require "test_helper"

class VisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @school = Institution.create!(name: "Sunrise Academy", kind: "coaching", city: "Sambalpur")
    Membership.create!(user: users(:teacher), institution: @school, status: "approved")
    Membership.create!(user: users(:one), institution: @school, status: "approved")
    @test = test_sessions(:one) # open test by users(:teacher)
  end

  test "an institution-only test is shown to its students and hidden from others" do
    @test.update!(visibility: "institution", institution: @school)

    sign_in_as users(:one)
    get all_tests_dashboard_path
    assert_select "h3", text: @test.title

    sign_in_as users(:two)
    get all_tests_dashboard_path
    assert_select "h3", text: @test.title, count: 0
    get test_intro_dashboard_path(@test)
    assert_redirected_to all_tests_dashboard_path
    post start_test_dashboard_path, params: { test_session_id: @test.id }
    assert_redirected_to all_tests_dashboard_path
  end

  test "a selected test is shown to picked students and batch members only" do
    batch = users(:teacher).batches.create!(name: "Batch A")
    batch.replace_students!([users(:two).id])
    @test.update!(visibility: "selected")
    @test.replace_audience!(batch_ids: [batch.id])

    assert @test.visible_to?(users(:two))
    assert_not @test.visible_to?(users(:one))
    assert @test.visible_to?(users(:teacher)) # the owner
    assert @test.visible_to?(users(:admin))
  end

  test "a PIN does not open a test the student is not allowed to see" do
    test = test_sessions(:two)
    test.update!(visibility: "institution", institution: @school)
    sign_in_as users(:two)
    post verify_pin_test_sessions_path, params: { pin_code: test.pin_code }
    assert_redirected_to join_test_sessions_path
  end

  test "students who already started a test keep seeing it" do
    users(:two).test_attempts.create!(test_session: @test)
    @test.update_columns(visibility: "institution", institution_id: @school.id)
    assert @test.visible_to?(users(:two))
  end

  test "private questions stay out of other students' question bank and practice" do
    q = Question.create!(topic: "Secret Topic", content: "Private question", exam_type: "UPSC_PRELIMS",
                         correct_answer: "A", option_a: "x", user: users(:teacher), visibility: "institution", institution: @school)

    sign_in_as users(:two)
    get question_bank_path
    assert_no_match "Secret Topic", response.body
    post start_test_dashboard_path, params: { topic: "Secret Topic" }
    assert_redirected_to dashboard_path
    post question_bank_answer_path, params: { question_id: q.id, answer_choice: "A" }
    assert_response :not_found

    sign_in_as users(:one)
    get question_bank_path
    assert_match "Secret Topic", response.body
  end

  test "teacher creates a test for selected students, picked or added by email" do
    sign_in_as users(:teacher)
    post test_sessions_path, params: {
      test_session: { title: "Batch quiz", exam_type: "UPSC_PRELIMS", duration_minutes: 20, pass_mark_percentage: 40,
                      access_type: "open", visibility: "selected", question_ids: [questions(:one).id] },
      audience: { user_ids: [users(:one).id], emails: "two@example.com, nobody@example.com" }
    }
    test = TestSession.find_by(title: "Batch quiz")
    assert test
    assert_equal [users(:one).id, users(:two).id].sort, test.granted_ids("User").sort
    assert_match "nobody@example.com", flash[:alert]
  end

  test "institution visibility needs one of the teacher's own institutions" do
    other = Institution.create!(name: "Other Coaching", kind: "coaching")
    sign_in_as users(:teacher)
    post test_sessions_path, params: {
      test_session: { title: "Wrong place", exam_type: "UPSC_PRELIMS", duration_minutes: 20, pass_mark_percentage: 40,
                      access_type: "open", visibility: "institution", institution_id: other.id, question_ids: [questions(:one).id] }
    }
    assert_response :unprocessable_entity
    assert_nil TestSession.find_by(title: "Wrong place")
  end

  test "all tests defaults to the student's exams" do
    TestSession.create!(user: users(:teacher), title: "NEET mock", exam_type: "NEET", duration_minutes: 10,
                        pass_mark_percentage: 40, access_type: "open", question_ids: [questions(:one).id])
    sign_in_as users(:one) # prepares for UPSC
    get all_tests_dashboard_path
    assert_select "h3", text: "NEET mock", count: 0
    get all_tests_dashboard_path, params: { exam: "all" }
    assert_select "h3", text: "NEET mock"
  end

  test "teacher manages a batch" do
    sign_in_as users(:teacher)
    post batches_path, params: { batch: { name: "Morning batch", institution_id: @school.id, student_ids: [users(:one).id], emails: "two@example.com" } }
    assert_redirected_to batches_path
    batch = users(:teacher).batches.find_by(name: "Morning batch")
    assert_equal [users(:one).id, users(:two).id].sort, batch.students.pluck(:id).sort
  end
end
