# A student entered this test's PIN (see TestSessionsController#verify_pin)
class TestPinEntry < ApplicationRecord
  belongs_to :test_session
  belongs_to :user
end
