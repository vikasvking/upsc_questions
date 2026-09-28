require "test_helper"

class AddQuestionTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:teacher) }

  def params(extra = {})
    { question: { exam_type: "UPSC", year: 2024, q_no: "3", topic: "Physics",
                  content: "What is the SI unit of power?", option_a: "Joule", option_b: "Watt",
                  option_c: "Newton", option_d: "Volt", correct_answer: "B",
                  explanation: "Power is measured in watts." } }.merge(extra)
  end

  test "teacher adds one question and it lands in the question bank" do
    get new_question_path(exam_type: "UPSC", year: 2024)
    assert_response :success
    assert_select "input[name='question[q_no]'][value='3']" # next number after the fixtures' Q1 and Q2 (UPSC 2024)

    assert_difference -> { Question.where(topic: "Physics").count }, 1 do
      post questions_path, params: params
    end
    assert_redirected_to questions_path
    assert_equal users(:teacher), Question.find_by(content: "What is the SI unit of power?").user
  end

  test "save and add another keeps exam, year and topic" do
    post questions_path, params: params(add_another: "1")
    assert_redirected_to new_question_path(exam_type: "UPSC", year: 2024, topic: "Physics")
  end

  test "invalid answer key shows errors" do
    post questions_path, params: { question: params[:question].merge(correct_answer: "E") }
    assert_response :unprocessable_entity
    assert_match "must be A, B, C or D", response.body
  end

  test "students cannot add questions" do
    sign_in_as users(:one)
    get new_question_path
    assert_redirected_to dashboard_path
  end

  test "signed-in pages have the small-screen menu button" do
    get questions_path
    assert_select "#sidebar-open"
    assert_select "#app-sidebar"
  end
end
