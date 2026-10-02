require "test_helper"

# Strict mode on an open test (no PIN): leaving the test page ends the test at once
class StrictOpenTest < ActionDispatch::IntegrationTest
  setup do
    @test = test_sessions(:one) # open test, no closing time: questions one (A) and two (B)
    @test.update!(strict_mode: true)
    sign_in_as users(:one)
    post start_test_dashboard_path, params: { test_session_id: @test.id }
    @attempt = users(:one).test_attempts.last
  end

  test "the rules and the test page say that leaving ends the test" do
    get test_intro_dashboard_path(@test)
    assert_match "ends your test", response.body
    get arena_dashboard_path(@attempt.token, n: 1)
    assert_select "[data-controller='strict-mode']"
    assert_match "ends your test straight away", response.body
  end

  test "leaving ends the test at once, and the result says why" do
    q = @attempt.questions.first
    post submit_answer_dashboard_path, params: { token: @attempt.token, n: 1, question_id: q.id, answer_choice: @attempt.shown_letter(q, q.correct_answer) }

    post report_leave_dashboard_path, params: { token: @attempt.token, kind: "hidden", seconds: 12 }, as: :json
    body = response.parsed_body
    assert_equal "finished", body["status"]
    assert_match "because you switched to another tab or app for 12s", body["message"]
    assert_equal test_results_dashboard_path(token: @attempt.token), body["redirect_to"]
    assert @attempt.reload.finished?
    assert_not @attempt.blocked?

    get arena_dashboard_path(@attempt.token, n: 1)
    assert_redirected_to test_results_dashboard_path(token: @attempt.token)
    follow_redirect!
    assert_match "This strict test ended early", response.body
    assert_match "Your 1 answered question was submitted and marked.", response.body
    assert_equal 1, @attempt.score_summary[:correct]
  end

  test "a quick refresh does not end the test" do
    post report_leave_dashboard_path, params: { token: @attempt.token, kind: "reloaded", seconds: 2 }, as: :json
    assert_equal "ok", response.parsed_body["status"]
    assert_not @attempt.reload.finished?
  end

  test "the teacher sees why the test ended" do
    @attempt.record_violation!("switched to another tab or app for 12s")
    sign_in_as users(:teacher)
    get test_session_path(@test)
    assert_match "Ended early: switched to another tab or app for 12s", response.body
  end
end
