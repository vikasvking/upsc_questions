class AddCreatorToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_reference :questions, :user, null: true, foreign_key: true
  end
end
