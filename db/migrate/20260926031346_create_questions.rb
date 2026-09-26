class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.integer :year
      t.string :q_no
      t.string :topic
      t.text :content
      t.text :option_a
      t.text :option_b
      t.text :option_c
      t.text :option_d
      t.string :correct_answer
      t.text :explanation

      t.timestamps
    end
  end
end
