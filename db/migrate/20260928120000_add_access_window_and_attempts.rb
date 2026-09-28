class AddAccessWindowAndAttempts < ActiveRecord::Migration[8.1]
  def up
    # 1. Test access + time window
    add_column :test_sessions, :access_type, :string, null: false, default: "pin"   # "open" or "pin"
    add_column :test_sessions, :starts_at, :datetime
    add_column :test_sessions, :ends_at, :datetime

    # 2. One row per student attempt (practice topic OR teacher test)
    create_table :test_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :test_session, null: true, foreign_key: true
      t.string   :topic
      t.string   :token, null: false
      t.datetime :started_at, null: false
      t.datetime :deadline_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :test_attempts, :token, unique: true
    add_index :test_attempts, [:user_id, :test_session_id]

    # 3. Fast lookup of answers inside one attempt
    add_index :user_responses, [:test_session_token, :question_id]

    # 4. Turn old practice runs into finished attempts so their results pages keep working
    execute <<~SQL
      INSERT INTO test_attempts (user_id, topic, token, started_at, finished_at, created_at, updated_at)
      SELECT ur.user_id, MIN(q.topic), ur.test_session_token, MIN(ur.created_at), MAX(ur.created_at), NOW(), NOW()
      FROM user_responses ur
      JOIN questions q ON q.id = ur.question_id
      WHERE ur.test_session_token IS NOT NULL
      GROUP BY ur.user_id, ur.test_session_token
    SQL
  end

  def down
    remove_index :user_responses, [:test_session_token, :question_id]
    drop_table :test_attempts
    remove_column :test_sessions, :ends_at
    remove_column :test_sessions, :starts_at
    remove_column :test_sessions, :access_type
  end
end
