require "test_helper"

# Upgrade -> Pay page: UPI QR + transaction ID checked by an admin, or Razorpay when switched on
class PaymentsTest < ActionDispatch::IntegrationTest
  setup do
    @warrior = Plan.create!(name: "Warrior", kind: "student", price_month_inr: 49, price_year_inr: 399,
                            price_month_upgrade_inr: 29, member_tier: "warrior")
    @starter = Plan.create!(name: "Starter", kind: "school", price_month_inr: 1999, price_year_inr: 19990,
                            max_students: 100, member_tier: "plus")
    @student = User.create!(name: "Free Student", email_address: "free@example.com", password: "Sunflower2026x",
                            date_of_birth: "2000-01-01")
    @student.replace_exams!(["UPSC_PRELIMS"])
    @school = Institution.create!(name: "Sunrise Academy", kind: "school")
    Membership.create!(user: users(:teacher), institution: @school, status: "approved")
    PaymentSetting.current.update!(upi_id: "rankwise@okhdfcbank", payee_name: "Rankwise")
  end

  # Replaces the real Razorpay call for one block (no network in tests)
  def with_fake_razorpay_order(order_id)
    original = RazorpayClient.method(:create_order)
    RazorpayClient.define_singleton_method(:create_order) { |**| { "id" => order_id } }
    yield
  ensure
    RazorpayClient.define_singleton_method(:create_order, original)
  end

  test "a student pays by UPI QR, sends the transaction ID, and an admin approves it" do
    sign_in_as @student
    get membership_path
    assert_select "a[href=?]", new_payment_path(plan_id: @warrior.id, period: "year")

    get new_payment_path(plan_id: @warrior.id, period: "year")
    assert_response :success
    assert_select "svg[aria-label='UPI QR code']"
    assert_match "rankwise@okhdfcbank", response.body
    assert_select "a[href^='upi://pay?pa=rankwise%40okhdfcbank']" # opens the UPI app with the amount filled in
    assert_match "am=399.00", response.body

    assert_difference -> { Payment.pending.count }, 1 do
      post payments_path, params: { payment: { plan_id: @warrior.id, period: "year", utr: "4123 4567 8901" } }
    end
    assert_redirected_to membership_path
    payment = Payment.last
    assert_equal ["412345678901", 399, "free"], [payment.utr, payment.amount_inr, @student.reload.tier]

    sign_in_as users(:admin)
    get admin_payments_path
    assert_match "412345678901", response.body
    assert_select "nav a", text: "Payments (1)"
    get admin_root_path
    assert_match "Payments to check", response.body

    patch approve_admin_payment_path(payment)
    assert payment.reload.approved?
    assert_equal "warrior", @student.reload.tier
    assert_equal Date.current + 1.year, @student.tier_until
    assert_equal "payment", @student.tier_source
    assert_equal "approve_payment", AdminLog.last.action
  end

  test "an admin rejects a transaction ID with a reason; the student keeps their tier" do
    payment = @student.payments.create!(plan: @warrior, period: "month", amount_inr: 49, utr: "999999999999")
    sign_in_as users(:admin)

    patch reject_admin_payment_path(payment), params: { note: "" }
    assert payment.reload.pending? # a reason is required

    patch reject_admin_payment_path(payment), params: { note: "Not found in bank" }
    assert payment.reload.rejected?
    assert_equal "free", @student.reload.tier

    sign_in_as @student
    get membership_path
    assert_match "Not found in bank", response.body
  end

  test "a transaction ID can be used only once, and a Plus student gets the upgrade price" do
    @student.payments.create!(plan: @warrior, period: "month", amount_inr: 49, utr: "111111111111")
    sign_in_as @student
    post payments_path, params: { payment: { plan_id: @warrior.id, period: "month", utr: "111111111111" } }
    assert_response :unprocessable_entity
    assert_match "already been submitted", response.body

    assert_equal 29, Payment.amount_for(@warrior, "month", Struct.new(:tier).new("plus"))
    assert_equal 49, Payment.amount_for(@warrior, "month", Struct.new(:tier).new("free"))
    assert_equal 399, Payment.amount_for(@warrior, "year", Struct.new(:tier).new("plus"))
  end

  test "a teacher pays for their school's plan; approval makes the school active" do
    sign_in_as users(:teacher)
    get payments_path
    assert_select "a[href=?]", new_payment_path(plan_id: @starter.id, period: "month", institution_id: @school.id)

    post payments_path, params: { payment: { plan_id: @starter.id, period: "month", institution_id: @school.id, utr: "222222222222" } }
    assert_redirected_to payments_path
    payment = Payment.last
    assert_equal [@school, 1999], [payment.institution, payment.amount_inr]

    other = Institution.create!(name: "Other School", kind: "school")
    post payments_path, params: { payment: { plan_id: @starter.id, period: "month", institution_id: other.id, utr: "333333333333" } }
    assert_response :unprocessable_entity # not their school

    payment.approve!(users(:admin))
    @school.reload
    assert @school.subscribed?
    assert_equal [@starter, Date.current + 1.month], [@school.plan, @school.subscription_renews_on]
  end

  test "with Razorpay on, a paid order with a valid signature activates the plan at once" do
    PaymentSetting.current.update!(gateway_enabled: true, razorpay_key_id: "rzp_test_abc123", razorpay_key_secret: "s3cret")
    sign_in_as @student

    get new_payment_path(plan_id: @warrior.id, period: "month")
    assert_select "#razorpay-button"
    assert_select "svg[aria-label='UPI QR code']", 0

    with_fake_razorpay_order("order_test_1") do
      post razorpay_order_payments_path, params: { plan_id: @warrior.id, period: "month" }, as: :json
    end
    assert_response :success
    assert_equal ["order_test_1", 4900, "rzp_test_abc123"], [json_body["order_id"], json_body["amount"], json_body["key"]]
    payment = Payment.find_by!(razorpay_order_id: "order_test_1")
    assert_equal "created", payment.status

    post razorpay_verify_payment_path(payment), params: { razorpay_order_id: "order_test_1", razorpay_payment_id: "pay_1", razorpay_signature: "forged" }
    assert_equal "created", payment.reload.status
    assert_equal "free", @student.reload.tier

    signature = OpenSSL::HMAC.hexdigest("SHA256", "s3cret", "order_test_1|pay_1")
    post razorpay_verify_payment_path(payment), params: { razorpay_order_id: "order_test_1", razorpay_payment_id: "pay_1", razorpay_signature: signature }
    assert_redirected_to membership_path
    assert payment.reload.approved?
    assert_equal "warrior", @student.reload.tier
  end

  test "payment settings: admins only, and online payment needs both keys" do
    sign_in_as users(:teacher)
    get edit_admin_payment_settings_path
    assert_response :redirect

    sign_in_as users(:admin)
    get edit_admin_payment_settings_path
    assert_response :success

    patch admin_payment_settings_path, params: { payment_setting: { gateway_enabled: "1", razorpay_key_id: "rzp_live_x1" } }
    assert_response :unprocessable_entity
    assert_not PaymentSetting.current.gateway_ready?

    patch admin_payment_settings_path, params: { payment_setting: { gateway_enabled: "1", razorpay_key_id: "rzp_live_x1", razorpay_key_secret: "topsecret" } }
    assert PaymentSetting.current.reload.gateway_ready?
    assert_equal "topsecret", PaymentSetting.current.razorpay_key_secret
    assert_not_equal "topsecret", PaymentSetting.current.encrypted_razorpay_key_secret
  end

  private

  def json_body = JSON.parse(response.body)
end
