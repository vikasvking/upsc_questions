# app/models/test_attempt.rb
# One student's run through either a practice topic or a teacher's test.
class TestAttempt < ApplicationRecord
  GRACE_PERIOD = 30.seconds # allows for slow networks on the final auto-submit

  # Strict mode (see TestSession#strict_mode)
  HEARTBEAT_EVERY  = 15.seconds # how often the test page pings the server while visible
  LEAVE_TIMEOUT    = 90.seconds # no ping for this long = the student left (closed the tab, locked the phone...)
  AWAY_GRACE       = 5.seconds  # being away for less than this is ignored (page refresh, a quick glance)
  WARNINGS_ALLOWED = 1          # leaves that only warn; the next one blocks

  belongs_to :user
  belongs_to :test_session, optional: true
  has_many :user_responses, primary_key: :token, foreign_key: :test_session_token, inverse_of: false

  validates :token, presence: true, uniqueness: true
  validate  :topic_or_test_present

  before_validation :set_defaults, on: :create

  scope :finished,    -> { where.not(finished_at: nil) }
  scope :in_progress, -> { where(finished_at: nil) }
  scope :blocked,     -> { where.not(blocked_at: nil) }
  scope :not_blocked, -> { where(blocked_at: nil) }
  # A student's first attempt at a teacher test is the one that is ranked; retakes are practice
  scope :first_tries, -> { where(retake: false) }
  scope :retakes,     -> { where(retake: true) }

  # The student's most recent attempt at a teacher test (a retake once they have retaken it)
  def self.latest_for(user, test_session)
    user.test_attempts.where(test_session: test_session).order(:id).last
  end

  # Starts the student's ranked attempt at a teacher test. Two taps on Start, or the website and the app at the
  # same moment, can both get here: the database lets only one through (see the one-first-try index) and the
  # other request gets that same attempt back.
  def self.start_first_try!(user, test_session)
    user.test_attempts.create!(test_session: test_session)
  rescue ActiveRecord::RecordNotUnique
    user.test_attempts.first_tries.find_by!(test_session: test_session)
  end

  def questions
    if test_session
      # Strict tests show each student the questions in their own order, so answers can't be passed around a classroom
      test_session.strict_mode? ? shuffled(test_session.questions) : test_session.ordered_questions
    else
      Question.available_to(user).where(topic: topic).in_order
    end
  end

  # ---------- options (strict tests shuffle them for each student too) ----------
  #
  # The student sees A, B, C, D in their own order; what is saved is always the question's own letter, so marks,
  # rankings, re-marking after a corrected answer key and the teacher's reports all work as before.

  def shuffles_options_of?(question)
    (test_session&.strict_mode? || false) && !question.fixed_option_order?
  end

  # The options as this student sees them: [[letter shown, the question's own letter, text], ...]
  def options_for(question)
    own = question.option_letters
    return own.map { |letter| [letter, letter, question.option_text(letter)] } unless shuffles_options_of?(question)

    own.sort_by { |letter| Digest::MD5.hexdigest("#{token}:#{question.id}:#{letter}") }
       .each_with_index.map { |letter, i| [Question::ANSWER_KEYS[i], letter, question.option_text(letter)] }
  end

  # Letter picked on screen -> the question's own letter; nil when it is not one of the options
  def own_letter(question, shown)
    options_for(question).find { |s, _, _| s == shown.to_s.strip.upcase }&.second
  end

  # The question's own letter -> the letter this student saw it as ("SKIPPED" and nil are returned as they are)
  def shown_letter(question, own)
    return own unless Question::ANSWER_KEYS.include?(own)
    options_for(question).find { |_, o, _| o == own }&.first || own
  end

  # ---------- going over answers before submitting ----------

  # Teacher tests stay open until the student presses Submit (or the time runs out), so they can go back over
  # their answers as in the real exam. Topic practice still finishes by itself after the last question.
  def submits_when_all_answered? = test_session.nil?

  def marked?(question) = marked_question_ids.include?(question.id)

  # "Mark for review" on (true) or off (false)
  def mark!(question, on = true)
    ids = on ? (marked_question_ids | [question.id]) : (marked_question_ids - [question.id])
    update_column(:marked_question_ids, ids) unless ids == marked_question_ids
  end

  # Marked questions that are still part of the test, in paper order
  def marked_ids_in(questions) = questions.map(&:id) & marked_question_ids

  def title
    test_session ? test_session.title : topic
  end

  def finished? = finished_at.present?
  def timed?    = deadline_at.present?
  # Retakes are practice, so nobody watches them
  def strict?   = !retake? && (test_session&.strict_mode? || false)
  def blocked?  = blocked_at.present?

  # A submitted attempt at a teacher test can be followed by practice retakes, as many as the student likes.
  # Tests with a closing time allow them only once they have closed.
  def retake_allowed?(now = Time.current)
    test_session.present? && !blocked? && (finished? || expired?(now)) && test_session.retakes_open?(now)
  end

  # ---------- strict mode ----------
  #
  # PIN tests warn once, then block the student until the teacher reinstates them.
  # Open tests have nobody to reinstate the student, so leaving ends the attempt at once: the answers so far are
  # submitted and marked, and ended_reason says why (see TestSession#ends_on_leave?).

  def ends_on_leave? = strict? && test_session.ends_on_leave?
  def ended_early?   = ended_reason.present?

  # What the student is told on their result: when and why the test ended, and what was kept
  def ended_message
    return nil unless ended_early?
    answered = user_responses.where(question_id: questions.select(:id)).distinct.count(:question_id)
    kept = answered.zero? ? "No questions had been answered." : "Your #{answered} answered #{answered == 1 ? "question was" : "questions were"} submitted and marked."
    "Your test ended at #{I18n.l(finished_at, format: :short)} because you #{ended_reason}. #{kept}"
  end

  # True while the student can still get into trouble for leaving
  def watched?(now = Time.current)
    strict? && !finished? && !blocked? && !expired?(now)
  end

  # Called on every heartbeat and test page load
  def record_presence!(now = Time.current)
    update_column(:last_seen_at, now)
  end

  # Blocks the student (open tests: ends the attempt) if the test page has been silent for too long.
  # Runs whenever the attempt is touched, so no background job is needed.
  def enforce_presence!(now = Time.current)
    return unless watched?(now) && last_seen_at && now - last_seen_at > LEAVE_TIMEOUT

    if ends_on_leave?
      # it ends when the page was last heard from: nothing could be answered after that
      end_early!("closed the test page or lost connection for over #{LEAVE_TIMEOUT.in_minutes.round(1)} minutes", last_seen_at)
    else
      block!("No connection from the test page for over #{LEAVE_TIMEOUT.in_minutes.round(1)} minutes", now)
    end
  end

  # The test page reported that the student left. Returns :warned, :blocked, :ended or :ignored.
  # `reason` reads after "you" ("switched to another tab or app for 12s"); `left_at`: when they left.
  def record_violation!(reason, now = Time.current, left_at: now)
    with_lock do
      if !watched?(now)
        :ignored
      elsif ends_on_leave?
        self.leave_count += 1
        end_early!(reason, left_at)
        :ended
      elsif leave_count + 1 > WARNINGS_ALLOWED
        self.leave_count += 1
        block!(reason, now)
        :blocked
      else
        self.leave_count += 1
        save!
        :warned
      end
    end
  end

  def warnings_left
    [WARNINGS_ALLOWED - leave_count, 0].max
  end

  def block!(reason, now = Time.current)
    update!(blocked_at: now, block_reason: reason.to_s.truncate(250))
  end

  # Open strict tests: submit the attempt as it stands, at the moment the student left (never after the deadline)
  def end_early!(reason, at = Time.current)
    ended = [[at, started_at].max, deadline_at].compact.min
    update!(finished_at: ended, ended_reason: reason.to_s.truncate(250))
  end

  # Teacher lets the student continue. The time spent blocked is given back,
  # but never beyond the test's closing time.
  def reinstate!(now = Time.current)
    return false unless blocked?

    new_deadline = deadline_at && [deadline_at + (now - blocked_at), test_session&.ends_at].compact.min
    update!(blocked_at: nil, block_reason: nil, leave_count: 0, last_seen_at: nil, deadline_at: new_deadline)
  end

  # Strict tests hide marks, rank and answers until the test closes
  def results_released?(now = Time.current)
    retake? || !test_session || test_session.results_released?(now)
  end

  def expired?(now = Time.current)
    timed? && now > deadline_at + GRACE_PERIOD
  end

  def seconds_left(now = Time.current)
    return nil unless timed?
    [(deadline_at - now).to_i, 0].max
  end

  def finish!
    update!(finished_at: [Time.current, deadline_at].compact.min) unless finished?
  end

  # Latest answer for each question in this attempt, keyed by question_id
  def responses_by_question
    user_responses.order(:updated_at).index_by(&:question_id)
  end

  # Marking scheme: the teacher test's exam; topic practice uses UPSC Prelims marking
  def exam
    test_session ? test_session.exam : Exam::DEFAULT
  end

  # Seconds from Start to Submit
  def time_taken
    return nil unless finished_at
    (finished_at - started_at).to_i
  end

  def score_summary
    question_ids = questions.pluck(:id)
    total     = question_ids.size
    # ignore answers to questions a teacher later removed from the test
    responses = responses_by_question.values_at(*question_ids).compact
    correct   = responses.count(&:is_correct)
    skipped   = responses.count { |r| r.chosen_option == "SKIPPED" }
    wrong     = responses.size - correct - skipped
    pct       = total.positive? ? (correct * 100.0 / total).round(1) : 0.0
    passed    = test_session ? pct >= test_session.pass_mark_percentage : nil

    { total: total, correct: correct, wrong: wrong, skipped: skipped,
      unattempted: total - responses.size, percentage: pct, passed: passed,
      marks: exam.marks_for(correct, wrong), max_marks: (total * exam.correct).round(2),
      time_taken: time_taken }
  end

  private

  # Each student gets their own order, worked out from the attempt's token: the same on every
  # refresh and device, different for every student, and nothing extra to store
  def shuffled(scope)
    scope.reorder(Arel.sql("md5(#{self.class.connection.quote(token)} || questions.id::text)"))
  end

  def set_defaults
    self.token      ||= SecureRandom.hex(8)
    self.started_at ||= Time.current

    if test_session && deadline_at.nil?
      # a retake gets the full duration: the test's closing time has already passed
      limits = [started_at + test_session.duration_minutes.to_i.minutes, (test_session.ends_at unless retake?)].compact
      self.deadline_at = limits.min
    end
  end

  def topic_or_test_present
    errors.add(:base, "Attempt needs a topic or a test") if topic.blank? && test_session_id.blank?
  end
end
