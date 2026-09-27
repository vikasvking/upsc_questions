# app/models/question.rb
class Question < ApplicationRecord
  has_many :user_responses, dependent: :destroy
  validates :q_no, :topic, :content, :correct_answer, presence: true

  def self.import_from_excel(file_path, exam_type_param, year_param = nil)
    # 🚀 DYNAMIC DETECTOR: Choose the right parsing mode based on file extension
    xlsx = if File.extname(file_path).downcase == ".xls"
             # Opens our lightweight tab-delimited format with no zip requirements
             Roo::Spreadsheet.open(file_path, extension: :csv, csv_options: { col_sep: "\t" })
           else
             # Standard modern zipped XML format reader
             Roo::Spreadsheet.open(file_path)
           end

    header = xlsx.row(1)

    ActiveRecord::Base.transaction do
      (2..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]

        q_number = row["Q.No"]
        topic    = row["Topic"]
        content  = row["Question"]
        opt_a    = row["Option A"]
        opt_b    = row["Option B"]
        opt_c    = row["Option C"]
        opt_d    = row["Option D"]
        correct  = row["Correct Answer"]
        explain  = row["Explanation"]

        next if content.blank? && q_number.blank?

        Question.create!(
          year:           year_param.presence,
          exam_type:      exam_type_param.strip.upcase,
          q_no:           q_number.to_s.strip,
          topic:          topic.to_s.strip,
          content:        content.to_s.strip,
          option_a:       opt_a.to_s.strip,
          option_b:       opt_b.to_s.strip,
          option_c:       opt_c.to_s.strip,
          option_d:       opt_d.to_s.strip,
          correct_answer: correct.to_s.strip.upcase,
          explanation:    explain.to_s.strip
        )
      end
    end
  end
end
