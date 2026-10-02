require "test_helper"

class AllTestsPageTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "dashboard shows at most 3 latest live or upcoming tests" do
    test_sessions(:two).update!(starts_at: 2.days.ago, ends_at: 1.day.ago) # closed
    4.times do |i|
      TestSession.create!(user: users(:teacher), title: "New Test #{i}", exam_type: "UPSC", # the student prepares for UPSC
                          duration_minutes: 10, pass_mark_percentage: 40, access_type: "open")
    end

    get dashboard_path
    assert_response :success
    assert_select "h3", text: /New Test/, count: 3
    assert_select "h3", text: "PIN Physics Test", count: 0 # closed tests stay off the dashboard
    assert_select "a[href=?]", all_tests_dashboard_path
  end

  test "all tests page lists every test" do
    get all_tests_dashboard_path
    assert_response :success
    assert_select "h3", text: "Open Physics Test"
    assert_select "h3", text: "PIN Physics Test"
  end

  test "filter by exam" do
    test_sessions(:two).update!(exam_type: "SSC")
    get all_tests_dashboard_path, params: { exam: "SSC" }
    assert_select "h3", text: "PIN Physics Test"
    assert_select "h3", text: "Open Physics Test", count: 0
  end

  test "filter by subject uses the topics of each test's questions" do
    questions(:two).update!(topic: "Chemistry") # only test one contains question two
    get all_tests_dashboard_path, params: { subject: "Chemistry" }
    assert_select "h3", text: "Open Physics Test"
    assert_select "h3", text: "PIN Physics Test", count: 0
  end

  test "compact cards: grouped by status, with the question count; a submitted test opens its result" do
    test_sessions(:two).update!(starts_at: 2.days.ago, ends_at: 1.day.ago) # closed
    attempt = users(:one).test_attempts.create!(test_session: test_sessions(:one), started_at: 1.hour.ago)
    attempt.update!(finished_at: 30.minutes.ago)

    get all_tests_dashboard_path
    assert_select "h2", text: "Open now"
    assert_select "h2", text: "Closed"
    assert_select "a[href=?]", test_results_dashboard_path(token: attempt.token), text: /2 questions.*Rank 1 of 1/m
    assert_select "a[href=?]", test_intro_dashboard_path(test_sessions(:two)), text: /1 question\b.*Closed/m
  end

  test "the test page shows who made it and its subjects" do
    get test_intro_dashboard_path(test_sessions(:one))
    assert_response :success
    assert_match "by", response.body
    assert_match users(:teacher).display_name, response.body
    assert_match "Physics", response.body
  end

  test "teachers are sent to their own test manager" do
    sign_in_as users(:teacher)
    get all_tests_dashboard_path
    assert_redirected_to test_sessions_path
  end
end
