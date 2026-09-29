require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "only admins can open the admin pages" do
    sign_in_as users(:teacher)
    get admin_root_path
    assert_redirected_to test_sessions_path

    sign_in_as users(:one)
    get admin_users_path
    assert_redirected_to dashboard_path
  end

  test "admin pages load" do
    [admin_root_path, admin_users_path, admin_user_path(users(:teacher)), new_admin_user_path, edit_admin_user_path(users(:one)),
     admin_questions_path, new_admin_question_path, edit_admin_question_path(questions(:one)),
     admin_test_sessions_path, new_admin_test_session_path, edit_admin_test_session_path(test_sessions(:one)), admin_logs_path].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "admin creates a teacher and it is logged" do
    assert_difference -> { User.teacher.count }, 1 do
      post admin_users_path, params: { user: { email_address: "new.teacher@example.com", role: "teacher",
                                               password: "secret123", password_confirmation: "secret123" } }
    end
    assert_equal "create_user", AdminLog.last.action
    assert_equal users(:admin), AdminLog.last.admin
  end

  test "admin cannot delete their own account or the last admin" do
    delete admin_user_path(users(:admin))
    assert User.exists?(users(:admin).id)
  end

  test "deleting a teacher keeps their tests, shown under the exam name" do
    test = test_sessions(:one)
    delete admin_user_path(users(:teacher))
    assert_redirected_to admin_users_path

    test.reload
    assert_nil test.user_id
    assert_equal "UPSC Prelims", test.author_name
    assert questions(:one).reload.persisted?
  end

  test "deleting a student with results needs their email typed" do
    users(:one).test_attempts.create!(test_session: test_sessions(:one))
    delete admin_user_path(users(:one))
    assert User.exists?(users(:one).id)

    delete admin_user_path(users(:one)), params: { confirm_text: users(:one).email_address }
    assert_not User.exists?(users(:one).id)
  end

  test "a locked test needs a reason, then the admin can change it and it is logged" do
    test = test_sessions(:two)
    test.update!(strict_mode: true, ends_at: 2.hours.from_now)
    users(:one).test_attempts.create!(test_session: test) # a student started, so it is locked
    assert test.reload.editing_locked?

    patch admin_test_session_path(test), params: { test_session: { title: "Fixed title", question_ids: [questions(:one).id, questions(:two).id] } }
    assert_response :unprocessable_entity
    assert_equal "PIN Physics Test", test.reload.title
    assert_equal [questions(:one).id], test.question_ids

    patch admin_test_session_path(test), params: { reason: "Teacher asked to add Q2",
                                                   test_session: { title: "Fixed title", question_ids: [questions(:one).id, questions(:two).id] } }
    assert_redirected_to admin_test_sessions_path
    assert_equal "Fixed title", test.reload.title
    assert_equal [questions(:one).id, questions(:two).id].sort, test.question_ids.sort

    log = AdminLog.last
    assert_equal "update_locked_test", log.action
    assert_equal "Teacher asked to add Q2", log.reason
  end

  test "outside the admin pages a locked test cannot be changed" do
    test = test_sessions(:two)
    test.update!(strict_mode: true, ends_at: 2.hours.from_now)
    users(:one).test_attempts.create!(test_session: test)

    assert_not test.reload.update(title: "Sneaky")
    assert_raises(TestSession::Locked) { test.question_ids = [questions(:two).id] }
  end

  test "extending the closing time applies to students already writing" do
    test = test_sessions(:two)
    test.update!(ends_at: 20.minutes.from_now, duration_minutes: 120)
    attempt = users(:one).test_attempts.create!(test_session: test)
    assert_in_delta 20.minutes.from_now, attempt.deadline_at, 5

    patch admin_test_session_path(test), params: { reason: "Power cut at the centre",
                                                   test_session: { ends_at: 1.hour.from_now.strftime("%Y-%m-%dT%H:%M"), question_ids: test.question_ids } }
    assert_in_delta 1.hour.from_now, attempt.reload.deadline_at, 60
  end

  test "a corrected answer key re-marks saved answers" do
    q = questions(:one) # answer A
    users(:one).user_responses.create!(question: q, chosen_option: "B", is_correct: false)
    users(:two).user_responses.create!(question: q, chosen_option: "A", is_correct: true)

    patch admin_question_path(q), params: { question: { correct_answer: "B" } }
    assert_redirected_to admin_questions_path
    assert users(:one).user_responses.find_by(question: q).is_correct
    assert_not users(:two).user_responses.find_by(question: q).is_correct
  end

  test "deleting a test with results needs its title typed" do
    test = test_sessions(:one)
    users(:one).test_attempts.create!(test_session: test)

    delete admin_test_session_path(test)
    assert TestSession.exists?(test.id)

    delete admin_test_session_path(test), params: { confirm_text: test.title }
    assert_not TestSession.exists?(test.id)
    assert_equal "delete_test", AdminLog.last.action
  end
end
