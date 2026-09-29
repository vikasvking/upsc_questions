class AddStrictModeToTestSessions < ActiveRecord::Migration[8.1]
  def change
    # Strict mode: students who leave the test get one warning, then are blocked until the teacher reinstates them
    add_column :test_sessions, :strict_mode, :boolean, default: false, null: false
  end
end
