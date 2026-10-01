require "test_helper"

# Going over answers before submitting (mark for review), one ranked attempt per student,
# strict tests' shuffled options, and the teacher's question-wise analysis and downloads
class ReviewAndReportsTest < ActionDispatch::IntegrationTest
  setup do
    @test = test_sessions(:one) # open test, no time window: questions one (answer A) and two (answer B)
  end

  def start_as(user, test = @test)
    sign_in_as user
    post start_test_dashboard_path, params: { test_session_id: test.id }
    user.test_attempts.order(:id).last
  end

  test "mark for review: the test stays open, marked questions come back, and Submit finishes it" do
    attempt = start_as(users(:one))
    first, second = attempt.questions.to_a

    # mark the first one without answering
    post submit_answer_dashboard_path, params: { token: attempt.token, n: 1, question_id: first.id, mark: "1" }
    assert_redirected_to arena_dashboard_path(attempt.token, n: 2)
    assert attempt.reload.marked?(first)
    assert_equal 0, attempt.user_responses.count

    post submit_answer_dashboard_path, params: { token: attempt.token, n: 2, question_id: second.id, answer_choice: second.correct_answer }
    assert_redirected_to arena_dashboard_path(attempt.token, n: 1), "back to the unanswered, marked question"

    get arena_dashboard_path(attempt.token, n: 1)
    assert_match "Marked for review", response.body
    assert_select "button[name=mark]"

    # answer it and keep the mark: everything answered, the next marked question is this one again
    post submit_answer_dashboard_path, params: { token: attempt.token, n: 1, question_id: first.id, answer_choice: first.correct_answer, mark: "1" }
    assert_redirected_to arena_dashboard_path(attempt.token, n: 1)
    assert_not attempt.reload.finished?
    follow_redirect!
    assert_match "1 still marked for review", response.body

    # Save & Next clears the mark
    post submit_answer_dashboard_path, params: { token: attempt.token, n: 1, question_id: first.id, answer_choice: first.correct_answer }
    assert_not attempt.reload.marked?(first)
    assert_not attempt.finished?

    post finish_test_dashboard_path, params: { token: attempt.token }
    assert attempt.reload.finished?
    assert_equal 2, attempt.score_summary[:correct]
  end

  test "Save & Next without an option is refused; topic practice still finishes after the last question" do
    attempt = start_as(users(:one))
    post submit_answer_dashboard_path, params: { token: attempt.token, n: 1, question_id: attempt.questions.first.id }
    assert_redirected_to arena_dashboard_path(attempt.token, n: 1)
    assert_equal "Please select an option before submitting.", flash[:alert]

    post start_test_dashboard_path, params: { topic: "Physics" }
    practice = users(:one).test_attempts.order(:id).last
    assert_nil practice.test_session
    practice.questions.to_a.each_with_index do |q, i|
      post submit_answer_dashboard_path, params: { token: practice.token, n: i + 1, question_id: q.id, answer_choice: "A" }
    end
    assert practice.reload.finished?
  end

  test "a second Start never makes a second ranked attempt" do
    attempt = start_as(users(:one))
    assert_equal attempt, TestAttempt.start_first_try!(users(:one), @test) # the database refuses a duplicate
    assert_equal 1, users(:one).test_attempts.where(test_session: @test).count
  end

  test "strict tests: the student answers with the letters they see and is marked on the right option" do
    strict = test_sessions(:two) # PIN test with question one (answer A)
    strict.update!(strict_mode: true, ends_at: 2.hours.from_now)
    sign_in_as users(:one)
    post verify_pin_test_sessions_path, params: { pin_code: strict.pin_code }
    post start_test_dashboard_path, params: { test_session_id: strict.id }
    attempt = users(:one).test_attempts.order(:id).last
    question = questions(:one)

    shown_correct = attempt.shown_letter(question, "A")
    get arena_dashboard_path(attempt.token, n: 1)
    assert_select "input[type=radio][name=answer_choice][value=?]", shown_correct
    # the option text next to that letter is the right answer
    assert_select "label", text: /#{shown_correct}\.\s+Newton/

    post submit_answer_dashboard_path, params: { token: attempt.token, n: 1, question_id: question.id, answer_choice: shown_correct }
    saved = attempt.user_responses.last
    assert_equal "A", saved.chosen_option # saved under the question's own letter
    assert saved.is_correct
  end

  test "teacher sees the question-wise analysis and downloads the results" do
    [[users(:one), "A", "B"], [users(:two), "C", "SKIPPED"]].each do |user, one, two|
      attempt = user.test_attempts.create!(test_session: @test, started_at: 1.hour.ago)
      { questions(:one) => one, questions(:two) => two }.each do |q, choice|
        user.user_responses.create!(question: q, chosen_option: choice, is_correct: choice == q.correct_answer, test_session_token: attempt.token)
      end
      attempt.update!(finished_at: 30.minutes.ago)
    end

    stats = @test.question_analysis
    one = stats.find { |s| s.question == questions(:one) }
    assert_equal [2, 1, 1, 50.0], [one.students, one.correct, one.wrong, one.correct_pct]
    assert_equal ["C", 1], one.common_wrong
    two = stats.find { |s| s.question == questions(:two) }
    assert_equal [1, 0, 1], [two.correct, two.wrong, two.skipped]
    assert_nil two.common_wrong
    assert_equal [["Physics", 2, 50.0]], @test.topic_analysis(stats).map { |t| [t.topic, t.questions, t.correct_pct] }

    sign_in_as users(:teacher)
    get test_session_path(@test)
    assert_response :success
    assert_match "Question-wise analysis", response.body
    assert_select "a[href=?]", export_test_session_path(@test)

    get export_test_session_path(@test)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
    lines = response.body.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF").lines
    assert_match(/\ARank,Student,Email/, lines.first)
    assert_equal 3, lines.size # header + two students
    assert_match "Student One", response.body

    get report_test_session_path(@test)
    assert_response :success
    assert_match "Print / Save as PDF", response.body
    assert_match "Question-wise analysis", response.body
  end

  test "students cannot download a test's results" do
    sign_in_as users(:one)
    get export_test_session_path(@test)
    assert_redirected_to dashboard_path
    get report_test_session_path(@test)
    assert_redirected_to dashboard_path
  end
end
