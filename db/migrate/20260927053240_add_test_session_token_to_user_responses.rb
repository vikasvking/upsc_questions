class AddTestSessionTokenToUserResponses < ActiveRecord::Migration[8.1]
  def change
    add_column :user_responses, :test_session_token, :string
  end
end
