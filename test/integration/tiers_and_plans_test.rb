require "test_helper"

class TiersAndPlansTest < ActionDispatch::IntegrationTest
  setup do
    @free = User.create!(name: "Free Student", email_address: "free@example.com", password: "Sunflower2026x",
                         date_of_birth: "2000-01-01")
    @free.replace_exams!(["UPSC_PRELIMS"])
    @sample = test_sessions(:one)           # open, public
    @sample.update!(free_sample: true)
    @other = test_sessions(:two)            # public PIN test, not a sample
    questions(:one).update!(free_sample: true)
  end

  def school_with_plan(limits = {})
    plan = Plan.create!({ name: "Starter #{SecureRandom.hex(2)}", kind: "school", price_month_inr: 1999, price_year_inr: 19990,
                          max_students: 100, max_teachers: 5, max_tests_per_month: 8, member_tier: "plus", member_max_exams: 1 }.merge(limits))
    Institution.create!(name: "Sunrise #{SecureRandom.hex(2)}", kind: "school", plan: plan, subscription_status: "active")
  end

  test "free students get only the sample tests and sample questions, each once" do
    assert_equal "free", @free.tier
    sign_in_as @free

    # every public test is listed; the non-sample one is locked with an upgrade button
    get all_tests_dashboard_path, params: { exam: "all" }
    assert_select "h3", text: @sample.title
    assert_select "h3", text: @other.title
    assert_select "a[href=?]", test_intro_dashboard_path(@other), text: /Upgrade to unlock/
    assert_select "a[href=?]", test_intro_dashboard_path(@sample), text: /Upgrade/, count: 0

    # clicking it shows the test's details with the upgrade options, not a Start button
    get test_intro_dashboard_path(@other)
    assert_response :success
    assert_select "a[href=?]", membership_path, text: /upgrade options/
    assert_select "button", text: "Start Test", count: 0

    # starting it anyway is still refused, and lands on the upgrade page
    post start_test_dashboard_path, params: { test_session_id: @other.id }
    assert_redirected_to test_intro_dashboard_path(@other)
    assert_equal 0, @free.test_attempts.where(test_session: @other).count

    # the right PIN for a locked test also leads to the upgrade page, not "Invalid PIN"
    post verify_pin_test_sessions_path, params: { pin_code: @other.pin_code }
    assert_redirected_to test_intro_dashboard_path(@other)

    post question_bank_answer_path, params: { question_id: questions(:one).id, answer_choice: "A" }
    assert_equal 1, @free.user_responses.count
    post question_bank_answer_path, params: { question_id: questions(:one).id, answer_choice: "B" }
    assert_equal 1, @free.user_responses.count # only once

    post question_bank_answer_path, params: { question_id: questions(:two).id, answer_choice: "B" }
    assert_response :not_found # not a sample question

    post start_test_dashboard_path, params: { topic: "Physics" }
    assert_redirected_to question_bank_path
  end

  test "an active school plan makes its students Plus, limited to their exams outside school tests" do
    school = school_with_plan
    Membership.create!(user: @free, institution: school, status: "approved")
    @free.reload
    assert_equal "plus", @free.tier
    assert_equal ["UPSC_PRELIMS"], @free.allowed_exam_codes

    neet = TestSession.create!(user: users(:teacher), title: "NEET mock", exam_type: "NEET", duration_minutes: 10,
                               pass_mark_percentage: 40, access_type: "open", question_ids: [questions(:two).id])
    school_test = TestSession.create!(user: users(:teacher), title: "School NEET test", exam_type: "NEET", duration_minutes: 10,
                                      pass_mark_percentage: 40, access_type: "open", visibility: "institution", institution: school,
                                      question_ids: [questions(:two).id])
    available = TestSession.available_to(@free)
    assert_includes available, @other           # public UPSC test
    assert_not_includes available, neet         # public, but not one of their exams
    assert_includes available, school_test      # school tests are always open to them

    # Plus students see the other exam's public test too, locked, with the Warrior nudge
    sign_in_as @free
    get all_tests_dashboard_path, params: { exam: "all" }
    assert_select "a[href=?]", test_intro_dashboard_path(neet), text: /Upgrade to unlock/
    assert_select "a[href=?]", test_intro_dashboard_path(school_test), text: /Upgrade/, count: 0
    get test_intro_dashboard_path(neet)
    assert_match "Your Plus plan covers", response.body

    school.update!(subscription_status: "suspended")
    assert_equal "free", @free.reload.tier
  end

  test "a student's own Warrior tier unlocks everything until it ends" do
    @free.update!(membership_tier: "warrior", tier_until: Date.current + 30)
    assert_equal "warrior", @free.reload.tier
    @free.update!(tier_until: Date.current - 1)
    assert_equal "free", @free.reload.tier
  end

  test "a full school cannot take more students" do
    school = school_with_plan(max_students: 1)
    Membership.create!(user: users(:one), institution: school, status: "approved")
    request = Membership.create!(user: users(:two), institution: school)
    assert_raises(Membership::LimitReached) { request.approve! }

    sign_in_as @free
    post memberships_path, params: { institution_id: school.id, join_code: school.join_code }
    assert_match "limit of 1 students", flash[:alert]
    assert @free.memberships.find_by(institution: school).pending?
  end

  test "teachers can publish only the school's monthly number of tests" do
    school = school_with_plan(max_tests_per_month: 1)
    Membership.create!(user: users(:teacher), institution: school, status: "approved")
    sign_in_as users(:teacher)

    params = ->(title) { { test_session: { title: title, exam_type: "UPSC_PRELIMS", duration_minutes: 20, pass_mark_percentage: 40,
                                           access_type: "open", visibility: "institution", institution_id: school.id,
                                           question_ids: [questions(:one).id] } } }
    post test_sessions_path, params: params.("First school test")
    assert TestSession.exists?(title: "First school test")

    post test_sessions_path, params: params.("Second school test")
    assert_response :unprocessable_entity
    assert_match "used all 1 tests", response.body
    assert_not TestSession.exists?(title: "Second school test")
  end

  test "a school without an active plan cannot have school tests" do
    school = Institution.create!(name: "No Plan School", kind: "school")
    Membership.create!(user: users(:teacher), institution: school, status: "approved")
    sign_in_as users(:teacher)
    post test_sessions_path, params: { test_session: { title: "Blocked", exam_type: "UPSC_PRELIMS", duration_minutes: 20, pass_mark_percentage: 40,
                                                       access_type: "open", visibility: "institution", institution_id: school.id,
                                                       question_ids: [questions(:one).id] } }
    assert_response :unprocessable_entity
    assert_match "no active plan", response.body
  end

  test "at most four sample tests, and they must be public" do
    3.times do |i|
      TestSession.create!(user: users(:teacher), title: "Sample #{i}", exam_type: "UPSC_PRELIMS", duration_minutes: 10,
                          pass_mark_percentage: 40, access_type: "open", free_sample: true, question_ids: [questions(:one).id])
    end
    fifth = TestSession.new(user: users(:teacher), title: "Too many", exam_type: "UPSC_PRELIMS", duration_minutes: 10,
                            pass_mark_percentage: 40, access_type: "open", free_sample: true)
    assert_not fifth.valid?

    private_sample = @other
    private_sample.assign_attributes(free_sample: true, visibility: "institution", institution: school_with_plan)
    assert_not private_sample.valid?
  end

  test "admin sets a school's plan and status; the change is logged" do
    school = Institution.create!(name: "New School", kind: "school")
    plan = Plan.create!(name: "Standard X", kind: "school", price_month_inr: 4999, price_year_inr: 49990, max_students: 300)
    sign_in_as users(:admin)
    patch subscription_admin_institution_path(school), params: { institution: { plan_id: plan.id, subscription_status: "trial",
                                                                                override_max_students: "350" } }
    school.reload
    assert school.subscribed?
    assert_equal 350, school.limit_for(:students)
    assert_equal "update_subscription", AdminLog.last.action

    get admin_plans_path
    assert_response :success
    get membership_path
    assert_response :success
  end

  test "a sub-admin cannot change plans or a school's subscription" do
    school = school_with_plan
    Membership.create!(user: users(:teacher), institution: school, status: "approved")
    users(:teacher).update!(permissions: %w[institutions])
    sign_in_as users(:teacher)
    get admin_plans_path
    assert_redirected_to admin_root_path
    patch subscription_admin_institution_path(school), params: { institution: { subscription_status: "cancelled" } }
    assert_equal "active", school.reload.subscription_status
  end

  test "students see their membership page" do
    sign_in_as @free
    get membership_path
    assert_response :success
    assert_match "free trial", response.body
  end
end
