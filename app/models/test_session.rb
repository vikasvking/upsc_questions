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
  validate  :strict_mode_is_valid
  validate  :not_locked, on: :update

  after_update :refresh_open_deadlines, if: -> { saved_change_to_ends_at? || saved_change_to_duration_minutes? }

  before_validation :generate_secure_pin, on: :create

  scope :newest_first, -> { order(created_at: :desc) }

  # Everyone the test is shown to, plus students who already started it (they keep seeing their result)
  def self.visible_to(user)
    scope = super
    user && !user.staff? ? scope.or(where(id: user.test_attempts.select(:test_session_id))) : scope
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

  # Students see marks, rank and answers only after a strict test closes. Teachers always see them.
  def results_released?(now = Time.current)
    !strict_mode? || ends_at.nil? || now >= ends_at
  end

  Result = Struct.new(:attempt, :user, :rank, :correct, :wrong, :skipped, :unattempted, :total,
                      :marks, :max_marks, :percentage, :passed, :time_taken, keyword_init: true)

  # Submitted attempts ranked by marks under this test's exam scheme (see Exam) high to low,
  # then less time taken, then earlier submission. Equal marks and time share a rank (1, 2, 2, 4).
  # Uses 3 queries no matter how many students took the test.
  def rankings
    # blocked attempts stay open so a reinstated student can carry on
    test_attempts.in_progress.not_blocked.select(&:expired?).each(&:finish!)

    attempts = test_attempts.finished.not_blocked.includes(:user).to_a
    qids     = ordered_questions.pluck(:id)
    total    = qids.size
    latest   = UserResponse.where(test_session_token: attempts.map(&:token), question_id: qids)
                           .order(:updated_at)
                           .index_by { |r| [r.test_session_token, r.question_id] }

    results = attempts.map do |a|
      answers = qids.filter_map { |qid| latest[[a.token, qid]] }
      correct = answers.count(&:is_correct)
      skipped = answers.count { |r| r.chosen_option == "SKIPPED" }
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

  def generate_secure_pin
    self.pin_code ||= loop do
      pin = SecureRandom.alphanumeric(6).upcase
      break pin unless TestSession.exists?(pin_code: pin)
    end
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
      limits = [a.started_at + duration_minutes.to_i.minutes, ends_at].compact
      a.update_column(:deadline_at, limits.min)
    end
  end

  def strict_mode_is_valid
    return unless strict_mode?
    errors.add(:strict_mode, "needs PIN access") unless pin_required?
    errors.add(:strict_mode, "needs a closing time (results are shown after it)") if ends_at.blank?
  end

  def window_is_valid
    if starts_at && ends_at && ends_at <= starts_at
      errors.add(:ends_at, "must be after the start time")
    end
  end
end
