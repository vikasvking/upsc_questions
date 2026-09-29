require "test_helper"

class StrictModeFlowTest < ActionDispatch::IntegrationTest
  setup do
    @test = test_sessions(:two) # PIN test with one question
    @test.update!(strict_mode: true, ends_at: 2.hours.from_now)
    sign_in_as users(:one)
    post verify_pin_test_sessions_path, params: { pin_code: @test.pin_code }
    post start_test_dashboard_path, params: { test_session_id: @test.id }
    @attempt = users(:one).test_attempts.last
  end

  test "test page carries the strict-mode controller and no exit link" do
    get arena_dashboard_path(@attempt.token, n: 1)
    assert_response :success
    assert_select "[data-controller='strict-mode']"
    assert_select "a", text: /Exit \(progress is saved\)/, count: 0
    assert @attempt.reload.last_seen_at.present?
  end

  test "heartbeat keeps the student present" do
    post heartbeat_dashboard_path, params: { token: @attempt.token }, as: :json
    assert_response :success
    assert_equal "ok", response.parsed_body["status"]
  end

  test "leaving twice blocks the student, who then cannot answer or restart" do
    post report_leave_dashboard_path, params: { token: @attempt.token, kind: "hidden", seconds: 12 }, as: :json
    assert_equal "ok", response.parsed_body["status"]
    assert_equal 1, response.parsed_body["leave_count"]

    post report_leave_dashboard_path, params: { token: @attempt.token, kind: "hidden", seconds: 20 }, as: :json
    assert_equal "blocked", response.parsed_body["status"]

    get arena_dashboard_path(@attempt.token, n: 1)
    assert_redirected_to test_intro_dashboard_path(@test)

    question = @attempt.questions.first
    post submit_answer_dashboard_path, params: { token: @attempt.token, n: 1, question_id: question.id, answer_choice: "A" }
    assert_redirected_to test_intro_dashboard_path(@test)
    assert_equal 0, @attempt.user_responses.count

    post start_test_dashboard_path, params: { test_session_id: @test.id }
    assert_redirected_to test_intro_dashboard_path(@test)
  end

  test "a quick refresh is not counted as leaving" do
    post report_leave_dashboard_path, params: { token: @attempt.token, kind: "reloaded", seconds: 2 }, as: :json
    assert_equal 0, @attempt.reload.leave_count
  end

  test "teacher reinstates a blocked student who can then continue" do
    @attempt.block!("left")

    sign_in_as users(:teacher)
    get test_session_path(@test)
    assert_select "td", text: users(:one).email_address

    post reinstate_test_session_path(@test, attempt_id: @attempt.id)
    assert_redirected_to test_session_path(@test)
    assert_not @attempt.reload.blocked?

    sign_in_as users(:one)
    get arena_dashboard_path(@attempt.token, n: 1)
    assert_response :success
  end

  test "another teacher cannot reinstate" do
    @attempt.block!("left")
    sign_in_as users(:teacher_two)
    post reinstate_test_session_path(@test, attempt_id: @attempt.id)
    assert @attempt.reload.blocked?
  end

  test "results stay hidden until the test closes" do
    post finish_test_dashboard_path, params: { token: @attempt.token }
    follow_redirect!
    assert_response :success
    assert_match "Results will be available", response.body
    assert_no_match "Answer Review", response.body

    travel 3.hours do
      get test_results_dashboard_path(token: @attempt.token)
      assert_match "Answer Review", response.body
    end
  end
end
