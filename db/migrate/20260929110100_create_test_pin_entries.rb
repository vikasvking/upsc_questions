# Who entered a test's PIN, so the teacher's live view can show students who have not started yet
class CreateTestPinEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :test_pin_entries do |t|
      t.references :test_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :test_pin_entries, [:test_session_id, :user_id], unique: true
  end
end
