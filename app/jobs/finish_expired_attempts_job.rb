# Submits tests whose time ran out while the student had the page closed,
# so teachers' result pages and ranks are complete without anyone opening them.
# Scheduled every 5 minutes in config/recurring.yml.
class FinishExpiredAttemptsJob < ApplicationJob
  queue_as :default

  def perform
    TestAttempt.in_progress
               .where("deadline_at < ?", TestAttempt::GRACE_PERIOD.ago)
               .find_each(&:finish!)
  end
end
