class AddExamTypeToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :exam_type, :string
    change_column_null :questions, :year, true
  end
end
