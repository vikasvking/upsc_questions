# app/models/question.rb
class Question < ApplicationRecord
  ANSWER_KEYS = %w[A B C D].freeze

  belongs_to :user, optional: true
  has_many :user_responses, dependent: :destroy
  has_many :test_questions, dependent: :destroy

  normalizes :correct_answer, with: ->(v) { v.to_s.strip.upcase }
  normalizes :q_no, with: ->(v) { v.to_s.strip }

  validates :q_no, :topic, :content, :correct_answer, presence: true
  validates :correct_answer, inclusion: { in: ANSWER_KEYS, message: "must be A, B, C or D" }

  # Safe ordering: never crashes on q_no values like "12a" or "Q5".
  # Sorts by exam, year, then the digits inside q_no, then q_no text, then id.
  scope :in_order, -> {
    order(:exam_type, :year)
      .order(Arel.sql("NULLIF(regexp_replace(questions.q_no, '[^0-9]', '', 'g'), '')::bigint ASC NULLS LAST"))
      .order(:q_no, :id)
  }

  def self.import_from_excel(file_path, exam_type_param, year_param, creator_id)
    # The downloadable template (.xls) is tab-separated text; real .xlsx files are opened natively.
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
          q_no:           cell_text(row["Q.No"]),
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
