# app/models/test_session.rb
class TestSession < ApplicationRecord
  belongs_to :user
  has_many :test_questions, dependent: :destroy
  has_many :questions, through: :test_questions

  validates :title, :exam_type, :pin_code, presence: true
  validates :pin_code, uniqueness: true

  before_validation :generate_secure_pin, on: :create

  # 🚀 PRODUCTION ENGINE: Automatically sanitizes corrupt Excel UTF-16/Windows-1252 byte streams
  def self.import_from_excel(file_path, creator_id)
    raw_content = File.read(file_path, mode: "rb") # Read as a pure binary block first

    # Detect and handle Excel standard UTF-16LE Little Endian byte tags cleanly
    if raw_content.start_with?("\xFF\xFE".force_encoding("BINARY"))
      normalized_text = raw_content.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    else
      # Fallback to general UTF-8 and strip any old Windows-1252 ANSI blocks
      normalized_text = raw_content.force_encoding("UTF-8").valid_encoding? ? raw_content : raw_content.force_encoding("ISO-8859-1").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    # Write the cleaned text string down to a temporary local cache wrapper file layer
    temp_cleaned_file = Tempfile.new(["sanitized_test_import", ".xls"])
    temp_cleaned_file.write(normalized_text)
    temp_cleaned_file.rewind

    # Roo reads the sanitized tab-separated matrix cleanly with zero encoding conflicts
    xlsx = Roo::Spreadsheet.open(temp_cleaned_file.path, extension: :csv, csv_options: { col_sep: "\t" })

    settings_row = Hash[[xlsx.row(1), xlsx.row(2)].transpose]

    ActiveRecord::Base.transaction do
      test_session = TestSession.create!(
        user_id:              creator_id,
        title:                settings_row["Test Title"].to_s.strip,
        exam_type:            settings_row["Exam Portfolio"].to_s.strip.upcase,
        duration_minutes:     settings_row["Duration Minutes"].to_i,
        pass_mark_percentage: settings_row["Passing Percentage"].to_i
      )

      header = xlsx.row(4)
      (5..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]
        next if row["Question"].blank?

        q = Question.create!(
          user_id:        creator_id,
          exam_type:      test_session.exam_type,
          year:           settings_row["Exam Year"].presence,
          q_no:           row["Q.No"].to_s.strip,
          topic:          row["Topic"].to_s.strip,
          content:        row["Question"].to_s.strip,
          option_a:       row["Option A"].to_s.strip,
          option_b:       row["Option B"].to_s.strip,
          option_c:       row["Option C"].to_s.strip,
          option_d:       row["Option D"].to_s.strip,
          correct_answer: row["Correct Answer"].to_s.strip.upcase,
          explanation:    row["Explanation"].to_s.strip
        )

        TestQuestion.create!(test_session: test_session, question: q)
      end
    end
  ensure
    # Cleanup memory buffers safely
    if temp_cleaned_file
      temp_cleaned_file.close
      temp_cleaned_file.unlink
    end
  end

  private

  def generate_secure_pin
    self.pin_code ||= SecureRandom.alphanumeric(6).upcase
  end
end
