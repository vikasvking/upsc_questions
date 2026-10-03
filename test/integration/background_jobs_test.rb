require "test_helper"

# A job that always fails, behind the leaderboard job's switch
class FailingSwitchedJob < ApplicationJob
  background_switch :refresh_leaderboard
  def perform = raise("boom")
end

# Admin → Background work: on/off switches for the scheduled jobs
class BackgroundJobsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:admin) }

  test "admin sees every background job, all on by default" do
    get admin_background_jobs_path
    assert_response :success
    BackgroundJobSetting::JOBS.each_value { |job| assert_match job.name, response.body }
    assert_match "All #{BackgroundJobSetting::JOBS.size} background jobs are", response.body
    assert_select "button", text: "Switch off", count: BackgroundJobSetting::JOBS.size
  end

  test "only full admins can open the page, not sub-admins or teachers" do
    sub_admin = users(:teacher)
    sub_admin.update!(permissions: ["questions"])
    assert sub_admin.reload.sub_admin?, "fixture teacher should be an approved teacher"

    sign_in_as sub_admin
    get admin_background_jobs_path
    assert_redirected_to admin_root_path
    patch admin_background_job_path("refresh_leaderboard"), params: { enabled: false }
    assert_redirected_to admin_root_path
    assert BackgroundJobSetting.enabled?(:refresh_leaderboard)

    sign_in_as users(:one)
    get admin_background_jobs_path
    assert_redirected_to dashboard_path
  end

  test "switching a job off stops it doing anything, is logged, and switching on brings it back" do
    users(:one).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, duration_seconds: 20)

    assert_difference -> { AdminLog.where(action: "update_background_job").count }, 1 do
      patch admin_background_job_path("refresh_leaderboard"), params: { enabled: false }
    end
    assert_redirected_to admin_background_jobs_path
    setting = BackgroundJobSetting.find_by!(key: "refresh_leaderboard")
    assert_not setting.enabled?
    assert_equal users(:admin), setting.updated_by
    assert_equal({ "enabled" => { "from" => true, "to" => false } }, AdminLog.newest_first.first.details)

    assert_no_difference -> { LeaderboardSnapshot.count } do
      RefreshLeaderboardJob.perform_now
    end
    assert_nil setting.reload.last_started_at, "a switched-off job should not record a run"

    follow_redirect!
    assert_match "1 job is OFF", response.body
    assert_match BackgroundJobSetting::JOBS["refresh_leaderboard"].warning, response.body
    assert_select "button", text: "Switch on", count: 1

    patch admin_background_job_path("refresh_leaderboard"), params: { enabled: true }
    assert BackgroundJobSetting.enabled?(:refresh_leaderboard)
    assert_difference -> { LeaderboardSnapshot.count }, 1 do
      RefreshLeaderboardJob.perform_now
    end
    setting.reload
    assert_equal "ok", setting.last_status
    assert setting.last_finished_at.present?
    assert_not setting.running?
  end

  test "saving the same state again is not logged twice" do
    patch admin_background_job_path("daily_practice_reminder"), params: { enabled: false }
    assert_no_difference -> { AdminLog.count } do
      patch admin_background_job_path("daily_practice_reminder"), params: { enabled: false }
    end
    assert_not BackgroundJobSetting.enabled?(:daily_practice_reminder)
  end

  test "a switched-off finish-expired job leaves the attempt open until switched back on" do
    expired = users(:one).test_attempts.create!(test_session: test_sessions(:one), started_at: 2.hours.ago)

    patch admin_background_job_path("finish_expired_attempts"), params: { enabled: false }
    FinishExpiredAttemptsJob.perform_now
    assert_not expired.reload.finished?

    patch admin_background_job_path("finish_expired_attempts"), params: { enabled: true }
    FinishExpiredAttemptsJob.perform_now
    assert expired.reload.finished?
  end

  test "switching off finish-expired asks for confirmation first" do
    get admin_background_jobs_path
    assert_select "#background_job_setting_#{BackgroundJobSetting.for(:finish_expired_attempts).id} [data-turbo-confirm]", 1
    assert_select "#background_job_setting_#{BackgroundJobSetting.for(:refresh_leaderboard).id} [data-turbo-confirm]", 0
  end

  test "a failed run is recorded with its error and the error is raised again" do
    assert_raises(RuntimeError) { FailingSwitchedJob.perform_now }
    setting = BackgroundJobSetting.find_by!(key: "refresh_leaderboard")
    assert setting.failed?
    assert_match "RuntimeError: boom", setting.last_error

    get admin_background_jobs_path
    assert_match "failed", response.body
    assert_match "RuntimeError: boom", response.body
  end

  test "unknown jobs are rejected" do
    patch admin_background_job_path("no_such_job"), params: { enabled: false }
    assert_response :not_found
    assert_raises(ArgumentError) { Class.new(ApplicationJob) { background_switch :no_such_job } }
  end

  test "the hourly clean-up is a switchable job class in the schedule" do
    schedule = YAML.load(ERB.new(File.read(Rails.root.join("config/recurring.yml"))).result)
    assert_equal "ClearFinishedJobsJob", schedule.dig("production", "clear_solid_queue_finished_jobs", "class")
    assert_equal "clear_finished_jobs", ClearFinishedJobsJob.background_switch_key
  end
end
