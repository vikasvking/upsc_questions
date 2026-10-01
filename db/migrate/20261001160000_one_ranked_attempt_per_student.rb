# Each student gets exactly one ranked (first) attempt per teacher test. Without this, two taps on Start,
# or starting on the website and the app at the same moment, could create two first attempts that were both ranked.
class OneRankedAttemptPerStudent < ActiveRecord::Migration[8.1]
  INDEX = "index_test_attempts_one_first_try".freeze

  def up
    # Any duplicates already in the database: keep the attempt the student actually used (the one with the
    # most answers, or the newest when equal, which is the one the test pages resumed) as the ranked one,
    # and turn the others into practice retakes. No answers are deleted.
    execute <<~SQL
      UPDATE test_attempts SET retake = TRUE, updated_at = NOW()
      WHERE id IN (
        SELECT id FROM (
          SELECT a.id,
                 ROW_NUMBER() OVER (
                   PARTITION BY a.user_id, a.test_session_id
                   ORDER BY (SELECT COUNT(*) FROM user_responses r WHERE r.test_session_token = a.token) DESC, a.id DESC
                 ) AS n
          FROM test_attempts a
          WHERE a.retake = FALSE AND a.test_session_id IS NOT NULL
        ) ranked
        WHERE ranked.n > 1
      )
    SQL

    add_index :test_attempts, [:user_id, :test_session_id], unique: true, name: INDEX,
                                                            where: "retake = FALSE AND test_session_id IS NOT NULL"
  end

  def down
    remove_index :test_attempts, name: INDEX
  end
end
