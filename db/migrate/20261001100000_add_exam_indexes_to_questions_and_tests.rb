# Lists of questions and tests are shown one exam at a time (exam tabs) and page by page
class AddExamIndexesToQuestionsAndTests < ActiveRecord::Migration[8.1]
  def change
    add_index :questions, [:exam_type, :year, :id]       # Question.in_order within one exam
    add_index :questions, [:exam_type, :topic]           # topic menus and filters per exam
    add_index :test_sessions, [:exam_type, :created_at]  # newest tests of one exam
  end
end
