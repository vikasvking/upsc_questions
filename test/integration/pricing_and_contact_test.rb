require "test_helper"

# Home page pricing (from Admin → Plans) and the footer contact form (only while email is on)
class PricingAndContactTest < ActionDispatch::IntegrationTest
  def email_on!
    MailSetting.current.update!(enabled: true, address: "smtp.example.com", from_address: "no-reply@example.com")
  end

  def contact_params(overrides = {})
    { contact_message: { name: "Ritu Sharma", email: "ritu@example.com", phone: "98765 43210", organisation: "Sunrise Academy",
                         topic: "custom_plan", message: "We have 1,500 students in 3 branches." }.merge(overrides) }
  end

  test "the home page shows the plans the admin offers, with their prices" do
    Plan.create!(name: "Starter", kind: "school", price_month_inr: 1999, price_year_inr: 19990, max_students: 100,
                 max_teachers: 5, max_tests_per_month: 8, member_tier: "plus", member_max_exams: 2)
    Plan.create!(name: "Warrior", kind: "student", price_month_inr: 49, price_year_inr: 399, price_month_upgrade_inr: 29,
                 member_tier: "warrior")
    Plan.create!(name: "Old plan", kind: "school", price_month_inr: 999, price_year_inr: 9990, active: false)

    get root_path
    assert_response :success
    assert_select "#pricing", text: /Starter/
    assert_match "₹1,999", response.body
    assert_match "Up to 100 students", response.body
    assert_match "₹49", response.body
    assert_match "₹29/month", response.body
    assert_match "save 32%", response.body # 399 instead of 49 × 12 = 588
    assert_no_match "Old plan", response.body
    assert_select "#pricing", text: /Custom/
  end

  test "a price changed in Admin → Plans shows on the home page" do
    plan = Plan.create!(name: "Standard", kind: "school", price_month_inr: 4999, price_year_inr: 49990)
    sign_in_as users(:admin)
    patch admin_plan_path(plan), params: { plan: { price_month_inr: 5499 } }
    sign_out

    get root_path
    assert_match "₹5,499", response.body
  end

  test "the contact form is hidden while email is off" do
    get root_path
    assert_select "form[action=?]", contact_messages_path, count: 0

    assert_no_difference -> { ContactMessage.count } do
      post contact_messages_path, params: contact_params
    end
  end

  test "with email on, a visitor's message is saved and emailed to the admins" do
    email_on!
    get root_path(topic: "custom_plan")
    assert_select "form[action=?]", contact_messages_path
    assert_select "select#contact_message_topic option[selected][value=custom_plan]"
    assert_select "a[href=?]", root_path(topic: "custom_plan", anchor: "contact"), text: "Contact us"

    assert_difference -> { ContactMessage.count }, 1 do
      assert_emails 1 do
        post contact_messages_path, params: contact_params
      end
    end
    assert_redirected_to root_path(anchor: "contact")
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.to, users(:admin).email_address
    assert_equal ["ritu@example.com"], mail.reply_to
    assert_match "Custom plan", mail.subject

    follow_redirect!
    assert_match "Thank you, Ritu Sharma!", response.body
  end

  test "a message with a mistake shows the form again with the visitor's text" do
    email_on!
    assert_no_difference -> { ContactMessage.count } do
      post contact_messages_path, params: contact_params(email: "not-an-email")
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Email is invalid/
    assert_select "textarea#contact_message_message", text: /1,500 students/
  end

  test "bots that fill in the hidden field are ignored" do
    email_on!
    assert_no_difference -> { ContactMessage.count } do
      post contact_messages_path, params: contact_params.merge(website: "http://spam.example")
    end
    assert_redirected_to root_path(anchor: "contact")
  end

  test "admins read messages and mark them done; others cannot" do
    message = ContactMessage.create!(name: "Ritu", email: "ritu@example.com", topic: "question", message: "Hello")

    sign_in_as users(:teacher)
    get admin_contact_messages_path
    assert_response :redirect

    sign_in_as users(:admin)
    get admin_contact_messages_path
    assert_response :success
    assert_match "Hello", response.body
    assert_select "nav a", text: "Messages (1)"

    patch admin_contact_message_path(message, status: "done")
    assert message.reload.done?
    assert_equal users(:admin), message.handled_by
    assert_equal "update_contact_message", AdminLog.last.action

    get admin_contact_messages_path
    assert_no_match "Hello", response.body # only new ones by default
    get admin_contact_messages_path(status: "done")
    assert_match "Hello", response.body
  end
end
