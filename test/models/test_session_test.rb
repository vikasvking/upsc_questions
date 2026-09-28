require "test_helper"

class TestSessionTest < ActiveSupport::TestCase
  test "window status follows start and end times" do
    t = test_sessions(:one)
    assert_equal :live, t.window_status

    t.starts_at = 1.hour.from_now
    assert_equal :upcoming, t.window_status

    t.starts_at = 2.hours.ago
    t.ends_at = 1.hour.ago
    assert_equal :closed, t.window_status
  end

  test "end time must be after start time" do
    t = test_sessions(:one)
    t.starts_at = 1.hour.from_now
    t.ends_at = 1.hour.ago
    assert_not t.valid?
  end
end
