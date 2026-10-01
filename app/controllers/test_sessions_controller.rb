class TestSessionsController < ApplicationController
  include AudienceAssignment
  include ExamListing
  FACULTY_ACTIONS = [:index, :new, :create, :show, :edit, :update, :reinstate, :live, :export, :report, :upload_form, :import, :download_template].freeze
  ONLINE_WITHIN = TestSession::ONLINE_WITHIN # two missed heartbeats = "no signal"
  LiveRow = TestSession::LiveRow

  before_action :ensure_faculty_access, only: FACULTY_ACTIONS - [:index]
  before_action :set_test_session, only: [:show, :edit, :update, :reinstate, :live, :export, :report]
  before_action :ensure_test_ownership, only: [:show, :edit, :update, :reinstate, :live, :export, :report]
  before_action :ensure_editable, only: [:edit, :update]

  rate_limit to: 10, within: 5.minutes, only: :verify_pin,
             with: -> { redirect_to join_test_sessions_path, alert: "Too many attempts. Try again in a few minutes." }

  def index
    unless Current.user.faculty?
      redirect_to join_test_sessions_path
      return
    end

    scope = Current.user.admin? ? TestSession.all : Current.user.test_sessions
    @exam = remembered_exam(:my_tests)
    @exam_counts = exam_counts(scope)
    scope = scope.where(exam_type: @exam) if @exam
    @test_sessions = paginate(scope.includes(:user, :institution, :audience_grants).newest_first)
    @question_counts = TestQuestion.where(test_session_id: @test_sessions.map(&:id)).group(:test_session_id).count
    render :teacher_index
  end

  # Results for one test: one row per student attempt
  # Results for one test, ranked by marks then time
  def show
    @results = @test_session.rankings
    @test_session.block_silent_students!
    @blocked_attempts = @test_session.test_attempts.blocked.includes(:user).order(:blocked_at)
    @in_progress_count = @test_session.test_attempts.first_tries.in_progress.not_blocked.count
    @total_participants = @results.size
    @class_average_marks = @results.any? ? (@results.sum(&:marks) / @results.size).round(2) : 0.0
    @class_average_pct = @results.any? ? (@results.sum(&:percentage) / @results.size).round(1) : 0.0
    toppers = @results.select { |r| r.rank == 1 && r.marks.positive? }
    @topper_email = toppers.any? ? toppers.map { |r| "#{r.user.display_name} (#{r.marks} marks)" }.join(", ") : "No submissions yet"
    @rating_summary = Rating.summary_for(@test_session)
    @rating_comments = @test_session.ratings.with_visible_comment.includes(:user).newest_first.limit(20)
    @question_stats = @test_session.question_analysis
    @topic_stats = @test_session.topic_analysis(@question_stats)
  end

  # GET /test_sessions/:id/export -> the results as a CSV file for Excel
  def export
    csv = TestResultsCsv.new(@test_session)
    send_data csv.to_s, filename: csv.filename, type: "text/csv; charset=utf-8"
  end

  # GET /test_sessions/:id/report -> a printable report (Print, or Save as PDF from the print dialog)
  def report
    @results = @test_session.rankings
    @question_stats = @test_session.question_analysis
    @topic_stats = @test_session.topic_analysis(@question_stats)
    @blocked_count = @test_session.test_attempts.first_tries.blocked.count
    render layout: false
  end

  def new
    @test_session = TestSession.new(duration_minutes: 45, pass_mark_percentage: 40, access_type: "pin")
  end

  def create
    @test_session = Current.user.test_sessions.new(test_session_params)
    selected_ids = Array(params.dig(:test_session, :question_ids)).compact_blank

    if selected_ids.empty?
      flash.now[:alert] = "Pick at least one question for this test."
      render :new, status: :unprocessable_entity
      return
    end

    if audience_valid?(@test_session) && @test_session.save
      apply_audience!(@test_session)
      message = @test_session.open_access? ? "Test created (#{@test_session.audience_label.downcase})." : "Test created. Share PIN: #{@test_session.pin_code}"
      redirect_to test_sessions_path, notice: message
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if Array(params.dig(:test_session, :question_ids)).compact_blank.empty?
      flash.now[:alert] = "A test cannot be left empty. Keep at least one question."
      render :edit, status: :unprocessable_entity
      return
    end

    @test_session.assign_attributes(test_session_params)
    if audience_valid?(@test_session) && @test_session.save
      apply_audience!(@test_session)
      redirect_to test_sessions_path, notice: "Test updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /test_sessions/:id/reinstate  attempt_id=...
  def reinstate
    attempt = @test_session.test_attempts.find(params[:attempt_id])
    if attempt.reinstate!
      redirect_to test_session_path(@test_session), notice: "#{attempt.user.display_name} can continue the test."
    else
      redirect_to test_session_path(@test_session), alert: "That student is not blocked."
    end
  end

  # GET /test_sessions/:id/live -> the live panel (a Turbo frame the Results page reloads every 15 s)
  # (shared between teachers for a few seconds, see TestSession#live_snapshot)
  def live
    snapshot = @test_session.live_snapshot
    @live_rows       = snapshot.rows
    @not_started     = snapshot.not_started
    @counts          = snapshot.counts
    @total_questions = snapshot.total_questions
    @refreshed_at    = snapshot.refreshed_at
    render layout: false
  end

  def upload_form
  end

  def import
    file = params[:file]
    if file.blank? || !file.original_filename.downcase.end_with?(".xls", ".xlsx")
      redirect_to upload_form_test_sessions_path, alert: "Please upload an Excel file (.xlsx) or the .xls template from this page."
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
      ["Surprise Physics Quiz", "CBSE X", "45", "40", "2026", "PIN", "2026-10-05 10:00", "2026-10-05 18:00"],
      [],
      ["Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer", "Explanation"],
      ["Physics", "What is the formula of Acceleration?", "MA", "MV", "v/t", "MV2", "C", "Acceleration = Velocity / Time."]
    ].map { |row| row.join("\t") }.join("\n")

    send_data xls_content, filename: "rankwise_test_template.xls", type: "application/vnd.ms-excel; charset=utf-8"
  end

  def join_form
  end

  def verify_pin
    match = TestSession.available_to(Current.user).find_by(pin_code: params[:pin_code].to_s.strip.upcase)

    if match && match.questions.exists?
      session[:unlocked_test_ids] = (Array(session[:unlocked_test_ids]) | [match.id]).last(50)
      # so the teacher's live panel can list students who entered the PIN but have not started
      TestPinEntry.create_or_find_by!(test_session: match, user: Current.user) if Current.user.student?
      redirect_to test_intro_dashboard_path(match), notice: "PIN accepted: #{match.title}"
    elsif !match && (locked = TestSession.visible_to(Current.user).find_by(pin_code: params[:pin_code].to_s.strip.upcase))
      # right PIN, but the test is outside the student's tier -> its page with the upgrade options
      redirect_to test_intro_dashboard_path(locked)
    else
      redirect_to join_test_sessions_path, alert: "Invalid PIN. Please check it with your teacher."
    end
  end

  private

  def set_test_session
    @test_session = TestSession.find(params[:id])
  end

  def ensure_test_ownership
    unless @test_session.user_id == Current.user.id || Current.user.admin?
      redirect_to test_sessions_path, alert: "You can only open tests you created."
    end
  end

  # Strict and time-bound tests lock 10 minutes before they open (see TestSession#editing_locked?)
  def ensure_editable
    return unless @test_session.editing_locked?

    redirect_to test_sessions_path,
                alert: "“#{@test_session.title}” can no longer be edited: tests with a time window or strict mode lock " \
                       "#{TestSession::EDIT_LOCK_BEFORE.in_minutes.to_i} minutes before they open, once a student has started, and after they close."
  end

  def ensure_faculty_access
    unless Current.user&.faculty?
      redirect_to dashboard_path, alert: "Only teachers and admins can manage tests."
    end
  end

  # The question picker (test form) loads its library from QuestionLibrariesController, 50 at a time
  def test_session_params
    permitted = params.require(:test_session).permit(:title, :exam_type, :duration_minutes, :pass_mark_percentage,
                                                     :access_type, :starts_at, :ends_at, :strict_mode, :visibility, :institution_id, question_ids: [])
    permitted[:question_ids] = permitted[:question_ids].compact_blank.uniq if permitted[:question_ids] # a question once per test
    permitted
  end
end
