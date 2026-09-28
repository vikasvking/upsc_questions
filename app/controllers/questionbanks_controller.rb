class QuestionbanksController < ApplicationController
  ICONS = {
    "Indian Polity" => "⚖️",
    "Ancient History" => "🏺",
    "Medieval History" => "🏰",
    "Physics" => "⚛️",
    "Chemistry" => "🧪"
  }.freeze

  def show
    # 2 queries in total instead of 2 per topic
    totals = Question.where.not(topic: nil).group(:topic).order(:topic).count
    solved = Current.user.user_responses.joins(:question)
                    .where(is_correct: true)
                    .group("questions.topic")
                    .distinct
                    .count(:question_id)

    @subjects = totals.keys
    @progress_map = totals.to_h do |topic, count|
      mastered = count.positive? ? ((solved[topic].to_i * 100.0) / count).round : 0
      [topic, { mastered: mastered, icon: ICONS[topic] || "📚", count: count }]
    end
  end
end
