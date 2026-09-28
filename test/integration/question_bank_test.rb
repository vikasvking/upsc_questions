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
end
