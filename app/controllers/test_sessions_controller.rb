class TestSessionsController < ApplicationController
  # Protect the controller space via custom role filters
  before_action :ensure_faculty_access, only: [:new, :create]

  def index
    if Current.user.teacher? || Current.user.admin?
      @test_sessions = Current.user.test_sessions.order(created_at: :desc)
      render :teacher_index
    else
      redirect_to join_test_sessions_path
    end
  end
  # 🚀 NEW METHOD: Computes high-yield group metrics and isolates the classroom topper profile
def show
  @test_session = TestSession.find(params[:id])
  unless Current.user.teacher? || Current.user.admin? || @test_session.user_id == Current.user.id
    redirect_to dashboard_path, alert: "Access Denied."
    return
  end

  # Fetch all user responses logged under this specific test session token identifier matrix
  # Group responses by user_id to evaluate student sheets independently
  all_session_responses = UserResponse.joins(:question)
                                         .where(question_id: @test_session.question_ids)
                                         .to_a
                                         .group_by { |resp| resp.user_id }

  @total_participants = all_session_responses.keys.count
  @student_performance_list = []

  highest_score = -1
  @topper_email = "No attempts logged yet"

  all_session_responses.each do |user_id, responses|
    student = User.find_by(id: user_id)
    next unless student

    total_questions_in_paper = @test_session.questions.count
    correct_answers_count = responses.select(&:is_correct).count

    # Compute precise percentage metrics for each participant sheet
    score_percentage = total_questions_in_paper > 0 ? ((correct_answers_count.to_f / total_questions_in_paper) * 100).round(1) : 0.0
    is_passed_check = score_percentage >= @test_session.pass_mark_percentage

    # 🚀 TOPPER DETECTOR: Track and isolate the absolute maximum mark holder profile string
    if score_percentage > highest_score
      highest_score = score_percentage
      @topper_email = "#{student.email_address} (#{score_percentage}%) 🔥"
    elsif score_percentage == highest_score && highest_score > 0
      @topper_email += ", #{student.email_address} (#{score_percentage}%) 🔥" # Handle joint toppers safely
    end

    @student_performance_list << {
      email: student.email_address,
      correct: correct_answers_count,
      total: total_questions_in_paper,
      percentage: score_percentage,
      passed: is_passed_check
    }
  end

  # Calculate global class average score percentage parameters safely
  if @total_participants > 0
    total_combined_pct = @student_performance_list.map { |s| s[:percentage] }.sum
    @class_average_pct = (total_combined_pct / @total_participants).round(1)
  else
    @class_average_pct = 0.0
  end

  # Sort students from highest score down to lowest score
  @student_performance_list.sort_by! { |s| -s[:percentage] }
end

  def new
    @test_session = TestSession.new
    # 🚀 FIX: Correctly maps and isolates the Arel order parameter chain without syntax clutter
    @questions = Question.order(exam_type: :asc, topic: :asc).order(Arel.sql("q_no::integer ASC"))
  end

  def create
    @test_session = Current.user.test_sessions.new(test_session_params)
    selected_ids = params[:selected_question_ids]

    if selected_ids.blank?
      @questions = Question.order(exam_type: :asc, topic: :asc).order(Arel.sql("q_no::integer ASC"))
      flash.now[:alert] = "Selection Error: Please pick at least one question checkbox from the repository list below."
      render :new, status: :unprocessable_entity
      return
    end

    if @test_session.save
      # Bind each explicitly hand-picked question to the newly generated custom exam session
      selected_ids.each do |q_id|
        TestQuestion.create!(test_session: @test_session, question_id: q_id)
      end
      redirect_to test_sessions_path, notice: "Custom test compiled successfully! Distribute PIN: #{@test_session.pin_code}"
    else
      @questions = Question.order(exam_type: :asc, topic: :asc).order(Arel.sql("q_no::integer ASC"))
      render :new, status: :unprocessable_entity
    end
  end

  def join_form
    # Renders the clean student PIN entry passcode window
  end

  def verify_pin
    match = TestSession.find_by(pin_code: params[:pin_code].to_s.strip.upcase)

    if match && match.questions.any?
      # Dynamically redirects the student into your main quiz workspace arena
      redirect_to dashboard_path(topic: match.questions.first.topic, active_custom_test_id: match.id), notice: "Access Granted: Entering #{match.title}."
    else
      redirect_to join_test_sessions_path, alert: "Invalid examination code PIN. Please verify with your instructor."
    end
  end

  private

  def test_session_params
    params.require(:test_session).permit(:title, :exam_type, :duration_minutes, :pass_mark_percentage)
  end

  def ensure_faculty_access
    unless Current.user&.teacher? || Current.user&.admin?
      redirect_to dashboard_path, alert: "Access Denied: Only faculty can compile bespoke exam papers."
    end
  end
end
