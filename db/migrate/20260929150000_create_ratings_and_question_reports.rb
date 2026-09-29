class CreateRatingsAndQuestionReports < ActiveRecord::Migration[8.1]
  def change
    # 1-5 stars (and an optional comment) from a student for a test or a teacher; one per student per item
    create_table :ratings do |t|
      t.string :rateable_type, null: false # TestSession or User (a teacher)
      t.bigint :rateable_id, null: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade } # the student
      t.integer :stars, null: false
      t.text :comment
      t.datetime :comment_hidden_at # an admin hid an abusive comment; the stars still count
      t.references :comment_hidden_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :ratings, [:rateable_type, :rateable_id, :user_id], unique: true, name: "index_ratings_one_per_student"
    add_index :ratings, [:rateable_type, :rateable_id]

    # "Report a problem" on a question: goes to the question's teacher and to admins
    create_table :question_reports do |t|
      t.references :question, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade } # who reported it
      t.string :kind, null: false             # wrong_answer, typo, unclear, other
      t.text :message
      t.string :status, null: false, default: "open" # open, fixed, dismissed
      t.text :response                         # the teacher's or admin's reply
      t.references :resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :question_reports, [:status, :created_at]
  end
end
