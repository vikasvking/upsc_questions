require "test_helper"

# JSON API used by the mobile app (see Api::V1::BaseController)
class ApiV1Test < ActionDispatch::IntegrationTest
  def api_sign_in(user, password: "password")
    post api_v1_session_path, params: { email_address: user.email_address, password: password }, as: :json
    assert_response :created
    { "Authorization" => "Bearer #{response.parsed_body["token"]}" }
  end

  def json = response.parsed_body

  test "sign in gives a token; a wrong password or a missing token is refused" do
    post api_v1_session_path, params: { email_address: users(:one).email_address, password: "wrong" }, as: :json
    assert_response :unauthorized
    assert_equal "invalid_login", json.dig("error", "code")

    get api_v1_me_path, as: :json
    assert_response :unauthorized

    headers = api_sign_in(users(:one))
    get api_v1_me_path, headers: headers, as: :json
    assert_response :success
    assert_equal "student", json.dig("user", "role")
    assert_nil json.dig("user", "account_issue")

    delete api_v1_session_path, headers: headers, as: :json
    assert_response :no_content
    get api_v1_me_path, headers: headers, as: :json
    assert_response :unauthorized
  end

  test "a student takes an open test and sees the result" do
    headers = api_sign_in(users(:one))
    test = test_sessions(:one)

    get api_v1_tests_path, params: { exam: "all" }, headers: headers
    assert_response :success
    card = json["tests"].find { |t| t["id"] == test.id }
    assert_equal false, card["locked"]

    post start_api_v1_test_path(test), headers: headers, as: :json
    assert_response :created
    token = json["attempt_token"]

    get api_v1_attempt_path(token), headers: headers
    assert_response :success
    assert_equal 2, json["questions"].size
    assert_nil json["questions"].first["correct_answer"] # never sent while the test is running

    post answer_api_v1_attempt_path(token), params: { question_id: questions(:one).id, choice: "A", duration_seconds: 12 }, headers: headers, as: :json
    assert_response :success
    assert_equal false, json["finished"]
    post answer_api_v1_attempt_path(token), params: { question_id: questions(:two).id, choice: "SKIPPED" }, headers: headers, as: :json
    assert_equal true, json["finished"] # every question answered or skipped -> submitted, as on the website

    get result_api_v1_attempt_path(token), headers: headers
    assert_response :success
    assert_equal true, json["released"]
    assert_equal 1, json.dig("summary", "correct")
    assert_equal 1, json.dig("rank", "rank")
    reviewed = json["review"].find { |r| r["id"] == questions(:one).id }
    assert_equal "A", reviewed["correct_answer"]
    assert_equal "A", reviewed["my_choice"]
    assert_equal true, reviewed["correct"]
  end

  def answer_both(token, headers, one:, two:)
    post answer_api_v1_attempt_path(token), params: { question_id: questions(:one).id, choice: one }, headers: headers, as: :json
    post answer_api_v1_attempt_path(token), params: { question_id: questions(:two).id, choice: two }, headers: headers, as: :json
    assert_equal true, json["finished"]
  end

  test "a student retakes a submitted test as often as they like; only the first attempt is ranked" do
    headers = api_sign_in(users(:one))
    test = test_sessions(:one) # no time window

    post start_api_v1_test_path(test), headers: headers, as: :json
    first = json["attempt_token"]
    answer_both(first, headers, one: "C", two: "B") # 1 correct

    post start_api_v1_test_path(test), headers: headers, as: :json
    assert_equal "finished", json["status"]
    assert_equal first, json["attempt_token"]
    assert_equal true, json["can_retake"]

    post start_api_v1_test_path(test), params: { retake: true }, headers: headers, as: :json
    assert_response :created
    assert_equal true, json["retake"]
    retake = json["attempt_token"]
    assert_not_equal first, retake
    answer_both(retake, headers, one: "A", two: "B") # 2 correct

    get result_api_v1_attempt_path(retake), headers: headers
    assert_response :success
    assert_equal true, json.dig("attempt", "retake")
    assert_equal 2, json.dig("summary", "correct")
    assert_equal 1, json.dig("rank", "rank")
    assert_equal true, json.dig("rank", "from_first_attempt")
    assert_equal true, json["can_retake"]

    get api_v1_test_path(test), headers: headers
    mine = json.dig("test", "my_attempt")
    assert_equal retake, mine["token"]
    assert_equal true, mine["retake"]
    assert_equal 2, mine["attempt_count"]
    assert_equal 1, test.rankings.size
  end

  test "a test with a closing time can be retaken only after it closes" do
    test = test_sessions(:one)
    test.update!(ends_at: 2.hours.from_now)
    headers = api_sign_in(users(:one))
    post start_api_v1_test_path(test), headers: headers, as: :json
    answer_both(json["attempt_token"], headers, one: "A", two: "B")

    post start_api_v1_test_path(test), params: { retake: true }, headers: headers, as: :json
    assert_response :conflict
    assert_equal "retake_not_open", json.dig("error", "code")

    travel 3.hours do
      headers = api_sign_in(users(:one))
      post start_api_v1_test_path(test), params: { retake: true }, headers: headers, as: :json
      assert_response :created
      get api_v1_attempt_path(json["attempt_token"]), headers: headers
      assert_response :success
      assert_equal false, json.dig("attempt", "strict")
    end
  end

  test "PIN tests need the PIN first" do
    headers = api_sign_in(users(:one))
    test = test_sessions(:two)

    post start_api_v1_test_path(test), headers: headers, as: :json
    assert_response :forbidden
    assert_equal "pin_required", json.dig("error", "code")

    post verify_pin_api_v1_tests_path, params: { pin_code: "nope00" }, headers: headers, as: :json
    assert_response :not_found

    post verify_pin_api_v1_tests_path, params: { pin_code: test.pin_code.downcase }, headers: headers, as: :json
    assert_response :success
    assert_equal test.id, json["test_id"]

    post start_api_v1_test_path(test), headers: headers, as: :json
    assert_response :created
  end

  test "free students see locked tests and get the upgrade options" do
    free = User.create!(name: "Free Student", email_address: "free-api@example.com", password: "Sunflower2026x", date_of_birth: "2000-01-01")
    free.replace_exams!(["UPSC_PRELIMS"])
    headers = api_sign_in(free, password: "Sunflower2026x")

    get api_v1_tests_path, params: { exam: "all" }, headers: headers
    assert json["tests"].find { |t| t["id"] == test_sessions(:one).id }["locked"]

    get api_v1_test_path(test_sessions(:one)), headers: headers
    assert_equal "free", json.dig("upgrade", "tier")

    post start_api_v1_test_path(test_sessions(:one)), headers: headers, as: :json
    assert_response :forbidden
    assert_equal "upgrade_required", json.dig("error", "code")
  end

  test "strict tests: leaving the app warns once, then blocks; the teacher reinstates" do
    test = test_sessions(:two)
    test.update!(strict_mode: true, ends_at: 2.hours.from_now)
    TestPinEntry.create!(test_session: test, user: users(:one))
    headers = api_sign_in(users(:one))

    post start_api_v1_test_path(test), headers: headers, as: :json
    token = json["attempt_token"]

    post report_leave_api_v1_attempt_path(token), params: { seconds: 2 }, headers: headers, as: :json
    assert_equal "ok", json["status"] # short absences are ignored
    post report_leave_api_v1_attempt_path(token), params: { seconds: 20 }, headers: headers, as: :json
    assert_equal 0, json["warnings_left"]
    post report_leave_api_v1_attempt_path(token), params: { seconds: 20 }, headers: headers, as: :json
    assert_equal "blocked", json["status"]

    get api_v1_attempt_path(token), headers: headers
    assert_response :conflict

    teacher = api_sign_in(users(:teacher))
    get live_api_v1_teacher_test_path(test), headers: teacher
    assert_equal "blocked", json["rows"].first["status"]
    post reinstate_api_v1_teacher_test_path(test), params: { attempt_id: TestAttempt.find_by(token: token).id }, headers: teacher, as: :json
    assert_response :success

    get api_v1_attempt_path(token), headers: headers
    assert_response :success
  end

  test "a teacher creates a test and sees its results; students cannot use teacher endpoints" do
    headers = api_sign_in(users(:teacher))
    get api_v1_teacher_form_options_path, headers: headers
    assert_response :success

    post api_v1_teacher_tests_path, params: { test: { title: "App quiz", exam_type: "UPSC_PRELIMS", duration_minutes: 20, pass_mark_percentage: 40,
                                                      access_type: "open", visibility: "public", question_ids: [questions(:one).id] } },
                                    headers: headers, as: :json
    assert_response :created
    id = json.dig("test", "id")
    assert_equal 1, json.dig("test", "question_count")

    patch api_v1_teacher_test_path(id), params: { test: { title: "App quiz 2", question_ids: [questions(:one).id, questions(:two).id] } },
                                        headers: headers, as: :json
    assert_response :success
    assert_equal 2, json.dig("test", "question_count")

    get results_api_v1_teacher_test_path(id), headers: headers
    assert_response :success
    assert_equal 0, json["participants"]

    post api_v1_teacher_questions_path, params: { question: { exam_type: "UPSC_PRELIMS", topic: "Physics", content: "Unit of power?",
                                                              option_a: "Watt", option_b: "Joule", option_c: "Newton", option_d: "Volt",
                                                              correct_answer: "A", visibility: "public" } },
                                        headers: headers, as: :json
    assert_response :created

    student = api_sign_in(users(:one))
    get api_v1_teacher_tests_path, headers: student
    assert_response :forbidden
  end

  test "question bank practice reveals the answer only after an attempt" do
    headers = api_sign_in(users(:one))
    get api_v1_question_bank_topic_path, params: { name: "Physics" }, headers: headers
    assert_response :success
    assert_nil json["questions"].first["correct_answer"]

    post api_v1_question_bank_answer_path, params: { question_id: questions(:one).id, choice: "B" }, headers: headers, as: :json
    assert_response :success
    assert_equal false, json["correct"]
    assert_equal "A", json.dig("question", "correct_answer")

    get api_v1_dashboard_path, headers: headers
    assert_response :success
    assert json.key?("streak_days")
  end
end
