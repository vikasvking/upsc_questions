require "test_helper"

class TestAttemptTest < ActiveSupport::TestCase
  test "teacher test deadline is start time plus duration" do
    test_session = test_sessions(:one)
    attempt = users(:one).test_attempts.create!(test_session: test_session)
    assert_in_delta attempt.started_at + 30.minutes, attempt.deadline_at, 1
  end

  test "deadline is cut short by the test's closing time" do
    test_session = test_sessions(:one)
    test_session.update!(ends_at: 10.minutes.from_now)
    attempt = users(:one).test_attempts.create!(test_session: test_session)
    assert_in_delta test_session.ends_at, attempt.deadline_at, 1
  end

  test "practice attempts have no deadline" do
    attempt = users(:one).test_attempts.create!(topic: "Physics")
    assert_nil attempt.deadline_at
    assert_not attempt.expired?
  end
end
