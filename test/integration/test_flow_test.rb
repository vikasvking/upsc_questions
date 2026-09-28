require "test_helper"

class TestFlowTest < ActionDispatch::IntegrationTest
  test "teacher can save an edited test" do
    sign_in_as users(:teacher)
    t = test_sessions(:one)

    patch test_session_path(t), params: { test_session: {
      title: "Renamed", exam_type: "UPSC", duration_minutes: 20, pass_mark_percentage: 40,
      access_type: "pin", question_ids: [questions(:two).id]
    } }

    assert_redirected_to test_sessions_path
    t.reload
    assert_equal "Renamed", t.title
    assert t.pin_required?
    assert_equal [questions(:two).id], t.question_ids
  end

  test "student takes an open test to the end without errors" do
    sign_in_as users(:one)
    t = test_sessions(:one)

    post start_test_dashboard_path, params: { test_session_id: t.id }
    attempt = users(:one).test_attempts.last
    assert_redirected_to arena_dashboard_path(attempt.token, n: 1)

    first_q, second_q = attempt.questions.to_a # the order the test paper uses

    post submit_answer_dashboard_path, params: { token: attempt.token, n: 1, question_id: first_q.id, answer_choice: first_q.correct_answer }
    assert_redirected_to arena_dashboard_path(attempt.token, n: 2)

    wrong = (%w[A B C D] - [second_q.correct_answer]).first
    post submit_answer_dashboard_path, params: { token: attempt.token, n: 2, question_id: second_q.id, answer_choice: wrong }
    assert_redirected_to test_results_dashboard_path(token: attempt.token)

    follow_redirect!
    assert_response :success
    assert attempt.reload.finished?
    assert_equal 1, attempt.score_summary[:correct]
  end

  test "PIN test cannot be started without the PIN" do
    sign_in_as users(:one)
    post start_test_dashboard_path, params: { test_session_id: test_sessions(:two).id }
    assert_redirected_to join_test_sessions_path

    post verify_pin_test_sessions_path, params: { pin_code: "pint02" }
    assert_redirected_to test_intro_dashboard_path(test_sessions(:two))

    post start_test_dashboard_path, params: { test_session_id: test_sessions(:two).id }
    assert_redirected_to arena_dashboard_path(users(:one).test_attempts.last.token, n: 1)
  end

  test "test that has not opened yet cannot be started" do
    sign_in_as users(:one)
    t = test_sessions(:one)
    t.update!(starts_at: 1.day.from_now)

    post start_test_dashboard_path, params: { test_session_id: t.id }
    assert_redirected_to test_intro_dashboard_path(t)
  end
end
