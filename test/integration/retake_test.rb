require "test_helper"

# Students can retake a teacher test as often as they like. Retakes are practice:
# only the first attempt is ranked, and tests with a closing time allow retakes only after they close.
class RetakeTest < ActionDispatch::IntegrationTest
  setup do
    @test = test_sessions(:one) # open test, no time window: questions one (answer A) and two (answer B)
    sign_in_as users(:one)
  end

  def start(test, retake: false)
    post start_test_dashboard_path, params: { test_session_id: test.id, retake: (1 if retake) }.compact
    users(:one).test_attempts.order(:id).last
  end

  # Answers every question in the test paper's order; the last answer submits the test
  def answer_all(attempt, choices)
    attempt.questions.to_a.each_with_index do |q, i|
      post submit_answer_dashboard_path, params: { token: attempt.token, n: i + 1, question_id: q.id, answer_choice: choices.fetch(q) }
    end
    assert attempt.reload.finished?
  end

  test "a student retakes a submitted test as many times as they like; the first attempt keeps the rank" do
    first = start(@test)
    answer_all(first, questions(:one) => "C", questions(:two) => "B") # 1 correct

    # starting again without asking for a retake still shows the old result
    post start_test_dashboard_path, params: { test_session_id: @test.id }
    assert_redirected_to test_results_dashboard_path(token: first.token)

    get test_intro_dashboard_path(@test)
    assert_select "button", text: "↻ Retake Test"

    second = start(@test, retake: true)
    assert_not_equal first, second
    assert second.retake?
    assert_redirected_to arena_dashboard_path(second.token, n: 1)
    answer_all(second, questions(:one) => "A", questions(:two) => "B") # 2 correct

    get test_results_dashboard_path(token: second.token)
    assert_response :success
    assert_match "Practice retake", response.body
    assert_match "Your rank (first attempt)", response.body
    assert_select "button", text: "↻ Retake Test"

    third = start(@test, retake: true)
    assert third.retake?
    assert_equal 3, users(:one).test_attempts.where(test_session: @test).count

    ranking = @test.rankings
    assert_equal 1, ranking.size, "retakes never add a second row for the same student"
    assert_equal first, ranking.first.attempt
  end

  test "a test with a closing time can be retaken only after it closes, with the full duration" do
    @test.update!(ends_at: 2.hours.from_now)
    first = start(@test)
    answer_all(first, questions(:one) => "A", questions(:two) => "B")

    get test_intro_dashboard_path(@test)
    assert_select "button", text: "↻ Retake Test", count: 0
    assert_match "after it closes", response.body

    post start_test_dashboard_path, params: { test_session_id: @test.id, retake: 1 }
    assert_redirected_to test_results_dashboard_path(token: first.token)
    assert_equal 1, users(:one).test_attempts.where(test_session: @test).count

    travel 3.hours do
      retake = start(@test, retake: true)
      assert retake.retake?
      assert_in_delta 30.minutes.from_now, retake.deadline_at, 5.seconds # not cut short by the (past) closing time
      get arena_dashboard_path(retake.token, n: 1)
      assert_response :success
    end
  end

  test "a strict test's retake after it closes is not watched and shows its result at once" do
    strict = test_sessions(:two) # PIN test with one question
    strict.update!(strict_mode: true, ends_at: 2.hours.from_now)
    post verify_pin_test_sessions_path, params: { pin_code: strict.pin_code }
    first = start(strict)
    answer_all(first, questions(:one) => "A")

    travel 3.hours do
      retake = start(strict, retake: true)
      assert retake.retake?
      assert_not retake.strict?
      get arena_dashboard_path(retake.token, n: 1)
      assert_select "[data-controller='strict-mode']", count: 0

      answer_all(retake, questions(:one) => "B")
      assert retake.results_released?
      assert_equal [first], strict.rankings.map(&:attempt)
    end
  end
end
