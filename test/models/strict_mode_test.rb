require "test_helper"

class StrictModeTest < ActiveSupport::TestCase
  setup do
    @test = test_sessions(:two) # PIN test
    @test.update!(strict_mode: true, ends_at: 2.hours.from_now)
    @attempt = users(:one).test_attempts.create!(test_session: @test)
  end

  test "strict mode needs neither a PIN nor a closing time; open strict tests end on leaving" do
    t = test_sessions(:one) # open test, no closing time
    t.strict_mode = true
    assert t.valid?
    assert t.ends_on_leave?
    assert_not @test.ends_on_leave? # PIN tests warn, then block
    assert t.results_released?      # no closing time: results as soon as a student submits
  end

  test "open strict tests: leaving ends the test with the answers so far, and says why" do
    open = test_sessions(:one)
    open.update!(strict_mode: true)
    attempt = users(:two).test_attempts.create!(test_session: open, started_at: 5.minutes.ago)
    users(:two).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, test_session_token: attempt.token)

    assert_equal :ended, attempt.record_violation!("switched to another tab or app for 12s", left_at: 12.seconds.ago)
    attempt.reload
    assert attempt.finished?
    assert_not attempt.blocked?
    assert_in_delta 12.seconds.ago, attempt.finished_at, 2
    assert_match "because you switched to another tab or app for 12s", attempt.ended_message
    assert_match "Your 1 answered question was submitted and marked.", attempt.ended_message
    assert_equal [attempt], open.rankings.map(&:attempt) # ranked on what was answered
    assert_equal :ignored, attempt.record_violation!("left again")
  end

  test "open strict tests: a silent page ends the test at the moment it was last heard from" do
    open = test_sessions(:one)
    open.update!(strict_mode: true)
    attempt = users(:two).test_attempts.create!(test_session: open, started_at: 10.minutes.ago)
    attempt.record_presence!(3.minutes.ago)
    attempt.enforce_presence!
    attempt.reload
    assert attempt.finished?
    assert_not attempt.blocked?
    assert attempt.ended_early?
    assert_in_delta 3.minutes.ago, attempt.finished_at, 2
  end

  test "first leave warns, second leave blocks" do
    assert_equal :warned, @attempt.record_violation!("tab")
    assert_not @attempt.reload.blocked?
    assert_equal 0, @attempt.warnings_left

    assert_equal :blocked, @attempt.record_violation!("tab again")
    assert @attempt.reload.blocked?
    assert_equal "tab again", @attempt.block_reason
  end

  test "leaves are ignored on tests without strict mode" do
    @test.update_columns(strict_mode: false) # the test is locked once started, so skip validations here
    assert_equal :ignored, @attempt.reload.record_violation!("tab")
    assert_equal 0, @attempt.reload.leave_count
  end

  test "a silent test page gets the student blocked" do
    @attempt.record_presence!(3.minutes.ago)
    @attempt.enforce_presence!
    assert @attempt.reload.blocked?
  end

  test "a recent heartbeat keeps the student in" do
    @attempt.record_presence!(10.seconds.ago)
    @attempt.enforce_presence!
    assert_not @attempt.reload.blocked?
  end

  test "reinstating gives back the blocked time, capped at the closing time" do
    @attempt.update!(deadline_at: 20.minutes.from_now)
    @attempt.block!("left", 10.minutes.ago)

    @attempt.reinstate!
    @attempt.reload
    assert_not @attempt.blocked?
    assert_equal 0, @attempt.leave_count
    assert_in_delta 30.minutes.from_now, @attempt.deadline_at, 5

    @attempt.update!(deadline_at: 110.minutes.from_now)
    @attempt.block!("left", 30.minutes.ago)
    @attempt.reinstate!
    assert_in_delta @test.ends_at, @attempt.reload.deadline_at, 1
  end

  test "blocked students are left out of the rankings and are not auto-submitted" do
    @attempt.update!(deadline_at: 1.minute.ago)
    @attempt.block!("left")

    assert_empty @test.rankings
    assert_not @attempt.reload.finished?
  end

  test "results are released only after a strict test closes" do
    assert_not @test.results_released?
    assert @test.results_released?(3.hours.from_now)
    assert test_sessions(:one).results_released?
  end
end
