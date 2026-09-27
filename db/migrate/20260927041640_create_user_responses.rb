class CreateUserResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :user_responses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true
      t.string :chosen_option, null: false
      t.boolean :is_correct, null: false, default: false
      t.integer :duration_seconds, default: 0

      t.timestamps
    end

    # Compound tracking index for rapid user data calculation
    add_index :user_responses, [:user_id, :question_id]
  end
end
