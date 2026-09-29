# Students can take a teacher test again, as many times as they like. Those extra attempts are practice:
# only a student's first attempt counts for the test's rank list (see TestSession#rankings).
class AddRetakeToTestAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :test_attempts, :retake, :boolean, default: false, null: false
  end
end
