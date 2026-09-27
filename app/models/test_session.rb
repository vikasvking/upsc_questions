class TestSession < ApplicationRecord
  belongs_to :user
  has_many :test_questions, dependent: :destroy
  has_many :questions, through: :test_questions

  validates :title, :exam_type, :pin_code, presence: true
  validates :pin_code, uniqueness: true

  before_validation :generate_secure_pin, on: :create

  # 🚀 REUSED EXCEL ENGINE: Bulk generates a test and creates/links its questions in one transaction
  def self.import_from_excel(file_path, creator_id)
    xlsx = Roo::Spreadsheet.open(file_path, extension: :csv, csv_options: { col_sep: "\t" })

    # Row 2 contains master session settings data metadata tokens
    settings_row = Hash[[xlsx.row(1), xlsx.row(2)].transpose]

    ActiveRecord::Base.transaction do
      test_session = TestSession.create!(
        user_id: creator_id,
        title: settings_row["Test Title"].to_s.strip,
        exam_type: settings_row["Exam Portfolio"].to_s.strip.upcase,
        duration_minutes: settings_row["Duration Minutes"].to_i,
        pass_mark_percentage: settings_row["Passing Percentage"].to_i
      )

      # Rows 5+ contain the specific question nodes to create and attach
      header = xlsx.row(4)
      (5..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]
        next if row["Question"].blank?

        q = Question.create!(
          user_id: creator_id,
          exam_type: test_session.exam_type,
          year: settings_row["Exam Year"].presence,
          q_no: row["Q.No"].to_s.strip,
          topic: row["Topic"].to_s.strip,
          content: row["Question"].to_s.strip,
          option_a: row["Option A"].to_s.strip,
          option_b: row["Option B"].to_s.strip,
          option_c: row["Option C"].to_s.strip,
          option_d: row["Option D"].to_s.strip,
          correct_answer: row["Correct Answer"].to_s.strip.upcase,
          explanation: row["Explanation"].to_s.strip
        )

        TestQuestion.create!(test_session: test_session, question: q)
      end
    end
  end

  private

  def generate_secure_pin
    self.pin_code ||= SecureRandom.alphanumeric(6).upcase
  end
end
