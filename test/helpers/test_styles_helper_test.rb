require "test_helper"

class TestStylesHelperTest < ActionView::TestCase
  include TestStylesHelper
  include ApplicationHelper

  test "each kind of test has its own look" do
    open_test = test_sessions(:one)
    pin_test  = test_sessions(:two)
    assert_equal :open, kind_of_test(open_test)
    assert_equal :pin,  kind_of_test(pin_test)

    pin_test.strict_mode = true
    assert_equal :strict, kind_of_test(pin_test)
    assert_includes kind_badge_for(pin_test), "Strict"
    assert_includes style_for_test(pin_test)[:stripe], "border-l-red-600"
    assert_includes exam_chip("NEET"), "NEET"
  end
end
