# app/models/test_session.rb
class TestSession < ApplicationRecord
  ACCESS_TYPES = %w[open pin].freeze

  belongs_to :user
  has_many :test_questions, dependent: :destroy
  has_many :questions, through: :test_questions
  has_many :test_attempts, dependent: :destroy

  validates :title, :exam_type, :pin_code, presence: true
  validates :pin_code, uniqueness: true
  validates :access_type, inclusion: { in: ACCESS_TYPES }
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :pass_mark_percentage, numericality: { only_integer: true, in: 0..100 }
  validate  :window_is_valid

  before_validation :generate_secure_pin, on: :create

  scope :newest_first, -> { order(created_at: :desc) }

  def open_access? = access_type == "open"
  def pin_required? = access_type == "pin"
  def time_bound? = starts_at.present? || ends_at.present?

  # :upcoming, :live or :closed
  def window_status(now = Time.current)
    return :upcoming if starts_at && now < starts_at
    return :closed   if ends_at && now >= ends_at
    :live
  end

  def available_now? = window_status == :live

  Result = Struct.new(:attempt, :user, :rank, :correct, :wrong, :skipped, :unattempted, :total,
                      :marks, :max_marks, :percentage, :passed, :time_taken, keyword_init: true)

  # Submitted attempts ranked UPSC-style: marks (+2 correct, -0.66 wrong, 0 skipped) high to low,
  # then less time taken, then earlier submission. Equal marks and time share a rank (1, 2, 2, 4).
  # Uses 3 queries no matter how many students took the test.
  def rankings
    test_attempts.in_progress.select(&:expired?).each(&:finish!)

    attempts = test_attempts.finished.includes(:user).to_a
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
                 marks: TestAttempt.marks_for(correct, wrong), max_marks: (total * TestAttempt::MARKS_CORRECT).round(2),
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
          q_no:           Question.cell_text(row["Q.No"]),
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

  def window_is_valid
    if starts_at && ends_at && ends_at <= starts_at
      errors.add(:ends_at, "must be after the start time")
    end
  end
end
