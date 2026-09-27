# app/models/question.rb
class Question < ApplicationRecord
  # Establish relationships safely
  belongs_to :user, optional: true
  has_many :user_responses, dependent: :destroy

  # Model level validation constraints
  validates :q_no, :topic, :content, :correct_answer, presence: true

  # 🚀 MANDATORY ARGUMENT MATCHING: Receives exactly 4 parameters from the controller
  def self.import_from_excel(file_path, exam_type_param, year_param, creator_id)
    # Open spreadsheet extension safely based on file parameters
    xlsx = if File.extname(file_path).downcase == ".xls"
             Roo::Spreadsheet.open(file_path, extension: :csv, csv_options: { col_sep: "\t" })
           else
             Roo::Spreadsheet.open(file_path)
           end

    header = xlsx.row(1)

    ActiveRecord::Base.transaction do
      (2..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]
        next if row["Question"].blank?

        Question.create!(
          user_id:        creator_id, # Links row strictly to your teacher ID profile
          year:           year_param.presence,
          exam_type:      exam_type_param.strip.upcase,
          q_no:           row["Q.No"],
          topic:          row["Topic"],
          content:        row["Question"],
          option_a:       row["Option A"],
          option_b:       row["Option B"],
          option_c:       row["Option C"],
          option_d:       row["Option D"],
          correct_answer: row["Correct Answer"],
          explanation:    row["Explanation"]
        )
      end
    end
  end
end
