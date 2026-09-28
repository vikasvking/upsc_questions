# The background scheduler saves the computed topper table here every 10 minutes,
# so dashboards and the homepage read one row instead of scanning every answer.
class CreateLeaderboardSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :leaderboard_snapshots do |t|
      t.jsonb :rows, null: false, default: []
      t.datetime :computed_at, null: false
      t.timestamps
    end
  end
end
