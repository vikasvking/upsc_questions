
  # app/models/question.rb
class Question < ApplicationRecord
  has_many :user_responses,dependent: :destroy
  validates :q_no, :topic, :content, :correct_answer, presence: true
  def self.import_from_excel(file_path, year)
    xlsx = Roo::Spreadsheet.open(file_path)
    header = xlsx.row(1)

    ActiveRecord::Base.transaction do
      (2..xlsx.last_row).each do |i|
        row = Hash[[header, xlsx.row(i)].transpose]

        Question.create!(
          year:           year,
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
