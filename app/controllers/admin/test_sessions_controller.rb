# Admins can create, change and delete any test, including locked strict or scheduled tests
# when a teacher asks. Changing a locked test needs a written reason, kept in the admin log.
class Admin::TestSessionsController < Admin::BaseController
  KINDS = %w[open pin strict scheduled].freeze

  before_action :set_test_session, only: [:edit, :update, :destroy]
  before_action :load_form_data, only: [:new, :edit]

  def index
    scope = TestSession.includes(:user).newest_first
    @exam    = Exam.normalize(params[:exam])
    @kind    = params[:kind].presence_in(KINDS)
    @teacher = params[:teacher].presence
    scope = scope.where(exam_type: @exam) if @exam
    scope = scope.where("title ILIKE ?", "%#{TestSession.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?
    scope = @teacher == "none" ? scope.where(user_id: nil) : scope.where(user_id: @teacher) if @teacher
    scope =
      case @kind
      when "strict"    then scope.where(strict_mode: true)
      when "pin"       then scope.where(access_type: "pin", strict_mode: false)
      when "open"      then scope.where(access_type: "open")
      when "scheduled" then scope.where("starts_at IS NOT NULL OR ends_at IS NOT NULL")
      else scope
      end

    @teachers = User.where(id: TestSession.select(:user_id)).order(:email_address)
    @tests = paginate(scope)
    ids = @tests.map(&:id)
    @question_counts = TestQuestion.where(test_session_id: ids).group(:test_session_id).count
    @attempt_counts  = TestAttempt.where(test_session_id: ids).group(:test_session_id).count
    @blocked_counts  = TestAttempt.blocked.in_progress.where(test_session_id: ids).group(:test_session_id).count
  end

  def new
    @test_session = TestSession.new(duration_minutes: 45, pass_mark_percentage: 40, access_type: "pin",
                                    user_id: params[:teacher].presence)
  end

  def create
    @test_session = TestSession.new(test_params)
    if question_ids_param.empty?
      @test_session.errors.add(:base, "Pick at least one question.")
    elsif @test_session.user && !@test_session.user.faculty?
      @test_session.errors.add(:user, "must be a teacher or admin")
    end

    if @test_session.errors.none? && @test_session.save
      log!("create_test", record: @test_session, label: @test_session.title,
           details: { teacher: @test_session.user&.email_address, questions: @test_session.question_ids.size })
      redirect_to admin_test_sessions_path, notice: "Test created#{@test_session.pin_required? ? " · PIN #{@test_session.pin_code}" : ""}."
    else
      load_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    locked = @test_session.editing_locked?
    before = @test_session.attributes.slice(*TRACKED)
    before_questions = @test_session.question_ids.sort

    if question_ids_param.empty?
      @test_session.errors.add(:base, "A test cannot be left empty. Keep at least one question.")
    elsif locked && reason_param.blank?
      @test_session.errors.add(:base, "This test is locked. Write the reason (e.g. the teacher's request) to change it.")
    end
    if @test_session.errors.any?
      @test_session.assign_attributes(test_params.except(:question_ids))
      load_form_data
      render :edit, status: :unprocessable_entity
      return
    end

    saved = TestSession.transaction do
      @test_session.admin_override = true
      @test_session.assign_attributes(test_params)
      @test_session.save || raise(ActiveRecord::Rollback)
    end

    if saved
      log!(locked ? "update_locked_test" : "update_test", record: @test_session, label: @test_session.title,
           reason: reason_param, details: change_details(before, before_questions).merge("students_started" => @test_session.test_attempts.count))
      redirect_to admin_test_sessions_path, notice: "Saved “#{@test_session.title}”."
    else
      messages = @test_session.errors.full_messages
      @test_session.reload.assign_attributes(test_params.except(:question_ids)) # questions were rolled back
      messages.each { |m| @test_session.errors.add(:base, m) }
      load_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  # A test with results needs its title typed; a locked test also needs a reason.
  def destroy
    attempts = @test_session.test_attempts.count
    locked = @test_session.editing_locked?
    if attempts.positive? && !confirmed?(@test_session.title)
      redirect_to edit_admin_test_session_path(@test_session), alert: "Type the test's title to confirm: #{attempts} student result(s) will be deleted."
      return
    end
    if locked && reason_param.blank?
      redirect_to edit_admin_test_session_path(@test_session), alert: "This test is locked. Give a reason to delete it."
      return
    end

    label = @test_session.title
    details = { exam: @test_session.exam.name, teacher: @test_session.user&.email_address, attempts_deleted: attempts }
    @test_session.destroy!
    log!("delete_test", label: label, reason: reason_param, details: details)
    redirect_to admin_test_sessions_path, notice: "Deleted “#{label}”."
  end

  private

  TRACKED = %w[title exam_type user_id duration_minutes pass_mark_percentage access_type starts_at ends_at strict_mode].freeze

  def set_test_session
    @test_session = TestSession.find(params[:id])
  end

  def load_form_data
    @questions = Question.in_order
    @owners = User.where(role: [:teacher, :admin]).order(:email_address)
  end

  def question_ids_param
    Array(params.dig(:test_session, :question_ids)).compact_blank
  end

  def test_params
    params.require(:test_session).permit(:title, :exam_type, :user_id, :duration_minutes, :pass_mark_percentage,
                                         :access_type, :starts_at, :ends_at, :strict_mode, question_ids: [])
  end

  def change_details(before, before_questions)
    after = @test_session.attributes.slice(*TRACKED)
    changes = after.filter_map { |k, v| [k, { "from" => before[k], "to" => v }] unless before[k] == v }.to_h
    after_questions = @test_session.question_ids.sort
    if after_questions != before_questions
      changes["questions"] = { "added" => after_questions - before_questions, "removed" => before_questions - after_questions }
    end
    changes
  end
end
