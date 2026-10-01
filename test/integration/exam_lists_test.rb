require "test_helper"

# Long lists of tests and questions: exam tabs, page limits, and the test form's question library
class ExamListsTest < ActionDispatch::IntegrationTest
  def add_questions(count, exam:, user: users(:teacher))
    count.times.map do |i|
      Question.create!(user: user, exam_type: exam, year: 2026, topic: "Matrices", content: "#{exam} question #{i + 1}",
                       option_a: "1", option_b: "2", option_c: "3", option_d: "4", correct_answer: "A")
    end
  end

  test "admin question list shows one exam at a time and remembers the exam" do
    sign_in_as users(:admin)
    add_questions(3, exam: "CBSE_XII")

    get admin_questions_path(exam: "CBSE_XII")
    assert_response :success
    assert_select "nav[aria-label=Exams] a[aria-current=page]", text: /CBSE XII\s*3/
    assert_select "tbody tr", 3
    assert_no_match questions(:one).content, response.body

    get admin_questions_path # opens on the remembered exam
    assert_select "tbody tr", 3

    get admin_questions_path(exam: "all")
    assert_match questions(:one).content, response.body
  end

  test "long lists are split into pages and the page size is remembered" do
    sign_in_as users(:admin)
    add_questions(30, exam: "NEET")

    get admin_questions_path(exam: "NEET", per: 25)
    assert_select "tbody tr", 25
    assert_select "a", text: "Next →"
    assert_match "1–25 of 30 questions", response.body

    get admin_questions_path(page: 2)
    assert_select "tbody tr", 5
  end

  test "admin test list has exam tabs" do
    sign_in_as users(:admin)
    get admin_test_sessions_path(exam: "UPSC_PRELIMS")
    assert_select "nav[aria-label=Exams] a[aria-current=page]", text: /UPSC Prelims/
    assert_match test_sessions(:one).title, response.body

    get admin_test_sessions_path(exam: "NEET")
    assert_no_match test_sessions(:one).title, response.body
  end

  test "teacher lists are split by exam and paged too" do
    sign_in_as users(:teacher)
    get test_sessions_path(exam: "NEET")
    assert_select "nav[aria-label=Exams]"
    assert_no_match test_sessions(:one).title, response.body

    get test_sessions_path(exam: "all")
    assert_match test_sessions(:one).title, response.body

    add_questions(30, exam: "JEE_MAIN")
    get questions_path(exam: "JEE_MAIN", per: 25)
    assert_select "tbody tr", 25
  end

  test "the test form loads its library separately: one exam, 50 at a time, searched on the server" do
    sign_in_as users(:teacher)
    add_questions(60, exam: "JEE_ADVANCED")

    get new_test_session_path
    assert_response :success
    assert_select "turbo-frame#question_library[src]"
    assert_select ".library-row-item", 0 # nothing from the bank is rendered with the form

    get question_library_path(exam: "JEE_ADVANCED")
    assert_select "turbo-frame#question_library .library-row-item", 50
    assert_select "turbo-frame#question_library_page_2 a", text: "Load 50 more"
    assert_no_match questions(:one).content, response.body # other exams stay out

    get question_library_path(exam: "JEE_ADVANCED", page: 2)
    assert_select "turbo-frame#question_library_page_2 .library-row-item", 10
    assert_select "turbo-frame#question_library_page_3", 0

    get question_library_path(exam: "JEE_ADVANCED", q: "question 7")
    assert_select ".library-row-item", 1

    get edit_test_session_path(test_sessions(:one))
    assert_select "#active-questions-container .question-checkbox", test_sessions(:one).questions.count
  end

  test "the admin test form's library covers the whole bank" do
    sign_in_as users(:admin)
    get edit_admin_test_session_path(test_sessions(:one))
    assert_select "turbo-frame#question_library[src*='all=1']"

    get question_library_path(exam: "all", all: "1")
    assert_select ".library-row-item", Question.count
  end

  test "students cannot open the question library" do
    sign_in_as users(:one)
    get question_library_path
    assert_response :forbidden
  end

  test "a question ticked twice is added to the test once" do
    sign_in_as users(:teacher)
    q = questions(:one)
    post test_sessions_path, params: { test_session: { title: "Twice ticked", exam_type: "UPSC_PRELIMS", duration_minutes: 10,
                                                       pass_mark_percentage: 40, access_type: "open", visibility: "public",
                                                       question_ids: [q.id, q.id] } }
    assert_equal [q.id], TestSession.find_by!(title: "Twice ticked").question_ids
  end
end
