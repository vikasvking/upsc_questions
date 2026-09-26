require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get questions_index_url
    assert_response :success
  end

  test "should get upload_form" do
    get questions_upload_form_url
    assert_response :success
  end
end
