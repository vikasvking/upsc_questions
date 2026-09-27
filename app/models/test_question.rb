class TestQuestion < ApplicationRecord
  belongs_to :test_session
  belongs_to :question
end
