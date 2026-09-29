# One saved copy of the topper table (see Leaderboard.refresh!)
class LeaderboardSnapshot < ApplicationRecord
  def self.latest(exam = nil)
    scope = exam ? where(exam_type: exam) : all
    scope.order(computed_at: :desc).first
  end

  def to_rows
    rows.map { |h| Leaderboard::Row.new(**h.symbolize_keys) }
  end
end
