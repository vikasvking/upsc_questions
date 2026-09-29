require "test_helper"

class SignupAndAccountsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  def signup(extra = {})
    post sign_up_path, params: { signup: {
      role: "student", name: "Priya Sharma", email_address: "priya@example.com",
      password: "Mountain2026x", password_confirmation: "Mountain2026x",
      date_of_birth: "2000-05-01", exam_codes: ["NEET", "JEE_MAIN"]
    }.merge(extra) }
  end

  def enable_mail!
    MailSetting.current.update!(enabled: true, address: "smtp.example.com", from_address: "no-reply@example.com")
  end

  test "adult student signs up with several exams" do
    assert_difference -> { User.count }, 1 do
      signup
    end
    user = User.find_by(email_address: "priya@example.com")
    assert_redirected_to dashboard_path
    assert_equal %w[JEE_MAIN NEET], user.exam_codes.sort
    assert_equal "Priya Sharma", user.name
  end

  test "weak passwords and mistyped emails are refused" do
    assert_no_difference -> { User.count } do
      signup(password: "password123", password_confirmation: "password123")
    end
    assert_response :unprocessable_entity
    assert_match "too common", response.body

    assert_no_difference -> { User.count } do
      signup(email_address: "priya@gmial.com")
    end
    assert_match "did you mean priya@gmail.com", response.body
  end

  test "joining with the right code is instant; without it a teacher approves" do
    inst = Institution.create!(name: "Sunrise Academy", kind: "coaching", city: "Sambalpur")
    Membership.create!(user: users(:teacher), institution: inst, status: "approved")

    signup(institution_id: inst.id, join_code: inst.join_code.downcase)
    assert User.find_by(email_address: "priya@example.com").memberships.first.approved?

    signup(email_address: "ravi@example.com", institution_id: inst.id)
    request = User.find_by(email_address: "ravi@example.com").memberships.first
    assert request.pending?

    users(:teacher).update!(permissions: ["approvals"]) # a sub-admin of this coaching approves requests
    sign_in_as users(:teacher)
    patch approve_membership_path(request)
    assert request.reload.approved?
  end

  test "teachers wait for admin approval" do
    post sign_up_path, params: { signup: {
      role: "teacher", name: "Meera Iyer", email_address: "meera@example.com",
      password: "Blackboard2026", password_confirmation: "Blackboard2026", subjects: "Polity, History"
    } }
    assert_redirected_to pending_approval_path
    teacher = User.find_by(email_address: "meera@example.com")
    assert teacher.pending_teacher?
    assert_equal %w[History Polity], teacher.subject_names

    get test_sessions_path
    assert_redirected_to pending_approval_path

    sign_in_as users(:admin)
    patch approve_admin_user_path(teacher)
    assert teacher.reload.approved?
  end

  test "under 18: the account is created only after the parent's code" do
    enable_mail!
    dob = (Date.current - 15.years).iso8601

    assert_no_difference -> { User.count } do
      assert_emails 1 do
        signup(date_of_birth: dob, parent_email: "parent@example.com", parent_phone: "9876543210")
      end
    end
    pending = PendingSignup.last
    assert_redirected_to consent_path(pending.token)
    mail = ActionMailer::Base.deliveries.last
    assert_equal ["parent@example.com"], mail.to
    code = mail.text_part.body.to_s[/\b\d{6}\b/]

    post verify_consent_path(pending.token), params: { code: "000000" == code ? "111111" : "000000" }
    assert_nil User.find_by(email_address: "priya@example.com")

    post verify_consent_path(pending.token), params: { code: code }
    user = User.find_by(email_address: "priya@example.com")
    assert user
    assert user.parent_consent?
    assert_equal "9876543210", user.guardian_consents.first.parent_phone
    assert_not PendingSignup.exists?(pending.id)
  end

  test "under 18 needs a parent's contact, and email switched on" do
    dob = (Date.current - 15.years).iso8601
    assert_no_difference -> { PendingSignup.count } do
      signup(date_of_birth: dob)
    end
    assert_match "Parent", response.body

    signup(date_of_birth: dob, parent_email: "parent@example.com", parent_phone: "9876543210")
    assert_response :unprocessable_entity
    assert_match "paused until email sending is set up", response.body
  end

  test "an existing under-18 student is asked for parent consent" do
    users(:one).update_column(:date_of_birth, Date.current - 14.years)
    sign_in_as users(:one)
    get dashboard_path
    assert_redirected_to new_parent_consent_path
  end

  test "incomplete profiles are sent to the profile page" do
    users(:one).update_column(:name, nil)
    sign_in_as users(:one)
    get dashboard_path
    assert_redirected_to edit_profile_path

    patch profile_details_path, params: { user: { name: "Student One", exam_codes: ["UPSC_PRELIMS", "SSC_CGL"] } }
    assert_redirected_to profile_path
    assert_equal %w[SSC_CGL UPSC_PRELIMS], users(:one).reload.exam_codes.sort
  end

  test "a teacher sub-admin approves only at their own institution and deletes nothing" do
    mine  = Institution.create!(name: "Sunrise Academy", kind: "coaching")
    other = Institution.create!(name: "Other Coaching", kind: "coaching")
    Membership.create!(user: users(:teacher), institution: mine, status: "approved")
    users(:teacher).update!(permissions: %w[approvals tests])
    assert users(:teacher).sub_admin?

    here  = Membership.create!(user: users(:one), institution: mine)
    there = Membership.create!(user: users(:two), institution: other)
    new_teacher = User.create!(name: "New Teacher", email_address: "newt@example.com", role: "teacher", password: "Chalkboard2026")
    Membership.create!(user: new_teacher, institution: mine)

    sign_in_as users(:teacher)
    get admin_approvals_path
    assert_response :success
    assert_match "New Teacher", response.body
    assert_no_match users(:two).display_name, response.body

    patch approve_membership_path(here)
    assert here.reload.approved?
    patch approve_membership_path(there)
    assert there.reload.pending?

    patch approve_teacher_admin_approval_path(new_teacher)
    assert new_teacher.reload.approved?

    get admin_users_path
    assert_redirected_to admin_root_path
    get edit_admin_mail_settings_path
    assert_redirected_to admin_root_path

    test = test_sessions(:one)
    delete admin_test_session_path(test)
    assert TestSession.exists?(test.id)
    get edit_admin_test_session_path(test)
    assert_response :success # can still change tests

    get admin_questions_path
    assert_redirected_to admin_root_path # not given the questions area
  end

  test "only teachers can be sub-admins, and ordinary teachers cannot approve" do
    user = users(:one)
    assert_not user.update(permissions: ["approvals"])

    inst = Institution.create!(name: "Sunrise Academy", kind: "coaching")
    Membership.create!(user: users(:teacher_two), institution: inst, status: "approved")
    request = Membership.create!(user: users(:two), institution: inst)
    sign_in_as users(:teacher_two)
    patch approve_membership_path(request)
    assert request.reload.pending?
  end

  test "admin saves email settings; the password is stored encrypted" do
    sign_in_as users(:admin)
    patch admin_mail_settings_path, params: { mail_setting: { enabled: "1", address: "smtp.example.com", port: 587,
                                                              user_name: "apikey", password: "s3cret-smtp", from_address: "no-reply@example.com" } }
    assert_redirected_to edit_admin_mail_settings_path
    setting = MailSetting.current
    assert setting.active?
    assert_equal "s3cret-smtp", setting.password
    assert_not_includes setting.encrypted_password, "s3cret-smtp"

    patch admin_mail_settings_path, params: { mail_setting: { enabled: "0", password: "" } }
    assert_not MailSetting.current.active?
    assert_equal "s3cret-smtp", MailSetting.current.password # blank keeps the saved password
  end

  test "email confirmation link" do
    user = users(:one)
    get email_confirmation_path(token: user.generate_token_for(:email_confirmation))
    assert user.reload.email_confirmed?
  end
end
