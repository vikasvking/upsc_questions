class TestSessionsController < ApplicationController
  FACULTY_ACTIONS = [:index, :new, :create, :show, :edit, :update, :upload_form, :import, :download_template].freeze

  before_action :ensure_faculty_access, only: FACULTY_ACTIONS - [:index]
  before_action :set_test_session, only: [:show, :edit, :update]
  before_action :ensure_test_ownership, only: [:show, :edit, :update]
  before_action :load_question_library, only: [:new, :edit]

  rate_limit to: 10, within: 5.minutes, only: :verify_pin,
             with: -> { redirect_to join_test_sessions_path, alert: "Too many attempts. Try again in a few minutes." }

  def index
    unless Current.user.faculty?
      redirect_to join_test_sessions_path
      return
    end

    scope = Current.user.admin? ? TestSession.all : Current.user.test_sessions
    @test_sessions = scope.includes(:user).newest_first
    @question_counts = TestQuestion.where(test_session_id: @test_sessions.map(&:id)).group(:test_session_id).count
    render :teacher_index
  end

  # Results for one test: one row per student attempt
  def show
    attempts = @test_session.test_attempts.includes(:user).to_a
    attempts.select(&:expired?).each(&:finish!)

    @in_progress_count = attempts.count { |a| !a.finished? }

    @student_performance_list = attempts.select(&:finished?).map do |attempt|
      s = attempt.score_summary
      { email: attempt.user.email_address, correct: s[:correct], total: s[:total],
        percentage: s[:percentage], passed: s[:passed], submitted_at: attempt.finished_at }
    end.sort_by { |row| -row[:percentage] }

    @total_participants = @student_performance_list.size
    @class_average_pct =
      @total_participants.positive? ? (@student_performance_list.sum { |r| r[:percentage] } / @total_participants).round(1) : 0.0

    top = @student_performance_list.first
    @topper_email =
      if top && top[:percentage].positive?
        @student_performance_list.select { |r| r[:percentage] == top[:percentage] }
                                 .map { |r| "#{r[:email]} (#{r[:percentage]}%)" }.join(", ")
      else
        "No submissions yet"
      end
  end

  def new
    @test_session = TestSession.new(duration_minutes: 45, pass_mark_percentage: 40, access_type: "pin")
  end

  def create
    @test_session = Current.user.test_sessions.new(test_session_params)
    selected_ids = Array(params.dig(:test_session, :question_ids)).compact_blank

    if selected_ids.empty?
      load_question_library
      flash.now[:alert] = "Pick at least one question for this test."
      render :new, status: :unprocessable_entity
      return
    end

    if @test_session.save
      message = @test_session.open_access? ? "Test created. It is open to all students." : "Test created. Share PIN: #{@test_session.pin_code}"
      redirect_to test_sessions_path, notice: message
    else
      load_question_library
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if Array(params.dig(:test_session, :question_ids)).compact_blank.empty?
      load_question_library
      flash.now[:alert] = "A test cannot be left empty. Keep at least one question."
      render :edit, status: :unprocessable_entity
      return
    end

    if @test_session.update(test_session_params)
      redirect_to test_sessions_path, notice: "Test updated."
    else
      load_question_library
      render :edit, status: :unprocessable_entity
    end
  end

  def upload_form
  end

  def import
    file = params[:file]
    if file.blank? || !file.original_filename.downcase.end_with?(".xls")
      redirect_to upload_form_test_sessions_path, alert: "Please upload the .xls template downloaded from this page."
      return
    end

    begin
      TestSession.import_from_excel(file.path, Current.user.id)
      redirect_to test_sessions_path, notice: "Test and questions imported."
    rescue StandardError => e
      redirect_to upload_form_test_sessions_path, alert: "Could not import the file: #{e.message}"
    end
  end

  def download_template
    xls_content = [
      ["Test Title", "Exam Portfolio", "Duration Minutes", "Passing Percentage", "Exam Year", "Access (Open/PIN)", "Starts At", "Ends At"],
      ["Surprise Physics Quiz", "CBSE", "45", "40", "2026", "PIN", "2026-10-05 10:00", "2026-10-05 18:00"],
      [],
      ["Q.No", "Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer", "Explanation"],
      ["1", "Physics", "What is the formula of Acceleration?", "MA", "MV", "v/t", "MV2", "C", "Acceleration = Velocity / Time."]
    ].map { |row| row.join("\t") }.join("\n")

    send_data xls_content, filename: "bulk_test_creation_template.xls", type: "application/vnd.ms-excel; charset=utf-8"
  end

  def join_form
  end

  def verify_pin
    match = TestSession.find_by(pin_code: params[:pin_code].to_s.strip.upcase)

    if match && match.questions.exists?
      session[:unlocked_test_ids] = (Array(session[:unlocked_test_ids]) | [match.id]).last(50)
      redirect_to test_intro_dashboard_path(match), notice: "PIN accepted: #{match.title}"
    else
      redirect_to join_test_sessions_path, alert: "Invalid PIN. Please check it with your teacher."
    end
  end

  private

  def set_test_session
    @test_session = TestSession.find(params[:id])
  end

  def load_question_library
    @questions = Question.in_order
  end

  def ensure_test_ownership
    unless @test_session.user_id == Current.user.id || Current.user.admin?
      redirect_to test_sessions_path, alert: "You can only open tests you created."
    end
  end

  def ensure_faculty_access
    unless Current.user&.faculty?
      redirect_to dashboard_path, alert: "Only teachers and admins can manage tests."
    end
  end

  def test_session_params
    params.require(:test_session).permit(:title, :exam_type, :duration_minutes, :pass_mark_percentage,
                                         :access_type, :starts_at, :ends_at, question_ids: [])
  end
end
