# Moves from 5 broad exam labels to 9 specific exams (see app/models/exam.rb).
class SplitExamTypes < ActiveRecord::Migration[8.1]
  MAPPING = {
    "UPSC" => "UPSC_PRELIMS",
    "JEE" => "JEE_MAIN",
    "SSC" => "SSC_CGL",
    "CBSE" => "CBSE_X",
    "BANKING" => "IBPS"
  }.freeze

  def up
    MAPPING.each do |old, new|
      execute "UPDATE questions SET exam_type = #{quote(new)} WHERE UPPER(exam_type) = #{quote(old)}"
      execute "UPDATE test_sessions SET exam_type = #{quote(new)} WHERE UPPER(exam_type) = #{quote(old)}"
    end

    # "Preparing for" on the profile; ranks on the dashboard default to this exam
    add_column :users, :target_exam, :string

    # One saved topper table per exam
    add_column :leaderboard_snapshots, :exam_type, :string
    add_index  :leaderboard_snapshots, [:exam_type, :computed_at]
    execute "DELETE FROM leaderboard_snapshots" # old all-exam tables; rebuilt on the next refresh
  end

  def down
    remove_index  :leaderboard_snapshots, [:exam_type, :computed_at]
    remove_column :leaderboard_snapshots, :exam_type
    remove_column :users, :target_exam
    MAPPING.each do |old, new|
      execute "UPDATE questions SET exam_type = #{quote(old)} WHERE exam_type = #{quote(new)}"
      execute "UPDATE test_sessions SET exam_type = #{quote(old)} WHERE exam_type = #{quote(new)}"
    end
  end

  private

  def quote(value) = connection.quote(value)
end
