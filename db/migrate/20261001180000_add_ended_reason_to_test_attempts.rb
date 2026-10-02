# Strict open tests end when the student leaves the test page: why, shown to the student and the teacher
class AddEndedReasonToTestAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :test_attempts, :ended_reason, :string
  end
end
