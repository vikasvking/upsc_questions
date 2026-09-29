require "test_helper"

class RatingsAndReportsTest < ActionDispatch::IntegrationTest
  setup do
    @test = test_sessions(:one) # by users(:teacher)
  end

  def submit_test(user)
    user.test_attempts.create!(test_session: @test, started_at: 1.hour.ago).update!(finished_at: 30.minutes.ago)
  end

  def rate(kind, id, stars, comment = nil)
    post ratings_path, params: { rateable: kind, rateable_id: id, rating: { stars: stars, comment: comment } }
  end

  test "only students who submitted a test can rate it; rating again replaces it" do
    sign_in_as users(:one)
    rate("test", @test.id, 5)
    assert_equal 0, @test.ratings.count

    submit_test(users(:one))
    rate("test", @test.id, 5, "Good paper")
    rate("test", @test.id, 3)
    assert_equal 1, @test.ratings.count
    assert_equal 3, @test.ratings.first.stars
  end

  test "a teacher can be rated by students who took their tests" do
    sign_in_as users(:two)
    rate("teacher", users(:teacher).id, 4)
    assert_equal 0, users(:teacher).received_ratings.count

    submit_test(users(:two))
    rate("teacher", users(:teacher).id, 4, "Clear explanations")
    assert_equal 4, users(:teacher).received_ratings.first.stars
  end

  test "averages show only from three ratings" do
    [users(:one), users(:two)].each { |u| Rating.create!(rateable: @test, user: u, stars: 5) }
    assert_not Rating.summary_for(@test).shown?

    third = User.create!(name: "Third", email_address: "third@example.com", password: "Maple2026river", date_of_birth: "2000-01-01")
    Rating.create!(rateable: @test, user: third, stars: 2)
    summary = Rating.summary_for(@test)
    assert summary.shown?
    assert_equal "4.0", summary.stars_text
  end

  test "teacher profile shows name, subjects and no email" do
    sign_in_as users(:one)
    get teacher_path(users(:teacher))
    assert_response :success
    assert_match "Asha Rao", response.body
    assert_match "Physics", response.body
    assert_no_match users(:teacher).email_address, response.body
  end

  test "student reports a problem; the teacher replies and the student sees it" do
    q = questions(:one)
    sign_in_as users(:one)
    post question_reports_path(question_id: q.id), params: { question_report: { kind: "wrong_answer", message: "Should be B" } }
    report = QuestionReport.last
    assert_equal users(:one), report.user

    sign_in_as users(:teacher)
    get question_reports_path
    assert_match "Should be B", response.body
    patch question_report_path(report), params: { status: "dismissed", response: "A is correct: force is in newtons" }
    assert_equal "dismissed", report.reload.status

    sign_in_as users(:one)
    get profile_path
    assert_match "force is in newtons", response.body
  end

  test "other teachers cannot answer a report on someone else's question" do
    report = QuestionReport.create!(question: questions(:one), user: users(:one), kind: "typo")
    sign_in_as users(:teacher_two)
    patch question_report_path(report), params: { status: "fixed" }
    assert report.reload.open?
  end

  test "admins hide an abusive comment; the stars still count" do
    rating = Rating.create!(rateable: users(:teacher), user: users(:one), stars: 1, comment: "rude words")
    sign_in_as users(:admin)
    get admin_moderation_index_path(tab: "ratings")
    assert_response :success
    patch hide_comment_admin_moderation_path(rating)
    assert rating.reload.comment_hidden_at
    assert_equal 1, Rating.summary_for(users(:teacher)).count

    sign_in_as users(:two)
    get teacher_path(users(:teacher))
    assert_no_match "rude words", response.body
  end

  test "teacher results and live pages show names instead of emails" do
    submit_test(users(:one))
    sign_in_as users(:teacher)
    get test_session_path(@test)
    assert_select "td", text: "Student One"
  end
end
