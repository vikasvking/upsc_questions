require "test_helper"

# Strict tests shuffle each question's options for each student (see TestAttempt#options_for)
class OptionShuffleTest < ActiveSupport::TestCase
  setup do
    @test = test_sessions(:one) # questions one (answer A) and two (answer B)
    @test.update!(access_type: "pin", strict_mode: true, ends_at: 2.hours.from_now)
    @question = questions(:one)
  end

  test "a strict attempt shows every option once, under the letters A to D" do
    attempt = users(:one).test_attempts.create!(test_session: @test)
    options = attempt.options_for(@question)

    assert_equal %w[A B C D], options.map(&:first)
    assert_equal %w[A B C D], options.map(&:second).sort
    assert_equal %w[Joule Newton Pascal Watt], options.map(&:third).sort
    assert_equal options, attempt.reload.options_for(@question), "the same order every time the page loads"
  end

  test "letters on screen turn back into the question's own letters" do
    attempt = users(:one).test_attempts.create!(test_session: @test)
    attempt.options_for(@question).each do |shown, own, _|
      assert_equal own, attempt.own_letter(@question, shown)
      assert_equal shown, attempt.shown_letter(@question, own)
    end
    assert_nil attempt.own_letter(@question, "E")
    assert_equal "SKIPPED", attempt.shown_letter(@question, "SKIPPED")
    assert_nil attempt.shown_letter(@question, nil)
  end

  test "students get different orders" do
    orders = 12.times.map do |i|
      TestAttempt.new(test_session: @test, token: "token#{i}").options_for(@question).map(&:second)
    end
    assert orders.uniq.size > 1
  end

  test "tests without strict mode, and options that point at other options, keep the written order" do
    plain = users(:one).test_attempts.create!(test_session: test_sessions(:two))
    assert_equal [%w[A A Newton], %w[B B Joule], %w[C C Watt], %w[D D Pascal]], plain.options_for(@question)

    @question.update!(option_d: "None of the above")
    strict = users(:one).test_attempts.create!(test_session: @test)
    assert @question.fixed_option_order?
    assert_equal %w[A B C D], strict.options_for(@question).map(&:second)
  end

  test "a blank option is left out and the rest are lettered without a gap" do
    @question.update!(option_c: "")
    attempt = users(:one).test_attempts.create!(test_session: @test)
    options = attempt.options_for(@question)
    assert_equal %w[A B C], options.map(&:first)
    assert_equal %w[A B D], options.map(&:second).sort
  end
end
