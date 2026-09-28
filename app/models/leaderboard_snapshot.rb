# One saved copy of the topper table (see Leaderboard.refresh!)
class LeaderboardSnapshot < ApplicationRecord
  def self.latest = order(computed_at: :desc).first

  def to_rows
    rows.map { |h| Leaderboard::Row.new(**h.symbolize_keys) }
  end
end
