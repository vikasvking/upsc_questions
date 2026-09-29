# app/models/question.rb
class Question < ApplicationRecord
  ANSWER_KEYS = %w[A B C D].freeze

  belongs_to :user, optional: true
  has_many :user_responses, dependent: :destroy
  has_many :test_questions, dependent: :destroy

  normalizes :correct_answer, with: ->(v) { v.to_s.strip.upcase }
  # "UPSC", "JEE Main", "jee_main" -> exam code (see Exam)
  normalizes :exam_type, with: ->(v) { Exam.normalize(v) || v.to_s.strip.upcase.presence }

  # q_no is no longer used (numbers clashed between uploads); old values stay in the database unused
  validates :topic, :content, :correct_answer, presence: true
  validates :correct_answer, inclusion: { in: ANSWER_KEYS, message: "must be A, B, C or D" }
  validates :exam_type, inclusion: { in: Exam.codes, message: "must be one of: #{Exam.all.map(&:name).join(", ")}" }, allow_blank: true

  def exam = Exam.find(exam_type)

  # Grouped by exam and year, then in the order the questions were added
  scope :in_order, -> { order(:exam_type, :year, :id) }

  def self.import_from_excel(file_path, exam_type_param, year_param, creator_id)
    # The downloadable template (.xls) is tab-separated text; real .xlsx files are opened natively.
    # An old "Q.No" column, if present, is simply ignored.
    xlsx = if File.extname(file_path).downcase == ".xls"
             Roo::Spreadsheet.open(file_path, extension: :csv, csv_options: { col_sep: "\t" })
           else
             Roo::Spreadsheet.open(file_path)
           end

    header = xlsx.row(1).map { |h| h.to_s.strip }

    ActiveRecord::Base.transaction do
      (2..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]
        next if row["Question"].blank?

        Question.create!(
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
end
