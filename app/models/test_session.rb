# app/models/test_session.rb
class TestSession < ApplicationRecord
  include Audience

  ACCESS_TYPES = %w[open pin].freeze

  class Locked < StandardError; end

  # Set by the admin pages (with a reason, see AdminLog) to change a locked test on a teacher's request
  attr_accessor :admin_override

  # nil once the teacher's account is deleted; the test stays and is shown under its exam's name
  belongs_to :user, optional: true
  has_many :test_questions, dependent: :destroy
  has_many :questions, through: :test_questions
  has_many :test_attempts, dependent: :destroy
  has_many :test_pin_entries, dependent: :delete_all
  has_many :ratings, as: :rateable, dependent: :delete_all

  normalizes :exam_type, with: ->(v) { Exam.normalize(v) || v.to_s.strip.upcase.presence }

  validates :user, presence: true, on: :create
  validates :title, :exam_type, :pin_code, presence: true
  validates :pin_code, uniqueness: true
  validates :access_type, inclusion: { in: ACCESS_TYPES }
  validates :exam_type, inclusion: { in: Exam.codes, message: "must be one of: #{Exam.all.map(&:name).join(", ")}" }
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :pass_mark_percentage, numericality: { only_integer: true, in: 0..100 }
  validate  :window_is_valid
  validate  :not_locked, on: :update
  validate  :free_sample_rules

  after_update :refresh_open_deadlines, if: -> { saved_change_to_ends_at? || saved_change_to_duration_minutes? }

  before_validation :generate_secure_pin, on: :create

  # Tell students about the new test. A minute later, so the questions and the chosen audience
  # (saved right after the test itself) are in place.
  after_create_commit -> { NewTestNotificationJob.set(wait: 1.minute).perform_later(id) }

  scope :newest_first, -> { order(created_at: :desc) }

  # Everyone the test is shown to, plus students who already started it (they keep seeing their result)
  def self.visible_to(user)
    scope = super
    user && !user.admin? ? scope.or(where(id: user.test_attempts.select(:test_session_id))) : scope
  end

  # What a student may open, by their tier (see Tiers): Free -> sample tests only; Plus -> school tests plus
  # public tests in their exams; Warrior -> everything visible. Tests already started always stay open.
  def self.available_to(user)
    scope = visible_to(user)
    return scope unless user&.student?

    started = where(id: user.test_attempts.select(:test_session_id))
    case user.tier
    when "warrior" then scope
    when "plus"
      scope.where(visibility: %w[institution selected])
           .or(scope.where(exam_type: user.allowed_exam_codes))
           .or(scope.where(free_sample: true)).or(started)
    else scope.where(free_sample: true).or(started)
    end
  end

  def open_access? = access_type == "open"
  def pin_required? = access_type == "pin"
  def time_bound? = starts_at.present? || ends_at.present?
  def exam = Exam.find(exam_type)

  EDIT_LOCK_BEFORE = 10.minutes

  # Strict and time-bound tests cannot be changed from 10 minutes before they open (or once anyone
  # has started, or after they close), so every student sits the same paper under the same rules.
  # Judged on the saved values, so changing the times cannot be used to unlock a locked test.
  def editing_locked?(now = Time.current)
    return false if new_record?
    starts, ends = starts_at_in_database, ends_at_in_database
    return false unless strict_mode_in_database || starts || ends
    (starts && now >= starts - EDIT_LOCK_BEFORE) || (ends && now >= ends) || test_attempts.exists?
  end

  # Questions are saved as soon as they are assigned, so the lock is checked here too
  def question_ids=(ids)
    if editing_locked? && !admin_override
      new_ids = Array(ids).compact_blank.map(&:to_i).sort
      raise Locked, "“#{title}” is locked; only an admin can change its questions" unless new_ids == question_ids.sort
    end
    super
  end

  # Shown instead of the teacher once their account is deleted
  def author_name
    user ? user.display_name : exam.name
  end

  # When editing stops for a test that has not locked yet (nil if there is no opening time)
  def edit_lock_at
    starts_at && starts_at - EDIT_LOCK_BEFORE
  end

  # Strict tests need neither a PIN nor a closing time. What leaving the test page does:
  #   PIN tests  -> a warning, then the student is blocked until the teacher reinstates them
  #   open tests -> the test ends at once with the answers so far (nobody is there to reinstate the student)
  def ends_on_leave? = strict_mode? && !pin_required?

  # Strict tests only, while the test has not closed: the teacher's live panel
  def live_view?(now = Time.current)
    strict_mode? && window_status(now) != :closed
  end

  # :upcoming, :live or :closed
  def window_status(now = Time.current)
    return :upcoming if starts_at && now < starts_at
    return :closed   if ends_at && now >= ends_at
    :live
  end

  def available_now? = window_status == :live

  # Students see marks, rank and answers only after a strict test closes (a strict test without a closing time:
  # as soon as they submit). Teachers always see them.
  def results_released?(now = Time.current)
    !strict_mode? || ends_at.nil? || now >= ends_at
  end

  # Students may retake a test they have submitted as often as they like; tests with a closing time only after it
  def retakes_open?(now = Time.current)
    ends_at.nil? || now >= ends_at
  end

  # The attempt that counts for this student's rank (retakes never do)
  def first_attempt_for(user)
    test_attempts.first_tries.find_by(user: user)
  end

  Result = Struct.new(:attempt, :user, :rank, :correct, :wrong, :skipped, :unattempted, :total,
                      :marks, :max_marks, :percentage, :passed, :time_taken, keyword_init: true)

  # How the class did on one question. `picks`: the question's own letter => how many students chose it.
  QuestionStat = Struct.new(:question, :number, :students, :picks, :correct, :wrong, :skipped, :unattempted,
                            keyword_init: true) do
    def percent(count) = students.positive? ? (count * 100.0 / students).round(1) : 0.0
    def correct_pct = percent(correct)

    # The wrong option most students fell for: [letter, count], or nil when nobody answered wrongly
    def common_wrong
      letter, count = picks.except(question.correct_answer).max_by { |_, c| c }
      count.to_i.positive? ? [letter, count] : nil
    end
  end

  TopicStat = Struct.new(:topic, :questions, :correct_pct, keyword_init: true)

  # Question-wise analysis for the teacher (ranked attempts only: first tries, submitted, not blocked), in paper order
  def question_analysis
    tokens    = test_attempts.first_tries.finished.not_blocked.pluck(:token)
    questions = ordered_questions.to_a
    latest    = latest_answers(tokens, questions.map(&:id))

    questions.each_with_index.map do |q, i|
      choices = tokens.filter_map { |t| latest[[t, q.id]]&.first }
      picks   = choices.reject { |c| c == "SKIPPED" }.tally
      correct = picks.fetch(q.correct_answer, 0)
      QuestionStat.new(question: q, number: i + 1, students: tokens.size, picks: picks, correct: correct,
                       wrong: picks.values.sum - correct, skipped: choices.count("SKIPPED"),
                       unattempted: tokens.size - choices.size)
    end
  end

  # Topics (subjects) from weakest to strongest, by the share of correct answers
  def topic_analysis(stats = question_analysis)
    stats.group_by { |s| s.question.topic.presence || "Other" }.map do |topic, list|
      answers = list.sum(&:students)
      TopicStat.new(topic: topic, questions: list.size,
                    correct_pct: answers.positive? ? (list.sum(&:correct) * 100.0 / answers).round(1) : 0.0)
    end.sort_by { |t| [t.correct_pct, t.topic] }
  end

  # ---------- speed: results and the live view are shared, not recalculated for every page ----------
  #
  # A big test (500 students x 100 questions = 50,000 answers) is expensive to rank. Result pages, test cards and
  # teachers' pages all need the same ranking, so it is worked out once and shared by everyone (per server process):
  #   * reused as long as nothing changed (same "fingerprint": submitted attempts, questions, test settings);
  #   * also reused for up to RANKINGS_REUSE while students are still submitting, except when the page asks for
  #     a student who is not in it yet (they just submitted), so nobody misses their own rank.
  # The teachers' live panel is shared the same way for LIVE_REUSE (it refreshes every 15 seconds anyway).
  # Sharing is off in tests, where every test has its own data (see test/models/shared_results_test.rb).

  ONLINE_WITHIN   = 35.seconds # two missed heartbeats = "no signal" on the live panel
  RANKINGS_REUSE  = 15.seconds
  LIVE_REUSE      = 5.seconds
  SHARED_ENTRIES  = 200        # tests kept in memory; the oldest are dropped first

  LiveRow = Struct.new(:attempt, :user, :status, :answered, :seconds_silent, keyword_init: true)
  LiveSnapshot = Struct.new(:rows, :not_started, :counts, :total_questions, :refreshed_at, keyword_init: true)
  LIVE_ORDER = { no_signal: 0, blocked: 1, opening: 2, writing: 3, submitted: 4 }.freeze

  @shared = {}
  @shared_lock = Mutex.new

  class << self
    attr_accessor :share_results

    def shared_read(key) = @shared_lock.synchronize { @shared[key] }

    def shared_write(key, value)
      @shared_lock.synchronize do
        @shared.delete(key)
        @shared[key] = value
        @shared.shift while @shared.size > SHARED_ENTRIES
      end
      value
    end

    def clear_shared! = @shared_lock.synchronize { @shared.clear }
  end
  self.share_results = !Rails.env.test?

  # Submitted attempts ranked by marks under this test's exam scheme (see Exam) high to low,
  # then less time taken, then earlier submission. Equal marks and time share a rank (1, 2, 2, 4).
  # Only each student's first attempt is ranked: retakes are practice, taken after seeing the answers.
  # `for_attempt`: the attempt the page is about; a shared ranking without it is not reused.
  # Returns a frozen array: do not change it, it is shared.
  def rankings(for_attempt: nil)
    finish_expired_attempts!
    return compute_rankings unless self.class.share_results

    fingerprint = rankings_fingerprint
    entry = self.class.shared_read([:rankings, id])
    if entry && (entry[:fingerprint] == fingerprint ||
                 (entry[:computed_at] > RANKINGS_REUSE.ago && (for_attempt.nil? || entry[:attempt_ids].include?(for_attempt.id))))
      return entry[:results]
    end

    results = compute_rankings
    self.class.shared_write([:rankings, id], { fingerprint: fingerprint, computed_at: Time.current, results: results,
                                              attempt_ids: results.map { |r| r.attempt.id }.to_set })
    results
  end

  # Submits attempts whose time ran out (the student closed the page), in one query.
  # Blocked attempts stay open so a reinstated student can carry on.
  def finish_expired_attempts!(now = Time.current)
    test_attempts.first_tries.in_progress.not_blocked
                 .where("deadline_at < ?", now - TestAttempt::GRACE_PERIOD)
                 .find_each(&:finish!)
  end

  # Strict tests: blocks students whose test page went silent (closed tab, locked phone...).
  # Only the silent ones are loaded, instead of checking every attempt one by one.
  def block_silent_students!(now = Time.current)
    return unless strict_mode?
    test_attempts.first_tries.in_progress.not_blocked
                 .where("last_seen_at < ?", now - TestAttempt::LEAVE_TIMEOUT)
                 .where("deadline_at IS NULL OR deadline_at >= ?", now - TestAttempt::GRACE_PERIOD)
                 .find_each { |attempt| attempt.enforce_presence!(now) }
  end

  # The teachers' live panel (website and app): who is writing, silent, blocked or submitted
  def live_snapshot(now = Time.current)
    if self.class.share_results && (cached = self.class.shared_read([:live, id])) && cached.refreshed_at > now - LIVE_REUSE
      return cached
    end

    block_silent_students!(now)
    attempts = test_attempts.first_tries.includes(:user).to_a # retakes are practice, not the live test
    answered = UserResponse.where(test_session_token: attempts.map(&:token))
                           .group(:test_session_token).distinct.count(:question_id)
    rows = attempts.map do |a|
      status =
        if a.blocked? then :blocked
        elsif a.finished? || a.expired?(now) then :submitted
        elsif a.last_seen_at.nil? then :opening
        elsif now - a.last_seen_at <= ONLINE_WITHIN then :writing
        else :no_signal
        end
      LiveRow.new(attempt: a, user: a.user, status: status, answered: answered[a.token].to_i,
                  seconds_silent: a.last_seen_at && (now - a.last_seen_at).to_i)
    end
    rows.sort_by! { |r| [LIVE_ORDER[r.status], r.user.display_name.downcase] }
    not_started = test_pin_entries.includes(:user).where.not(user_id: attempts.map(&:user_id)).order(:created_at).to_a

    snapshot = LiveSnapshot.new(rows: rows.freeze, not_started: not_started.freeze, counts: rows.map(&:status).tally,
                                total_questions: questions.count, refreshed_at: now)
    self.class.share_results ? self.class.shared_write([:live, id], snapshot) : snapshot
  end

  # ---------- push notifications (see NewTestNotificationJob) ----------

  # The Firebase topic for a new public test with open access: its exam's students whose tier includes it
  # (sample tests: every student of that exam). Public PIN tests are not announced to everyone, since only
  # the teacher's own students have the PIN. nil for school and selected tests.
  def push_topic
    return nil unless visibility == "public" && open_access?
    "#{free_sample? ? "all" : "tests"}_#{exam_type}"
  end

  # School and selected tests: the students it is shown to who can open it on their tier
  def push_recipient_ids
    return [] if visibility == "public"

    candidate_ids =
      if visibility == "institution"
        Membership.approved.where(institution_id: institution_id).pluck(:user_id)
      else
        grants = audience_grants.to_a
        ids_of = ->(type) { grants.select { |g| g.grantee_type == type }.map(&:grantee_id) }
        ids_of.("User") +
          Membership.approved.where(institution_id: ids_of.("Institution")).pluck(:user_id) +
          BatchMember.where(batch_id: ids_of.("Batch")).pluck(:user_id)
      end
    User.student.where(id: candidate_ids.uniq).select { |u| TestSession.available_to(u).exists?(id) }.map(&:id)
  end

  # Questions in the order the teacher added them
  def ordered_questions
    questions.reorder("test_questions.id ASC")
  end

  # Accepts a real Excel file (.xlsx) or the tab-separated .xls template from the download button
  def self.import_from_excel(file_path, creator_id)
    if File.extname(file_path).downcase == ".xlsx"
      xlsx = Roo::Spreadsheet.open(file_path, extension: :xlsx)
    else
      raw_content = File.read(file_path, mode: "rb")

      normalized_text =
        if raw_content.start_with?("\xFF\xFE".b)
          raw_content.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        elsif raw_content.dup.force_encoding("UTF-8").valid_encoding?
          raw_content.force_encoding("UTF-8")
        else
          raw_content.force_encoding("ISO-8859-1").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        end

      temp_cleaned_file = Tempfile.new(["sanitized_test_import", ".xls"])
      temp_cleaned_file.write(normalized_text)
      temp_cleaned_file.rewind

      xlsx = Roo::Spreadsheet.open(temp_cleaned_file.path, extension: :csv, csv_options: { col_sep: "\t" })
    end

    settings_row = Hash[[xlsx.row(1).map { |h| h.to_s.strip }, xlsx.row(2)].transpose]
    access = settings_row["Access (Open/PIN)"].to_s.strip.downcase
    access = "pin" unless ACCESS_TYPES.include?(access)

    ActiveRecord::Base.transaction do
      test_session = TestSession.create!(
        user_id:              creator_id,
        title:                settings_row["Test Title"].to_s.strip,
        exam_type:            settings_row["Exam Portfolio"].to_s.strip.upcase,
        duration_minutes:     settings_row["Duration Minutes"].to_i,
        pass_mark_percentage: settings_row["Passing Percentage"].to_i,
        access_type:          access,
        starts_at:            parse_time(settings_row["Starts At"]),
        ends_at:              parse_time(settings_row["Ends At"])
      )

      header = xlsx.row(4).map { |h| h.to_s.strip }
      (5..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]
        next if row["Question"].blank?

        q = Question.create!(
          user_id:        creator_id,
          exam_type:      test_session.exam_type,
          year:           settings_row["Exam Year"].presence,
          topic:          Question.cell_text(row["Topic"]),
          content:        Question.cell_text(row["Question"]),
          option_a:       Question.cell_text(row["Option A"]),
          option_b:       Question.cell_text(row["Option B"]),
          option_c:       Question.cell_text(row["Option C"]),
          option_d:       Question.cell_text(row["Option D"]),
          correct_answer: Question.cell_text(row["Correct Answer"]),
          explanation:    Question.cell_text(row["Explanation"])
        )

        TestQuestion.create!(test_session: test_session, question: q)
      end

      test_session
    end
  ensure
    if temp_cleaned_file
      temp_cleaned_file.close
      temp_cleaned_file.unlink
    end
  end

  # Accepts "2026-10-05 10:00" style text; blank means "no limit"
  # Accepts "2026-10-05 10:00" text or a real Excel date/time cell. Blank means "no limit".
  # Excel cells have no time zone, so they are read as India time.
  def self.parse_time(value)
    return nil if value.blank?
    if value.respond_to?(:strftime)
      Time.zone.local(value.year, value.month, value.day,
                      value.respond_to?(:hour) ? value.hour : 0,
                      value.respond_to?(:min) ? value.min : 0)
    else
      Time.zone.parse(value.to_s)
    end
  end

  private

  # Changes whenever the ranking could change: a submission, a block or reinstatement, the questions or the test's settings
  def rankings_fingerprint
    attempts = test_attempts.first_tries.finished.not_blocked
                            .pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(test_attempts.updated_at)"))
    questions_sig = test_questions.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(test_questions.id)"))
    [updated_at, *attempts, *questions_sig]
  end

  # Works out the ranking (4 queries however many students). Answers are read as plain values rather than
  # loaded as records, which is several times faster for tens of thousands of answers.
  def compute_rankings
    attempts = test_attempts.first_tries.finished.not_blocked.includes(:user).to_a
    qids     = ordered_questions.pluck(:id)
    total    = qids.size
    latest   = latest_answers(attempts.map(&:token), qids)

    results = attempts.map do |a|
      answers = qids.filter_map { |qid| latest[[a.token, qid]] }
      correct = answers.count { |_, ok| ok }
      skipped = answers.count { |choice, _| choice == "SKIPPED" }
      wrong   = answers.size - correct - skipped
      pct     = total.positive? ? (correct * 100.0 / total).round(1) : 0.0
      Result.new(attempt: a, user: a.user, correct: correct, wrong: wrong, skipped: skipped,
                 unattempted: total - answers.size, total: total,
                 marks: exam.marks_for(correct, wrong), max_marks: (total * exam.correct).round(2),
                 percentage: pct, passed: pct >= pass_mark_percentage, time_taken: a.time_taken)
    end

    results.sort_by! { |r| [-r.marks, r.time_taken || Float::INFINITY, r.attempt.finished_at] }
    results.each_with_index do |r, i|
      prev = results[i - 1] if i.positive?
      r.rank = prev && prev.marks == r.marks && prev.time_taken == r.time_taken ? prev.rank : i + 1
    end
    results.freeze
  end

  # [token, question_id] => [choice, correct] for these attempts. Ordered by time, so the last answer wins.
  def latest_answers(tokens, question_ids)
    latest = {}
    UserResponse.where(test_session_token: tokens, question_id: question_ids)
                .order(:updated_at)
                .pluck(:test_session_token, :question_id, :chosen_option, :is_correct)
                .each { |token, qid, choice, correct| latest[[token, qid]] = [choice, correct] }
    latest
  end

  def generate_secure_pin
    self.pin_code ||= loop do
      pin = SecureRandom.alphanumeric(6).upcase
      break pin unless TestSession.exists?(pin_code: pin)
    end
  end

  def free_sample_rules
    return unless free_sample?
    errors.add(:free_sample, "tests must be visible to everyone") unless visibility == "public"
    others = TestSession.where(free_sample: true).where.not(id: id).count
    errors.add(:free_sample, "can be set on at most #{Tiers::FREE_SAMPLE_TESTS} tests; untick another first") if others >= Tiers::FREE_SAMPLE_TESTS
  end

  def not_locked
    return if admin_override || !has_changes_to_save? || !editing_locked?
    errors.add(:base, "This test is locked: tests with a time window or strict mode cannot be changed from " \
                      "#{EDIT_LOCK_BEFORE.in_minutes.to_i} minutes before they open, once a student has started, or after they close. " \
                      "Ask an admin to change it.")
  end

  # Students already writing get the new closing time / duration
  def refresh_open_deadlines
    test_attempts.in_progress.find_each do |a|
      limits = [a.started_at + duration_minutes.to_i.minutes, (ends_at unless a.retake?)].compact
      a.update_column(:deadline_at, limits.min)
    end
  end

  def window_is_valid
    if starts_at && ends_at && ends_at <= starts_at
      errors.add(:ends_at, "must be after the start time")
    end
  end
end
