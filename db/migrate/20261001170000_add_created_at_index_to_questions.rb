# The home page always shows the newest public questions
class AddCreatedAtIndexToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_index :questions, [:visibility, :created_at]
  end
end
