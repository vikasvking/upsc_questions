require "test_helper"

class TestStylesHelperTest < ActionView::TestCase
  include TestStylesHelper
  include ApplicationHelper

  test "each kind of test has its own look" do
    open_test = test_sessions(:one)
    pin_test  = test_sessions(:two)
    assert_equal :open, test_kind(open_test)
    assert_equal :pin,  test_kind(pin_test)

    pin_test.strict_mode = true
    assert_equal :strict, test_kind(pin_test)
    assert_includes test_kind_badge(pin_test), "Strict"
    assert_includes test_style(pin_test)[:stripe], "border-l-red-600"
    assert_includes exam_chip("NEET"), "NEET"
  end
end
