# Recomputes the topper table. Scheduled every 10 minutes in config/recurring.yml.
class RefreshLeaderboardJob < ApplicationJob
  queue_as :default
  background_switch :refresh_leaderboard # on/off on Admin → Background work

  def perform
    Leaderboard.refresh_all! # one topper table per exam
  end
end
