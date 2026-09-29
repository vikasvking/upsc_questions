require "test_helper"

class LiveViewAndLockTest < ActionDispatch::IntegrationTest
  setup do
    @test = test_sessions(:two) # PIN test
    @test.update!(strict_mode: true, starts_at: 5.minutes.ago, ends_at: 2.hours.from_now)
  end

  test "teacher sees who entered the PIN, who is writing and who submitted" do
    sign_in_as users(:two)
    post verify_pin_test_sessions_path, params: { pin_code: @test.pin_code } # enters PIN, never starts

    sign_in_as users(:one)
    post verify_pin_test_sessions_path, params: { pin_code: @test.pin_code }
    post start_test_dashboard_path, params: { test_session_id: @test.id }
    get arena_dashboard_path(users(:one).test_attempts.last.token, n: 1)

    sign_in_as users(:teacher)
    get test_session_path(@test)
    assert_select "turbo-frame#live_panel[src=?]", live_test_session_path(@test)

    get live_test_session_path(@test)
    assert_response :success
    assert_select "turbo-frame#live_panel"
    assert_match users(:one).email_address, response.body
    assert_match "Writing", response.body
    assert_match users(:two).email_address, response.body
    assert_match "Not started", response.body
  end

  test "students cannot open the live view" do
    sign_in_as users(:one)
    get live_test_session_path(@test)
    assert_redirected_to dashboard_path
  end

  test "a timed test locks 10 minutes before it opens" do
    sign_in_as users(:teacher)
    @test.update_columns(starts_at: 11.minutes.from_now, ends_at: 2.hours.from_now)
    get edit_test_session_path(@test)
    assert_response :success

    travel 2.minutes do # now 9 minutes before opening
      get edit_test_session_path(@test)
      assert_redirected_to test_sessions_path
      patch test_session_path(@test), params: { test_session: { title: "Changed", question_ids: [questions(:one).id] } }
      assert_redirected_to test_sessions_path
      assert_not_equal "Changed", @test.reload.title
    end
  end

  test "a test with no time window and no strict mode stays editable" do
    sign_in_as users(:teacher)
    get edit_test_session_path(test_sessions(:one))
    assert_response :success
  end

  test "student sets the exam they are preparing for" do
    sign_in_as users(:one)
    patch profile_exam_path, params: { target_exam: "NEET" }
    assert_redirected_to profile_path
    assert_equal "NEET", users(:one).reload.target_exam

    get dashboard_path
    assert_match "NEET", response.body
  end
end
