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
    @progress = StudentProgress.new(Current.user, exams: exam_filter)
    @topics = @progress.topic_stats
  end

  # GET /question_bank/topic?name=Physics&filter=wrong -> every question in one topic
  def topic
    @topic = params[:name].to_s
    @progress = StudentProgress.new(Current.user) # every visible question of the topic, whichever exam
    @stat = @progress.topic_stat(@topic)
    unless @stat
      redirect_to question_bank_path, alert: "Topic not found."
      return
    end

    all_questions = @progress.questions.where(topic: @topic).in_order.to_a
    @question_stats = @progress.question_stats(all_questions)
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"
    @filter_counts = FILTERS.to_h { |f| [f, all_questions.count { |q| matches_filter?(q, f) }] }
    # keep the question just answered on screen even if it no longer matches the filter
    @answered_id = flash[:answered_id].to_i
    @questions = all_questions.select { |q| matches_filter?(q, @filter) || q.id == @answered_id }
    @numbers = all_questions.each_with_index.to_h { |q, i| [q.id, i + 1] }
  end

  # POST /question_bank/answer -> practise one question on its own (not part of any test)
  def answer
    question = Question.visible_to(Current.user).find(params[:question_id])
    choice = params[:answer_choice].to_s.strip.upcase
    back = question_bank_topic_path(name: question.topic, filter: params[:filter].presence, anchor: "q-#{question.id}")

    unless Question::ANSWER_KEYS.include?(choice)
      redirect_to back, alert: "Pick an option first."
      return
    end

    correct = choice == question.correct_answer
    Current.user.user_responses.create!(
      question: question,
      chosen_option: choice,
      is_correct: correct,
      duration_seconds: params[:duration_seconds].to_i.clamp(0, 3600),
      test_session_token: nil # single-question practice, not tied to a test
    )

    flash[:answered_id] = question.id
    flash[:answered_correct] = correct
    redirect_to back
  end

  private

  # My exams by default; ?exams=all shows every exam's questions
  def exam_filter
    @all_exams = params[:exams] == "all" || Current.user.exam_codes.empty?
    @all_exams ? nil : Current.user.exam_codes
  end

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
