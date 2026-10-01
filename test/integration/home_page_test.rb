require "test_helper"

# The public home page: the answer sheet with the newest free sample, the newest questions, and the exam list
class HomePageTest < ActionDispatch::IntegrationTest
  test "without free samples the answer sheet shows the example question" do
    get root_path
    assert_response :success
    assert_match "Fill the bubble.", response.body
    assert_match "Example question", response.body
    assert_select "[data-controller=answer-sheet][data-answer-sheet-correct-value=D]"
    assert_select "button[data-letter]", minimum: 4
  end

  test "the newest free sample goes on the answer sheet; its share of right answers shows from 20 answers" do
    q = questions(:one)
    q.update!(free_sample: true)

    get root_path
    assert_match "Newest sample question", response.body
    assert_select "[data-answer-sheet-correct-value=?]", q.correct_answer
    assert_no_match "of the time", response.body

    20.times { |i| UserResponse.create!(user: users(i.even? ? :one : :two), question: q, chosen_option: i < 15 ? "A" : "B", is_correct: i < 15) }
    get root_path
    assert_match "get this right 75% of the time", response.body
  end

  test "fresh questions: newest public first, locked unless a free sample, private ones left out" do
    newest = Question.create!(user: users(:teacher), exam_type: "NEET", topic: "Biology", content: "Where do the light reactions take place?",
                              option_a: "Stroma", option_b: "Thylakoid membrane", option_c: "Cytoplasm", option_d: "Nucleus", correct_answer: "B")
    hidden = Question.create!(user: users(:teacher), exam_type: "NEET", topic: "Biology", content: "A question only one class can see",
                              option_a: "1", option_b: "2", option_c: "3", option_d: "4", correct_answer: "A", visibility: "selected")

    get root_path
    assert_select "#fresh article", count: 3 # the two public fixtures and the new one
    assert_select "#fresh article:first-child", text: /#{Regexp.escape(newest.content)}/
    assert_select "#fresh article:first-child", text: /Sign up free to answer/
    assert_no_match hidden.content, response.body
    assert_select "#fresh a[href=?]", question_bank_path
  end

  test "the exam row lists exams that have questions, with their counts" do
    get root_path
    assert_select "a[href=?]", new_registration_path, text: /UPSC Prelims\s+2 questions/
  end

  test "signed-in users go to their dashboard" do
    sign_in_as users(:one)
    get root_path
    assert_redirected_to dashboard_path
  end
end
