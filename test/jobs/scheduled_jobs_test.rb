require "test_helper"

class ScheduledJobsTest < ActiveJob::TestCase
  test "refresh leaderboard job saves a snapshot that dashboards read" do
    users(:one).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, duration_seconds: 20)

    assert_difference -> { LeaderboardSnapshot.count }, 1 do
      RefreshLeaderboardJob.perform_now
    end
    assert_equal [users(:one).id], Leaderboard.rows.map(&:user_id)
    assert_equal 12.0, Leaderboard.rows.first.score # read back from the saved snapshot
  end

  test "old snapshot is recomputed on the spot when the scheduler is not running" do
    LeaderboardSnapshot.create!(rows: [], computed_at: 1.hour.ago)
    users(:one).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, duration_seconds: 20)

    assert_equal [users(:one).id], Leaderboard.rows.map(&:user_id)
    assert LeaderboardSnapshot.latest.computed_at > 1.minute.ago
  end

  test "finish expired attempts job submits tests whose time ran out" do
    expired = users(:one).test_attempts.create!(test_session: test_sessions(:one), started_at: 2.hours.ago)
    running = users(:two).test_attempts.create!(test_session: test_sessions(:one))

    FinishExpiredAttemptsJob.perform_now

    assert expired.reload.finished?
    assert_equal expired.deadline_at.to_i, expired.finished_at.to_i
    assert_not running.reload.finished?
  end
end
