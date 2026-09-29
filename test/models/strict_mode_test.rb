require "test_helper"

class StrictModeTest < ActiveSupport::TestCase
  setup do
    @test = test_sessions(:two) # PIN test
    @test.update!(strict_mode: true, ends_at: 2.hours.from_now)
    @attempt = users(:one).test_attempts.create!(test_session: @test)
  end

  test "strict mode needs PIN access and a closing time" do
    t = test_sessions(:one) # open test
    t.strict_mode = true
    assert_not t.valid?
    assert_includes t.errors[:strict_mode], "needs PIN access"
    assert_includes t.errors[:strict_mode], "needs a closing time (results are shown after it)"
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
