class QuestionbanksController < ApplicationController
  def show
    # Pluck all unique topics currently loaded into your Question database table
    @subjects = Question.pluck(:topic).uniq.compact

    # Calculate user progress matrices dynamically using real response rows
    @progress_map = {}

    @subjects.each do |topic_name|
      total_questions_in_topic = Question.where(topic: topic_name).count

      if total_questions_in_topic > 0 && Current.user
        # Count unique questions in this specific topic that the current user has answered correctly at least once
        correctly_solved_unique_count = Current.user.user_responses
                                                 .joins(:question)
                                                 .where(questions: { topic: topic_name }, is_correct: true)
                                                 .distinct
                                                 .count(:question_id)

        mastery_percentage = ((correctly_solved_unique_count.to_f / total_questions_in_topic) * 100).round
      else
        mastery_percentage = 0
      end

      # Dynamic icon mapping matching your Burgundy design themes
      icon_map = { "Indian Polity" => "⚖️", "Ancient History" => "🏺", "Medieval History" => "🏰" }

      @progress_map[topic_name] = {
        mastered: mastery_percentage,
        icon: icon_map[topic_name] || "📚",
        count: total_questions_in_topic
      }
    end
  end
end
