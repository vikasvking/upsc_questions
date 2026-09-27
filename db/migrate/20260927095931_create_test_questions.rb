class CreateTestQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :test_questions do |t|
      t.references :test_session, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true

      t.timestamps
    end
  end
end
