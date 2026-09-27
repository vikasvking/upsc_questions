require "test_helper"

class QuestionbanksControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get questionbanks_show_url
    assert_response :success
  end
end
