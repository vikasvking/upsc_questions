require "test_helper"

class TestRankingsTest < ActiveSupport::TestCase
  setup { @test = test_sessions(:one) } # questions one (answer A) and two (answer B)

  def submit(user, answers, seconds:)
    attempt = user.test_attempts.create!(test_session: @test, started_at: 1.hour.ago)
    answers.each do |question, choice|
      user.user_responses.create!(question: question, chosen_option: choice,
                                  is_correct: choice == question.correct_answer,
                                  test_session_token: attempt.token)
    end
    attempt.update!(finished_at: attempt.started_at + seconds)
    attempt
  end

  test "UPSC marking: a wrong answer costs a third, a skip costs nothing" do
    submit(users(:one), { questions(:one) => "A", questions(:two) => "C" }, seconds: 100)       # 2 - 0.67
    submit(users(:two), { questions(:one) => "A", questions(:two) => "SKIPPED" }, seconds: 300) # 2

    results = @test.rankings
    assert_equal [users(:two), users(:one)], results.map(&:user)
    assert_equal 2.0, results.first.marks
    assert_equal 1.33, results.last.marks
    assert_equal [1, 2], results.map(&:rank)
  end

  test "equal marks: less time taken ranks higher" do
    submit(users(:one), { questions(:one) => "A" }, seconds: 500)
    submit(users(:two), { questions(:one) => "A" }, seconds: 200)

    results = @test.rankings
    assert_equal users(:two), results.first.user
    assert_equal 200, results.first.time_taken
  end
end
