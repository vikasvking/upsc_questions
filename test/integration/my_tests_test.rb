require "test_helper"

# A student's list of everything they have attempted (DashboardsController#my_tests)
class MyTestsTest < ActionDispatch::IntegrationTest
  def attempt(user, test: nil, topic: nil, answers: {}, finished: true, retake: false)
    # an unfinished attempt starts now: one started an hour ago on a 30-minute test has run out and counts as submitted
    a = user.test_attempts.create!(test_session: test, topic: topic, started_at: finished ? 1.hour.ago : Time.current, retake: retake)
    answers.each do |q, choice|
      user.user_responses.create!(question: q, chosen_option: choice, is_correct: choice == q.correct_answer, test_session_token: a.token)
    end
    a.update!(finished_at: 30.minutes.ago) if finished
    a
  end

  test "lists tests, retakes and practice with marks, rank and what to do next" do
    test = test_sessions(:one) # UPSC marking, questions one (A) and two (B)
    first = attempt(users(:one), test: test, answers: { questions(:one) => "A", questions(:two) => "SKIPPED" })
    retake = attempt(users(:one), test: test, answers: { questions(:one) => "A", questions(:two) => "B" }, retake: true)
    running = attempt(users(:one), test: test_sessions(:two), answers: {}, finished: false)
    practice = attempt(users(:one), topic: "Physics", answers: { questions(:one) => "A", questions(:two) => "C" })

    sign_in_as users(:one)
    get my_tests_dashboard_path
    assert_response :success

    assert_match "2 / 4", response.body     # first attempt: one right, one skipped
    assert_match "Rank 1 of 1", response.body
    assert_match "4 / 4", response.body     # the retake
    assert_match "Retake 1, practice", response.body
    assert_match "Physics (topic practice)", response.body
    assert_match "1 of 2 correct", response.body
    assert_match "In progress", response.body
    assert_select "a[href=?]", arena_dashboard_path(running.token), text: "Resume"
    [first, retake, practice].each do |a|
      assert_select "a[href=?]", test_results_dashboard_path(token: a.token), text: "View answers"
    end
    assert_select "a[href=?]", my_tests_dashboard_path, minimum: 1 # sidebar link

    get my_tests_dashboard_path(kind: "practice")
    assert_match "Physics (topic practice)", response.body
    assert_no_match "Open Physics Test", response.body
  end

  test "strict tests wait for their closing time; blocked students are told to ask their teacher" do
    strict = test_sessions(:two)
    strict.update!(strict_mode: true, ends_at: 2.hours.from_now)
    attempt(users(:one), test: strict, answers: { questions(:one) => "A" })
    blocked = attempt(users(:two), test: strict, finished: false)
    blocked.block!("left")

    sign_in_as users(:one)
    get my_tests_dashboard_path
    assert_match "results at", response.body
    assert_no_match "Rank 1 of", response.body

    sign_in_as users(:two)
    get my_tests_dashboard_path
    assert_match "Blocked", response.body
    assert_select "a[href=?]", test_intro_dashboard_path(strict), text: "Test page"
  end

  test "nothing attempted yet" do
    sign_in_as users(:one)
    get my_tests_dashboard_path
    assert_select "p", text: "You haven't started a test or a practice yet." # compares the text, not the escaped HTML
  end
end
