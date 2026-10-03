# Admin → Background work: an on/off switch for each scheduled job, and how its last run went
class CreateBackgroundJobSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :background_job_settings do |t|
      t.string :key, null: false
      t.boolean :enabled, default: true, null: false
      t.datetime :last_started_at
      t.datetime :last_finished_at
      t.string :last_status
      t.text :last_error
      t.integer :last_duration_ms
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :background_job_settings, :key, unique: true
    add_index :background_job_settings, :updated_by_id
  end
end
