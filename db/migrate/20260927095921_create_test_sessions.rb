class CreateTestSessions < ActiveRecord::Migration[8.1]
  def change
   create_table :test_sessions do |t|
     t.references :user, null: false, foreign_key: true
     t.string :title, null: false
     t.string :exam_type, null: false
     t.integer :duration_minutes, default: 60
     t.integer :pass_mark_percentage, default: 50
     t.string :pin_code, null: false

     t.timestamps
   end

   # Secure unique index for rapid access PIN validation searches
   add_index :test_sessions, :pin_code, unique: true
  end
end
