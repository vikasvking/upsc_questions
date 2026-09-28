# app/models/leaderboard.rb
# Compares students: "Top 10" = the 10 students with the most solved questions
# (ties broken by accuracy). Only student accounts are counted.
#
# Metrics per student
#   solved          questions answered correctly at least once
#   accuracy        correct answers / all answers (skips excluded), in %
#   avg_seconds     average time spent per answered question
#   topics_completed topics where every question is solved
#   active_days     days with at least one answer in the last 7 days
class Leaderboard
  TOP_N = 10
  CACHE_FOR = 5.minutes

  Row = Struct.new(:user_id, :solved, :accuracy, :avg_seconds, :topics_completed, :active_days, keyword_init: true)

  METRICS = [
    [:solved,           "Questions solved",       :higher],
    [:accuracy,         "Accuracy",               :higher],
    [:avg_seconds,      "Avg time per question",  :lower],
    [:topics_completed, "Topics completed",       :higher],
    [:active_days,      "Active days (last 7)",   :higher]
  ].freeze

  # All students with at least one answer, best first. Cached briefly because it scans every answer.
  def self.rows
    Rails.cache.fetch(["leaderboard-v1", UserResponse.maximum(:updated_at), Question.count], expires_in: CACHE_FOR) do
      build_rows
    end
  end

  def self.build_rows
    week_start = ActiveRecord::Base.connection.quote(6.days.ago.beginning_of_day)
    tz = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)

    base = UserResponse.joins(:user).where(users: { role: User.roles[:student] })

    stats = base.group(:user_id).pluck(
      :user_id,
      Arel.sql("COUNT(DISTINCT user_responses.question_id) FILTER (WHERE user_responses.is_correct)"),
      Arel.sql("COUNT(*) FILTER (WHERE user_responses.chosen_option <> 'SKIPPED')"),
      Arel.sql("COUNT(*) FILTER (WHERE user_responses.is_correct)"),
      Arel.sql("AVG(user_responses.duration_seconds) FILTER (WHERE user_responses.chosen_option <> 'SKIPPED' AND user_responses.duration_seconds > 0)"),
      Arel.sql("COUNT(DISTINCT DATE(user_responses.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{tz})) FILTER (WHERE user_responses.created_at >= #{week_start})")
    )

    # topics completed: solved-per-topic for every student vs. questions-per-topic
    totals = Question.where.not(topic: [nil, ""]).group(:topic).count
    completed = Hash.new(0)
    base.joins(:question).where(is_correct: true)
        .group(:user_id, "questions.topic")
        .distinct.count(:question_id)
        .each { |(uid, topic), solved| completed[uid] += 1 if totals[topic].to_i.positive? && solved >= totals[topic] }

    stats.map do |uid, solved, answered, correct, avg_sec, active|
      Row.new(user_id: uid, solved: solved,
              accuracy: answered.positive? ? (correct * 100.0 / answered).round(1) : nil,
              avg_seconds: avg_sec&.to_f&.round,
              topics_completed: completed[uid], active_days: active)
    end.sort_by { |r| [-r.solved, -(r.accuracy || 0), r.user_id] }
  end

  def self.toppers = rows.first(TOP_N)

  # Average of each metric over a group of rows (nil when nobody has a value)
  def self.average(group)
    METRICS.to_h do |key, _, _|
      values = group.map(&key).compact
      [key, values.any? ? (values.sum.to_f / values.size).round(1) : nil]
    end
  end

  # Everything the "You vs Toppers" card needs for one student
  def self.comparison_for(user)
    all  = rows
    me   = all.find { |r| r.user_id == user.id } ||
           Row.new(user_id: user.id, solved: 0, accuracy: nil, avg_seconds: nil, topics_completed: 0, active_days: 0)
    rank = all.index { |r| r.user_id == user.id }

    {
      me: me,
      top: average(all.first(TOP_N)),
      platform: average(all),
      top_count: [all.size, TOP_N].min,
      students: all.size,
      rank: rank && rank + 1
    }
  end
end
