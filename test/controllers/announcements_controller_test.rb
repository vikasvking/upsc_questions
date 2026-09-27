require "test_helper"

class AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get announcements_show_url
    assert_response :success
  end
end
