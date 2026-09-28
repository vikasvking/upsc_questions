require "test_helper"

class AllTestsPageTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "dashboard shows at most 3 latest live or upcoming tests" do
    test_sessions(:two).update!(starts_at: 2.days.ago, ends_at: 1.day.ago) # closed
    4.times do |i|
      TestSession.create!(user: users(:teacher), title: "New Test #{i}", exam_type: "SSC",
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

  test "teachers are sent to their own test manager" do
    sign_in_as users(:teacher)
    get all_tests_dashboard_path
    assert_redirected_to test_sessions_path
  end
end
