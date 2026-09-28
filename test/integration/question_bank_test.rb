require "test_helper"

class QuestionBankTest < ActionDispatch::IntegrationTest
  test "question bank lists topics with progress" do
    sign_in_as users(:one)
    get question_bank_path
    assert_response :success
    assert_select "h3", text: "Physics"
    assert_match "0 / 2", response.body
  end

  test "topic page hides the answer until the question is attempted" do
    sign_in_as users(:one)
    get question_bank_topic_path(name: "Physics")
    assert_response :success
    assert_match "Answer and explanation appear after you attempt", response.body
    assert_no_match questions(:one).explanation, response.body

    users(:one).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, test_session_token: "t1")
    get question_bank_topic_path(name: "Physics", filter: "solved")
    assert_match questions(:one).explanation, response.body
    assert_match "Attempted 1 time", response.body
  end

  test "dashboard shows real topper comparison" do
    sign_in_as users(:one)
    get dashboard_path
    assert_response :success
    assert_match "Topper Comparison", response.body
    assert_no_match "AIR-10", response.body
  end

  test "teacher who is not the creator sees an error instead of the edit page" do
    sign_in_as users(:teacher_two)
    get edit_question_path(questions(:one))
    assert_redirected_to questions_path
    follow_redirect!
    assert_match "You are not the creator of this question", response.body
    assert_select "button", text: /🔒 Edit/
  end

  test "creator can still edit" do
    sign_in_as users(:teacher)
    get edit_question_path(questions(:one))
    assert_response :success
  end

  test "a single question can be practised from the question bank" do
    sign_in_as users(:one)
    assert_difference -> { users(:one).user_responses.count }, 1 do
      post question_bank_answer_path, params: { question_id: questions(:one).id, answer_choice: "a", duration_seconds: 12 }
    end
    assert_redirected_to question_bank_topic_path(name: "Physics", anchor: "q-#{questions(:one).id}")
    follow_redirect!
    assert_match "✓ Correct!", response.body
    assert_match "Attempted 1 time", response.body
    assert_nil users(:one).user_responses.last.test_session_token
  end

  test "student sees their rank on a submitted test" do
    sign_in_as users(:one)
    post start_test_dashboard_path, params: { test_session_id: test_sessions(:one).id }
    attempt = users(:one).test_attempts.last
    post finish_test_dashboard_path, params: { token: attempt.token }
    follow_redirect!
    assert_match "Your rank", response.body
    assert_match "#1", response.body
  end
end
