class DashboardsController < ApplicationController
  # Runs the global metrics summary computations before handling any active dashboard requests
  before_action :set_global_dashboard_metrics

  def show
    if params[:topic].present?
      @topic = params[:topic]

      # Enforce pre-test instruction validation constraints if the user session hasn't initialized the quiz
      if session[:active_test_topic] != @topic
        @total_q_count = Question.where(topic: @topic).count
        render :test_confirmation and return
      end

      # Load up all questions inside this topic explicitly typecasted via native PostgreSQL integers
      @questions = Question.where(topic: @topic).order(Arel.sql("q_no::integer ASC"))
      current_q_no = params[:q_no].presence || 1
      @question = @questions.find_by(q_no: current_q_no) || @questions.first

      # Securely check if the user has already loaded a choice response map inside this isolated testing block
      if Current.user && @question
        @previous_attempt = Current.user.user_responses.where(question: @question, test_session_token: session[:active_test_token]).last
      end

      render :quiz_arena
    else
      # Mode B: Standard Main Dashboard Selection View Panel Hub
      @streak_days = generate_streak_calendar_data
      render :show
    end
  end

  # Initializes session tokens and tracking timestamps
  def start_test
    topic = params[:topic]
    session[:active_test_topic] = topic
    session[:active_test_token] = SecureRandom.hex(8)
    session[:test_start_time] = Time.current.to_i

    redirect_to dashboard_path(topic: topic)
  end

  # Receives multiple choice options input, checks validity, and appends rows to user response records
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
      test_session_token: session[:active_test_token]
    )

    flash[:chosen_answer] = chosen
    flash[:is_correct_flag] = correct_check
    flash[:explanation_text] = @question.explanation

    # Dynamic sequential next lookups leveraging PostgreSQL cast operations
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

  # Saves a custom "SKIPPED" flag entry parameter to help your dynamic AI model track avoided modules
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

  # Finalizes exam execution and tears down active session state cookie logs
  def finish_test
    completed_topic = session[:active_test_topic]
    completed_token = session[:active_test_token]

    session[:active_test_topic] = nil
    session[:active_test_token] = nil
    session[:test_start_time] = nil

    redirect_to test_results_dashboard_path(topic: completed_topic, token: completed_token), notice: "Test evaluation complete."
  end

  # Pulls the complete evaluation worksheet history matrix mapping onto blocks
  def results
    @topic = params[:topic]
    @token = params[:token]

    @questions = Question.where(topic: @topic).order(Arel.sql("q_no::integer ASC"))
    @responses = Current.user.user_responses.where(test_session_token: @token).index_by { |resp| resp.question_id }

    total_attempts = @responses.values.count
    @correct_count = @responses.values.select(&:is_correct).count
    @wrong_count = total_attempts - @correct_count
  end

  private

  # Compiles chronological response counts over a 7-day row history mapping matrix
  def generate_streak_calendar_data
    return [] unless Current.user

    (0..6).to_a.reverse.map do |day_offset|
      target_date = Date.current - day_offset
      solved_count = Current.user.user_responses.where(created_at: target_date.all_day).count

      {
        date: target_date,
        day_name: target_date.strftime("%a"),
        day_number: target_date.day,
        solved_count: solved_count,
        target_fulfilled: solved_count >= 25, # Enforces your strict 25-Question threshold target
        is_today: target_date == Date.current
      }
    end
  end

  # Dynamically iterates backwards across logs to quantify accurate consecutive target fulfillment totals
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

  # Gathers global analytical profile metrics used on top information panels
  def set_global_dashboard_metrics
    @current_streak_count = calculate_active_streak

    if Current.user
      total_platform_questions = Question.count

      @lifetime_correct_count = Current.user.user_responses.where(is_correct: true).distinct.count(:question_id)
      @lifetime_wrong_count = Current.user.user_responses.where(is_correct: false).where.not(chosen_option: "SKIPPED").distinct.count(:question_id)
      unique_attempted_questions = Current.user.user_responses.distinct.count(:question_id)

      @overall_completion_pct = total_platform_questions > 0 ? ((unique_attempted_questions.to_f / total_platform_questions) * 100).round : 0

      total_validated_attempts = Current.user.user_responses.where.not(chosen_option: "SKIPPED").count
      @global_accuracy_pct = total_validated_attempts > 0 ? ((Current.user.user_responses.where(is_correct: true).count.to_f / total_validated_attempts) * 100).round(1) : 0.0
    else
      @lifetime_correct_count = 0
      @lifetime_wrong_count = 0
      @overall_completion_pct = 0
      @global_accuracy_pct = 0.0
    end
  end
end
