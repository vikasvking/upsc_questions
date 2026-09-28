# app/models/leaderboard.rb
# Ranks students across the whole platform. Only student accounts are counted.
#
# Rank score (higher is better) — rewards solving questions, in few tries, quickly:
#   for every question a student has solved:
#     points by the try on which it was first answered correctly: 1st try 10, 2nd try 6, 3rd or later 3
#     + speed bonus up to 2: full at 30 s or less, falling to 0 at 120 s or more
#       (time spent on that first correct answer; unknown time gets no bonus)
#   Ties: higher accuracy, then more questions solved.
#   "Top 10" = the 10 highest rank scores.
#
# Other metrics shown for comparison
#   solved           questions answered correctly at least once
#   accuracy         correct answers / all answers (skips excluded), in %
#   avg_tries        average tries needed per solved question (lower is better)
#   avg_seconds      average time spent per answered question
#   topics_completed topics where every question is solved
#   active_days      days with at least one answer in the last 7 days
class Leaderboard
  TOP_N = 10
  CACHE_FOR = 5.minutes

  POINTS_BY_TRY = { 1 => 10, 2 => 6 }.freeze
  POINTS_LATER_TRY = 3
  SPEED_BONUS_MAX = 2.0
  FAST_SECONDS = 30
  SLOW_SECONDS = 120

  Row = Struct.new(:user_id, :score, :solved, :accuracy, :avg_tries, :avg_seconds, :topics_completed, :active_days, keyword_init: true)

  METRICS = [
    [:score,            "Rank score",             :higher],
    [:solved,           "Questions solved",       :higher],
    [:avg_tries,        "Tries per solved Q",     :lower],
    [:accuracy,         "Accuracy",               :higher],
    [:avg_seconds,      "Avg time per question",  :lower],
    [:topics_completed, "Topics completed",       :higher],
    [:active_days,      "Active days (last 7)",   :higher]
  ].freeze

  # Points for one solved question
  def self.points_for(try_number, seconds)
    base = POINTS_BY_TRY.fetch(try_number, POINTS_LATER_TRY)
    bonus =
      if seconds.to_i <= 0 then 0.0
      elsif seconds <= FAST_SECONDS then SPEED_BONUS_MAX
      elsif seconds >= SLOW_SECONDS then 0.0
      else SPEED_BONUS_MAX * (SLOW_SECONDS - seconds) / (SLOW_SECONDS - FAST_SECONDS)
      end
    base + bonus
  end

  # All students with at least one answer, best first. Cached briefly because it scans every answer.
  def self.rows
    Rails.cache.fetch(["leaderboard-v2", UserResponse.maximum(:updated_at), Question.count], expires_in: CACHE_FOR) do
      build_rows
    end
  end

  def self.build_rows
    conn = ActiveRecord::Base.connection
    week_start = conn.quote(6.days.ago.beginning_of_day)
    tz = conn.quote(Time.zone.tzinfo.name)
    student = User.roles[:student].to_i

    base = UserResponse.joins(:user).where(users: { role: student })

    stats = base.group(:user_id).pluck(
      :user_id,
      Arel.sql("COUNT(DISTINCT user_responses.question_id) FILTER (WHERE user_responses.is_correct)"),
      Arel.sql("COUNT(*) FILTER (WHERE user_responses.chosen_option <> 'SKIPPED')"),
      Arel.sql("COUNT(*) FILTER (WHERE user_responses.is_correct)"),
      Arel.sql("AVG(user_responses.duration_seconds) FILTER (WHERE user_responses.chosen_option <> 'SKIPPED' AND user_responses.duration_seconds > 0)"),
      Arel.sql("COUNT(DISTINCT DATE(user_responses.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{tz})) FILTER (WHERE user_responses.created_at >= #{week_start})")
    )

    # For every solved question: on which try was it first answered correctly, and how long did that answer take?
    first_correct = conn.select_rows(<<~SQL)
      SELECT user_id, try_number, duration_seconds FROM (
        SELECT ur.user_id, ur.is_correct, ur.duration_seconds,
               ROW_NUMBER() OVER (PARTITION BY ur.user_id, ur.question_id ORDER BY ur.created_at, ur.id) AS try_number,
               ROW_NUMBER() OVER (PARTITION BY ur.user_id, ur.question_id, ur.is_correct ORDER BY ur.created_at, ur.id) AS nth_of_kind
        FROM user_responses ur
        JOIN users u ON u.id = ur.user_id
        WHERE u.role = #{student} AND ur.chosen_option <> 'SKIPPED'
      ) tries
      WHERE is_correct AND nth_of_kind = 1
    SQL

    score = Hash.new(0.0)
    tries = Hash.new { |h, k| h[k] = [] }
    first_correct.each do |uid, try_number, secs|
      uid = uid.to_i
      score[uid] += points_for(try_number.to_i, secs.to_i)
      tries[uid] << try_number.to_i
    end

    # topics completed: solved-per-topic for every student vs. questions-per-topic
    totals = Question.where.not(topic: [nil, ""]).group(:topic).count
    completed = Hash.new(0)
    base.joins(:question).where(is_correct: true)
        .group(:user_id, "questions.topic")
        .distinct.count(:question_id)
        .each { |(uid, topic), solved| completed[uid] += 1 if totals[topic].to_i.positive? && solved >= totals[topic] }

    stats.map do |uid, solved, answered, correct, avg_sec, active|
      t = tries[uid]
      Row.new(user_id: uid, score: score[uid].round(1), solved: solved,
              accuracy: answered.positive? ? (correct * 100.0 / answered).round(1) : nil,
              avg_tries: t.any? ? (t.sum.to_f / t.size).round(2) : nil,
              avg_seconds: avg_sec&.to_f&.round,
              topics_completed: completed[uid], active_days: active)
    end.sort_by { |r| [-r.score, -(r.accuracy || 0), -r.solved, r.user_id] }
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
           Row.new(user_id: user.id, score: 0.0, solved: 0, accuracy: nil, avg_tries: nil, avg_seconds: nil, topics_completed: 0, active_days: 0)
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
