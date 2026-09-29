class AddStrictTrackingToTestAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :test_attempts, :last_seen_at, :datetime   # last heartbeat from the test page
    add_column :test_attempts, :leave_count, :integer, default: 0, null: false
    add_column :test_attempts, :blocked_at, :datetime     # set when blocked; cleared when the teacher reinstates
    add_column :test_attempts, :block_reason, :string
    add_index  :test_attempts, [:test_session_id, :blocked_at]
  end
end
