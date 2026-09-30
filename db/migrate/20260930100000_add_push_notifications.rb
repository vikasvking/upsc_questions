# Push notifications to the mobile app through Firebase Cloud Messaging (see PushNotifier):
# the phones to send to, each student's on/off switches, and which tests were already announced.
class AddPushNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token, null: false
      t.string :platform, null: false, default: "android"
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :device_tokens, :token, unique: true

    add_column :users, :push_new_tests, :boolean, null: false, default: true
    add_column :users, :push_results, :boolean, null: false, default: true
    add_column :users, :push_reminders, :boolean, null: false, default: true

    add_column :test_sessions, :new_test_notified_at, :datetime
    add_column :test_sessions, :results_notified_at, :datetime
  end
end
