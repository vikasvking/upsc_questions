class AddAdminLogsAndKeepTestsOfDeletedTeachers < ActiveRecord::Migration[8.1]
  def change
    # A deleted teacher's tests stay; they are then shown under their exam's name
    change_column_null :test_sessions, :user_id, true
    remove_foreign_key :test_sessions, :users
    add_foreign_key    :test_sessions, :users, on_delete: :nullify
    remove_foreign_key :questions, :users
    add_foreign_key    :questions, :users, on_delete: :nullify

    # Every admin change: who, what, why (reason is required for overrides of locked tests)
    create_table :admin_logs do |t|
      t.references :admin, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :admin_email, null: false # kept even if the admin account is deleted later
      t.string :action, null: false      # e.g. "update_locked_test", "delete_user"
      t.string :record_type
      t.bigint :record_id
      t.string :record_label             # e.g. the test title or user email at the time
      t.text   :reason
      t.jsonb  :details, default: {}, null: false
      t.datetime :created_at, null: false
    end
    add_index :admin_logs, :created_at
    add_index :admin_logs, [:record_type, :record_id]
  end
end
