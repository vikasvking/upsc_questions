# "Mark for review": the questions a student flagged to look at again before submitting
class AddMarkedQuestionIdsToTestAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :test_attempts, :marked_question_ids, :bigint, array: true, default: [], null: false
  end
end
