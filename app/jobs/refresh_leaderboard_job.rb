# Recomputes the topper table. Scheduled every 10 minutes in config/recurring.yml.
class RefreshLeaderboardJob < ApplicationJob
  queue_as :default

  def perform
    Leaderboard.refresh!
  end
end
