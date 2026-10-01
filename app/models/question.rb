# app/models/question.rb
class Question < ApplicationRecord
  include Audience

  ANSWER_KEYS = %w[A B C D].freeze

  belongs_to :user, optional: true
  has_many :user_responses, dependent: :destroy
  has_many :test_questions, dependent: :destroy
  has_many :test_sessions, through: :test_questions
  has_many :question_reports, dependent: :delete_all

  after_update :remark_saved_answers, if: :saved_change_to_correct_answer?

  normalizes :correct_answer, with: ->(v) { v.to_s.strip.upcase }
  # "UPSC", "JEE Main", "jee_main" -> exam code (see Exam)
  normalizes :exam_type, with: ->(v) { Exam.normalize(v) || v.to_s.strip.upcase.presence }

  # q_no is no longer used (numbers clashed between uploads); old values stay in the database unused
  validates :topic, :content, :correct_answer, presence: true
  validates :correct_answer, inclusion: { in: ANSWER_KEYS, message: "must be A, B, C or D" }
  validates :exam_type, inclusion: { in: Exam.codes, message: "must be one of: #{Exam.all.map(&:name).join(", ")}" }, allow_blank: true

  validate :free_sample_rules

  def exam = Exam.find(exam_type)

  OPTION_COLUMNS = { "A" => :option_a, "B" => :option_b, "C" => :option_c, "D" => :option_d }.freeze

  # Options that refer to other options ("All of the above", "Both (a) and (b)", "A and C") only make sense in the
  # order they were written, so these questions keep that order even where strict tests shuffle options.
  # A false match only means the options are not shuffled for that question.
  FIXED_ORDER_PATTERNS = [
    /\b(all|none|both|neither)\b[^.]{0,30}\babove\b/i,
    /\(\s*[a-d]\s*\)/i,
    /\boption\s+[a-d]\b/i,
    /\b[A-D]\s*(,|&|and|or)\s*[A-D]\b/ # capitals only, so everyday words do not match
  ].freeze

  def option_text(letter) = public_send(OPTION_COLUMNS.fetch(letter))

  # Letters of the options that have text, in the order the question was written
  def option_letters = ANSWER_KEYS.select { |letter| option_text(letter).present? }

  def fixed_option_order?
    option_letters.any? { |letter| FIXED_ORDER_PATTERNS.any? { |pattern| pattern.match?(option_text(letter)) } }
  end

  # Free -> sample questions only; Plus -> their exams plus their school's private questions; Warrior -> all visible
  def self.available_to(user)
    scope = visible_to(user)
    return scope unless user&.student?

    case user.tier
    when "warrior" then scope
    when "plus"
      scope.where.not(visibility: "public").or(scope.where(exam_type: user.allowed_exam_codes)).or(scope.where(free_sample: true))
    else scope.where(free_sample: true)
    end
  end

  # What a student sees in the Question Bank. Free students see every visible question (to show what upgrading
  # unlocks), but can only answer the free samples: the rest are shown locked (see #locked_for?).
  # Everyone else sees exactly what they may answer.
  def self.listed_to(user)
    user&.student? && user.free_tier? ? visible_to(user) : available_to(user)
  end

  # Shown in the Question Bank but not answerable on this student's tier (Free: every question but the samples)
  def locked_for?(user)
    !!(user&.student? && user.free_tier? && !free_sample?)
  end

  # Tests using this question that are locked (see TestSession#editing_locked?)
  def locked_tests
    test_sessions.select(&:editing_locked?)
  end

  # Grouped by exam and year, then in the order the questions were added
  scope :in_order, -> { order(:exam_type, :year, :id) }

  # Returns the created questions. visibility/institution_id apply to every imported question.
  def self.import_from_excel(file_path, exam_type_param, year_param, creator_id, visibility: "public", institution_id: nil)
    # The downloadable template (.xls) is tab-separated text; real .xlsx files are opened natively.
    # An old "Q.No" column, if present, is simply ignored.
    xlsx = if File.extname(file_path).downcase == ".xls"
             Roo::Spreadsheet.open(file_path, extension: :csv, csv_options: { col_sep: "\t" })
           else
             Roo::Spreadsheet.open(file_path)
           end

    header = xlsx.row(1).map { |h| h.to_s.strip }

    ActiveRecord::Base.transaction do
      (2..xlsx.last_row).filter_map do |i|
        row = Hash[[header, xlsx.row(i)].transpose]
        next if row["Question"].blank?

        Question.create!(
          visibility:     visibility,
          institution_id: institution_id,
          user_id:        creator_id,
          year:           year_param.presence,
          exam_type:      exam_type_param.strip.upcase,
          topic:          cell_text(row["Topic"]),
          content:        cell_text(row["Question"]),
          option_a:       cell_text(row["Option A"]),
          option_b:       cell_text(row["Option B"]),
          option_c:       cell_text(row["Option C"]),
          option_d:       cell_text(row["Option D"]),
          correct_answer: cell_text(row["Correct Answer"]),
          explanation:    cell_text(row["Explanation"])
        )
      rescue ActiveRecord::RecordInvalid => e
        raise "Row #{i}: #{e.record.errors.full_messages.to_sentence}"
      end
    end
  end

  # Excel gives whole numbers back as 1.0 - store them as "1"
  def self.cell_text(value)
    value = value.to_i if value.is_a?(Float) && value == value.floor
    value.to_s.strip
  end

  private

  def free_sample_rules
    return unless free_sample?
    errors.add(:free_sample, "questions must be visible to everyone") unless visibility == "public"
    others = Question.where(free_sample: true).where.not(id: id).count
    errors.add(:free_sample, "can be set on at most #{Tiers::FREE_SAMPLE_QUESTIONS} questions; untick another first") if others >= Tiers::FREE_SAMPLE_QUESTIONS
  end

  # A corrected answer key re-marks every saved answer, so marks and ranks follow the fix
  def remark_saved_answers
    UserResponse.where(question_id: id).where.not(chosen_option: "SKIPPED")
                .update_all(["is_correct = (chosen_option = ?), updated_at = updated_at", correct_answer])
  end
end
