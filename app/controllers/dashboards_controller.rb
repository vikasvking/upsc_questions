class DashboardsController < ApplicationController
  before_action :set_global_dashboard_metrics

  def show
    if params[:topic].present?
      @topic = params[:topic]

      # 🚀 If no test session cookie matches this topic, force the confirmation page first
      if session[:active_test_topic] != @topic
        @total_q_count = Question.where(topic: @topic).count
        render :test_confirmation and return
      end

      @questions = Question.where(topic: @topic).order(Arel.sql("q_no::integer ASC"))
      current_q_no = params[:q_no].presence || 1
      @question = @questions.find_by(q_no: current_q_no) || @questions.first

      if Current.user && @question
        @previous_attempt = Current.user.user_responses.where(question: @question, test_session_token: session[:active_test_token]).last
      end

      render :quiz_arena
    else
      @streak_days = generate_streak_calendar_data
      render :show
    end
  end

  # 🚀 Starts the test tracking lifecycle
  def start_test
    topic = params[:topic]
    session[:active_test_topic] = topic
    session[:active_test_token] = SecureRandom.hex(8) # Unique token separating this mock attempt
    session[:test_start_time] = Time.current.to_i

    redirect_to dashboard_path(topic: topic)
  end

  def submit_answer
    @question = Question.find(params[:question_id])
    chosen = params[:answer_choice]

    if chosen.blank?
      redirect_to dashboard_path(topic: @question.topic, q_no: @question.q_no), alert: "Please select an option before submitting."
      return
    end

    correct_check = (chosen.strip.upcase == @question.correct_answer.strip.upcase)

    Current.user.user_responses.create!(
      question: @question,
      chosen_option: chosen,
      is_correct: correct_check,
      duration_seconds: params[:duration_seconds].to_i,
      test_session_token: session[:active_test_token] # Link to current attempt session
    )

    flash[:chosen_answer] = chosen
    flash[:is_correct_flag] = correct_check
    flash[:explanation_text] = @question.explanation

    next_q = Question.where(topic: @question.topic)
                     .where("q_no::integer > ?", @question.q_no.to_i)
                     .order(Arel.sql("q_no::integer ASC"))
                     .first

    if next_q
      redirect_to dashboard_path(topic: @question.topic, q_no: next_q.q_no)
    else
      redirect_to finish_test_dashboard_path(question_id: @question.id), data: { turbo_method: :post }
    end
  end

  def skip_question
    @question = Question.find(params[:question_id])

    Current.user.user_responses.create!(
      question: @question,
      chosen_option: "SKIPPED",
      is_correct: false,
      duration_seconds: params[:duration_seconds].to_i,
      test_session_token: session[:active_test_token]
    )

    next_q = Question.where(topic: @question.topic)
                     .where("q_no::integer > ?", @question.q_no.to_i)
                     .order(Arel.sql("q_no::integer ASC"))
                     .first

    if next_q
      redirect_to dashboard_path(topic: @question.topic, q_no: next_q.q_no)
    else
      redirect_to finish_test_dashboard_path(question_id: @question.id), data: { turbo_method: :post }
    end
  end

  # 🚀 Finishes the test session and tears down cookies
  def finish_test
    completed_topic = session[:active_test_topic]
    completed_token = session[:active_test_token]

    # Terminate the active session tracking locks
    session[:active_test_topic] = nil
    session[:active_test_token] = nil
    session[:test_start_time] = nil

    redirect_to test_results_dashboard_path(topic: completed_topic, token: completed_token), notice: "Test evaluation complete."
  end

  # 🚀 Compiles full correct answers matrix for the finished session
  def results
  @topic = params[:topic]
  @token = params[:token]

  @questions = Question.where(topic: @topic).order(Arel.sql("q_no::integer ASC"))

  # 🚀 FIX: Convert index_by symbol mapping into a standard execution block
  @responses = Current.user.user_responses.where(test_session_token: @token).index_by { |resp| resp.question_id }

  # Score calculation parameters
  total_attempts = @responses.values.count
  @correct_count = @responses.values.select(&:is_correct).count
  @wrong_count = total_attempts - @correct_count
end


  private

  # ... retain generate_streak_calendar_data and calculate_active_streak exactly intact ...
  def generate_streak_calendar_data
    return [] unless Current.user
    (0..6).to_a.reverse.map do |day_offset|
      target_date = Date.current - day_offset
      solved_count = Current.user.user_responses.where(created_at: target_date.all_day).count
      { date: target_date, day_name: target_date.strftime("%a"), day_number: target_date.day, solved_count: solved_count, target_fulfilled: solved_count >= 25, is_today: target_date == Date.current }
    end
  end

  def calculate_active_streak
    return 0 unless Current.user
    streak = 0
    check_date = Date.current
    loop do
      count = Current.user.user_responses.where(created_at: check_date.all_day).count
      if count >= 25
        streak += 1
        check_date -= 1.day
      else
        if check_date == Date.current
          yesterday_count = Current.user.user_responses.where(created_at: (Date.current - 1.day).all_day).count
          if yesterday_count >= 25
            check_date -= 1.day
            next
          end
        end
        break
      end
    end
    streak
  end

  def set_global_dashboard_metrics
    @subjects = Question.pluck(:topic).uniq.compact
    @progress_map = {}
    @current_streak_count = calculate_active_streak

    if Current.user
      total_platform_questions = Question.count
      @lifetime_correct_count = Current.user.user_responses.where(is_correct: true).distinct.count(:question_id)
      @lifetime_wrong_count = Current.user.user_responses.where(is_correct: false).where.not(chosen_option: "SKIPPED").distinct.count(:question_id)
      unique_attempted_questions = Current.user.user_responses.distinct.count(:question_id)
      @overall_completion_pct = total_platform_questions > 0 ? ((unique_attempted_questions.to_f / total_platform_questions) * 100).round : 0
      total_validated_attempts = Current.user.user_responses.where.not(chosen_option: "SKIPPED").count
      @global_accuracy_pct = total_validated_attempts > 0 ? ((Current.user.user_responses.where(is_correct: true).count.to_f / total_validated_attempts) * 100).round(1) : 0.0
    end

    @subjects.each do |topic_name|
      total_q = Question.where(topic: topic_name).count
      if total_q > 0 && Current.user
        correct_count = Current.user.user_responses.joins(:question).where(questions: { topic: topic_name }, is_correct: true).distinct.count(:question_id)
        mastery = ((correct_count.to_f / total_q) * 100).round
      else
        mastery = 0
      end
      icon_map = { "Indian Polity" => "⚖️", "Ancient History" => "🏺", "Medieval History" => "🏰" }
      @progress_map[topic_name] = { mastered: mastery, icon: icon_map[topic_name] || "📚", count: total_q }
    end
  end
end
