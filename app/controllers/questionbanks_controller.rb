class QuestionbanksController < ApplicationController
  ICONS = {
    "Indian Polity" => "⚖️",
    "Ancient History" => "🏺",
    "Medieval History" => "🏰",
    "Physics" => "⚛️",
    "Chemistry" => "🧪"
  }.freeze

  FILTERS = %w[all solved wrong not_attempted].freeze

  helper_method :topic_icon

  # GET /question_bank -> every topic with this student's progress
  def show
    @progress = StudentProgress.new(Current.user)
    @topics = @progress.topic_stats
  end

  # GET /question_bank/topic?name=Physics&filter=wrong -> every question in one topic
  def topic
    @topic = params[:name].to_s
    @progress = StudentProgress.new(Current.user)
    @stat = @progress.topic_stat(@topic)
    unless @stat
      redirect_to question_bank_path, alert: "Topic not found."
      return
    end

    all_questions = Question.where(topic: @topic).in_order.to_a
    @question_stats = @progress.question_stats(all_questions)
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"
    @filter_counts = FILTERS.to_h { |f| [f, all_questions.count { |q| matches_filter?(q, f) }] }
    @questions = all_questions.select { |q| matches_filter?(q, @filter) }
    @numbers = all_questions.each_with_index.to_h { |q, i| [q.id, i + 1] }
  end

  private

  def topic_icon(topic)
    ICONS[topic] || "📚"
  end

  def matches_filter?(question, filter)
    s = @question_stats[question.id]
    case filter
    when "solved"        then s.solved?
    when "wrong"         then s.attempted? && !s.solved?
    when "not_attempted" then !s.attempted?
    else true
    end
  end
end
