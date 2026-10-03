# Admin → Background work: an on/off switch for each job the site runs on its own, and how its last run went.
# A switched-off job still comes round on its schedule (config/recurring.yml) but does nothing, so switching it
# back on resumes at the next run. Jobs opt in with `background_switch :key` (see ApplicationJob).
# A job with no row yet counts as on.
class BackgroundJobSetting < ApplicationRecord
  Job = Data.define(:key, :name, :schedule, :description, :warning)

  JOBS = [
    Job.new(key: "finish_expired_attempts", name: "Finish expired tests", schedule: "Every 5 minutes",
            description: "Submits tests whose time ran out while the student had the page closed, so teachers' results and ranks are complete.",
            warning: "While this is off, tests left open past their time stay unsubmitted until the student opens them again, " \
                     "so teachers' results and ranks can be incomplete."),
    Job.new(key: "refresh_leaderboard", name: "Refresh leaderboards", schedule: "Every 10 minutes",
            description: "Recomputes the topper table for each exam.",
            warning: "While this is off, the topper tables are only recomputed when someone opens them and the saved one is old, " \
                     "which makes those pages slower."),
    Job.new(key: "results_released_notifications", name: "Results-out notifications", schedule: "Every 5 minutes",
            description: "Tells students by push notification, with their rank, when a strict test closes and its results are out.",
            warning: "Strict tests that close while this is off are only announced if it is switched back on within a day."),
    Job.new(key: "new_test_notifications", name: "New test notifications", schedule: "A minute after a teacher creates a test",
            description: "Tells the students a new test is for, by push notification.",
            warning: "Tests created while this is off are never announced."),
    Job.new(key: "daily_practice_reminder", name: "Daily practice reminder", schedule: "Every day at 7 PM (India time)",
            description: "Reminds Plus and Warrior students who have not finished today's practice target.",
            warning: "No practice reminders are sent while this is off."),
    Job.new(key: "clear_finished_jobs", name: "Clear finished job records", schedule: "Every hour",
            description: "Deletes the records of jobs that have finished, so the database stays small.",
            warning: "While this is off, finished job records pile up in the database.")
  ].index_by(&:key).freeze

  belongs_to :updated_by, class_name: "User", optional: true

  validates :key, presence: true, uniqueness: true, inclusion: { in: JOBS.keys }

  def self.for(key)
    find_or_create_by!(key: key.to_s)
  rescue ActiveRecord::RecordNotUnique # created by another process at the same moment
    find_by!(key: key.to_s)
  end

  # On unless an admin switched it off
  def self.enabled?(key) = where(key: key.to_s).pick(:enabled) != false

  # One row per job, in the order of JOBS
  def self.all_jobs
    rows = where(key: JOBS.keys).index_by(&:key)
    JOBS.keys.map { |key| rows[key] || self.for(key) }
  end

  def job = JOBS.fetch(key)
  delegate :name, :schedule, :description, :warning, to: :job

  # update_columns, so updated_at keeps showing when the switch was last changed
  def record_start!(at = Time.current) = update_columns(last_started_at: at)

  def record_finish!(started_at, error: nil)
    now = Time.current
    update_columns(last_finished_at: now, last_status: error ? "failed" : "ok",
                   last_error: error && "#{error.class}: #{error.message}".truncate(1000),
                   last_duration_ms: ((now - started_at) * 1000).round)
  end

  def running? = last_started_at.present? && (last_finished_at.nil? || last_started_at > last_finished_at)
  def failed? = last_status == "failed"
end
