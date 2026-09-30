require "test_helper"

# The app registers its phone for push notifications and changes the switches under Me
class ApiPushTest < ActionDispatch::IntegrationTest
  def json = response.parsed_body

  def sign_in(user)
    post api_v1_session_path, params: { email_address: user.email_address, password: "password" }, as: :json
    { "Authorization" => "Bearer #{response.parsed_body["token"]}" }
  end

  test "a phone is registered, moved to whoever signs in next, and removed on sign-out" do
    headers = sign_in(users(:one))
    post api_v1_devices_path, params: { token: "abc123", platform: "android" }, headers: headers, as: :json
    assert_response :created
    assert_equal %w[all_UPSC_PRELIMS tests_UPSC_PRELIMS], json["push_topics"]
    assert_equal users(:one), DeviceToken.find_by!(token: "abc123").user

    # the same phone, another student
    other = sign_in(users(:two))
    post api_v1_devices_path, params: { token: "abc123" }, headers: other, as: :json
    assert_equal users(:two), DeviceToken.find_by!(token: "abc123").user
    assert_equal 1, DeviceToken.count

    delete api_v1_devices_path, params: { token: "abc123" }, headers: other, as: :json
    assert_response :no_content
    assert_equal 0, DeviceToken.count

    post api_v1_devices_path, params: { token: "" }, headers: other, as: :json
    assert_response :unprocessable_entity
  end

  test "notification switches are saved and turning off new tests empties the topics" do
    headers = sign_in(users(:one))
    get api_v1_me_path, headers: headers, as: :json
    assert_equal({ "new_tests" => true, "results" => true, "reminders" => true }, json.dig("user", "notifications"))

    patch api_v1_me_notifications_path, params: { new_tests: false, reminders: false }, headers: headers, as: :json
    assert_response :success
    assert_equal({ "new_tests" => false, "results" => true, "reminders" => false }, json.dig("user", "notifications"))
    assert_empty json.dig("user", "push_topics")
    assert_not users(:one).reload.push_reminders?
  end
end
