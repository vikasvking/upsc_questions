class DashboardsController < ApplicationController
  BLOCKED_MESSAGE = "You were blocked from this test for leaving it. Ask your teacher to reinstate you.".freeze

  before_action :ensure_student_access
  before_action :set_attempt, only: [:arena, :submit_answer, :skip_question, :finish_test, :results, :heartbeat, :report_leave]
  before_action :stop_if_blocked, only: [:arena, :submit_answer, :skip_question, :finish_test, :results]
  before_action :close_if_time_up, only: [:arena, :submit_answer, :skip_question]

  # GET /dashboard            -> hub
  # GET /dashboard?topic=X    -> rules page for a practice topic
  def show
    if params[:topic].present?
      @topic = params[:topic]
      @total_q_count = Question.where(topic: @topic).count
      @resume_attempt = Current.user.test_attempts.in_progress.find_by(topic: @topic, test_session_id: nil)
      render :test_confirmation
      return
    end

    set_global_dashboard_metrics
    @streak_days = generate_streak_calendar_data
    @progress    = StudentProgress.new(Current.user)

    # Ranks are per exam: "Preparing for" (profile) unless the student picks another exam here
    @rank_exams  = (Exam.codes & ([Current.user.target_exam] + Current.user.practised_exam_codes)).map { |c| Exam::BY_CODE[c] }
    @rank_exam   = Exam.normalize(params[:exam]) || Current.user.ranking_exam_code
    @comparison  = Leaderboard.comparison_for(Current.user, @rank_exam)

    # Only the 3 newest tests that are live or opening soon; the rest are on "All Tests"
    @latest_tests = TestSession.includes(:user)
                               .where("test_sessions.ends_at IS NULL OR test_sessions.ends_at > ?", Time.current)
                               .newest_first.limit(3).to_a
    load_card_data(@latest_tests)
  end

  # GET /dashboard/all_tests?exam=UPSC&subject=Physics
  def all_tests
    @exam    = Exam.normalize(params[:exam])
    @subject = params[:subject].presence

    used = TestSession.distinct.pluck(:exam_type)
    @exam_options    = Exam.options.select { |_, code| used.include?(code) }
    @subject_options = Question.joins(:test_questions).where.not(topic: [nil, ""]).distinct.order(:topic).pluck(:topic)

    scope = TestSession.includes(:user)
    scope = scope.where(exam_type: @exam) if @exam
    if @subject
      scope = scope.where(id: TestQuestion.joins(:question).where(questions: { topic: @subject }).select(:test_session_id))
    end

    # Live first, then opening soon, then closed; newest first inside each group
    rank = { live: 0, upcoming: 1, closed: 2 }
    @tests = scope.newest_first.to_a.sort_by.with_index { |t, i| [rank[t.window_status], i] }
    load_card_data(@tests)
  end

  # GET /dashboard/tests/:id -> rules page for a teacher test
  def test_intro
    @test_session = TestSession.find(params[:id])
    @existing_attempt = Current.user.test_attempts.find_by(test_session: @test_session)
    @existing_attempt&.enforce_presence!

    unless can_access_test?(@test_session)
      redirect_to join_test_sessions_path, alert: "This test needs a PIN. Enter the code from your teacher."
      return
    end

    @total_q_count = @test_session.questions.count
    render :test_confirmation
  end

  # POST /dashboard/start_test (topic=... OR test_session_id=...)
  def start_test
    if params[:test_session_id].present?
      start_teacher_test(TestSession.find(params[:test_session_id]))
    else
      start_practice(params[:topic].to_s)
    end
  end

  # GET /dashboard/arena/:token?n=3
  def arena
    @questions = @attempt.questions.to_a
    if @questions.empty?
      redirect_to dashboard_path, alert: "This test has no questions yet."
      return
    end

    @position = params[:n].to_i.clamp(1, @questions.size)
    @question = @questions[@position - 1]
    @responses = @attempt.responses_by_question
    @previous_attempt = @responses[@question.id]
    @attempt.record_presence! if @attempt.strict?
    render :quiz_arena
  end

  def submit_answer
    chosen = params[:answer_choice].to_s.strip.upcase
    question = find_question_in_attempt
    return unless question

    unless Question::ANSWER_KEYS.include?(chosen)
      redirect_to arena_dashboard_path(@attempt.token, n: params[:n]), alert: "Please select an option before submitting."
      return
    end

    save_response(question, chosen, chosen == question.correct_answer.to_s.strip.upcase)
    go_to_next_question(question)
  end

  def skip_question
    question = find_question_in_attempt
    return unless question

    save_response(question, "SKIPPED", false)
    go_to_next_question(question)
  end

  def finish_test
    @attempt.finish!
    redirect_to test_results_dashboard_path(token: @attempt.token), notice: "Test submitted."
  end

  # GET /dashboard/results?token=...
  def results
    @attempt.finish! if @attempt.expired?
    unless @attempt.finished?
      redirect_to arena_dashboard_path(@attempt.token), alert: "Finish the test to see your results."
      return
    end

    # Strict tests: marks, rank and answers only after the test closes
    unless @attempt.results_released?
      render :results_pending
      return
    end

    @topic     = @attempt.title
    @questions = @attempt.questions.to_a
    @responses = @attempt.responses_by_question
    @summary   = @attempt.score_summary
    @correct_count = @summary[:correct]
    @wrong_count   = @summary[:wrong]

    # Rank among everyone who has submitted this teacher test so far
    if @attempt.test_session
      ranking = @attempt.test_session.rankings
      @my_result = ranking.find { |r| r.attempt.id == @attempt.id }
      @ranked_count = ranking.size
    end
  end

  # ---------- strict mode (JSON, called by strict_mode_controller.js) ----------

  # POST /dashboard/heartbeat  token=...
  def heartbeat
    @attempt.enforce_presence!
    render json: strict_state(present: true)
  end

  # POST /dashboard/report_leave  token=... seconds=12 kind=hidden|navigated|reloaded
  # Sent by the test page after the student comes back (or, for in-app navigation, while they are away).
  def report_leave
    @attempt.enforce_presence!
    seconds = params[:seconds].to_i
    if seconds >= TestAttempt::AWAY_GRACE.to_i
      where = { "navigated" => "opened another page", "reloaded" => "closed or left the page" }
                .fetch(params[:kind].to_s, "switched to another tab or app")
      @attempt.record_violation!("Left the test (#{where}) for #{seconds}s")
    end
    render json: strict_state(present: params[:kind] != "navigated")
  end

  private

  def strict_state(present:)
    if @attempt.blocked?
      { status: "blocked", message: BLOCKED_MESSAGE, redirect_to: test_intro_dashboard_path(@attempt.test_session) }
    elsif @attempt.finished? || @attempt.expired?
      { status: "finished", redirect_to: test_results_dashboard_path(token: @attempt.token) }
    else
      @attempt.record_presence! if present && @attempt.strict?
      { status: "ok", leave_count: @attempt.leave_count, warnings_left: @attempt.warnings_left }
    end
  end

  # Attempts and subject names for a list of test cards (2 queries in total)
  def load_card_data(tests)
    ids = tests.map(&:id)
    @my_attempts_by_test = Current.user.test_attempts.where(test_session_id: ids).index_by(&:test_session_id)

    # My rank on each test I have submitted: { test_id => [rank, number of students] }
    @ranks_by_test = {}
    tests.each do |t|
      mine = @my_attempts_by_test[t.id]
      next unless mine&.finished? || mine&.expired?
      next if mine.blocked? || !t.results_released? # strict tests show ranks only after they close
      ranking = t.rankings
      me = ranking.find { |r| r.attempt.id == mine.id }
      @ranks_by_test[t.id] = [me.rank, ranking.size] if me
    end
    @subjects_by_test = TestQuestion.joins(:question)
                                    .where(test_session_id: ids)
                                    .distinct
                                    .order("questions.topic")
                                    .pluck(:test_session_id, "questions.topic")
                                    .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(id, topic), h| h[id] << topic if topic.present? }
  end

  # ---------- starting ----------

  def start_practice(topic)
    if topic.blank? || !Question.exists?(topic: topic)
      redirect_to dashboard_path, alert: "That topic has no questions."
      return
    end

    attempt = Current.user.test_attempts.in_progress.find_by(topic: topic, test_session_id: nil) ||
              Current.user.test_attempts.create!(topic: topic)
    redirect_to arena_dashboard_path(attempt.token, n: 1)
  end

  def start_teacher_test(test)
    unless can_access_test?(test)
      redirect_to join_test_sessions_path, alert: "This test needs a PIN. Enter the code from your teacher."
      return
    end

    existing = Current.user.test_attempts.find_by(test_session: test)
    existing&.enforce_presence!
    if existing&.blocked?
      redirect_to test_intro_dashboard_path(test), alert: BLOCKED_MESSAGE
      return
    end
    if existing&.finished? || existing&.expired?
      existing.finish!
      redirect_to test_results_dashboard_path(token: existing.token), notice: "You have already submitted this test."
      return
    end
    if existing
      redirect_to arena_dashboard_path(existing.token), notice: "Resuming your test."
      return
    end

    case test.window_status
    when :upcoming
      redirect_to test_intro_dashboard_path(test), alert: "This test opens at #{I18n.l(test.starts_at, format: :long)}."
      return
    when :closed
      redirect_to dashboard_path, alert: "This test closed at #{I18n.l(test.ends_at, format: :long)}."
      return
    end

    if test.questions.none?
      redirect_to dashboard_path, alert: "This test has no questions yet."
      return
    end

    attempt = Current.user.test_attempts.create!(test_session: test)
    redirect_to arena_dashboard_path(attempt.token, n: 1)
  end

  # Open tests: anyone. PIN tests: only after the student entered the PIN (remembered in their session).
  def can_access_test?(test)
    test.open_access? || unlocked_test_ids.include?(test.id) ||
      Current.user.test_attempts.exists?(test_session: test)
  end

  def unlocked_test_ids
    Array(session[:unlocked_test_ids]).map(&:to_i)
  end

  # ---------- answering ----------

  def set_attempt
    token = params[:token].presence
    @attempt = token && Current.user.test_attempts.find_by(token: token)
    return if @attempt

    if request.format.json?
      head :not_found
    else
      redirect_to dashboard_path, alert: "Test not found."
    end
  end

  # Strict tests: a blocked student cannot see, answer or submit anything until reinstated
  def stop_if_blocked
    @attempt.enforce_presence!
    redirect_to test_intro_dashboard_path(@attempt.test_session), alert: BLOCKED_MESSAGE if @attempt.blocked?
  end

  def close_if_time_up
    if @attempt.finished?
      redirect_to test_results_dashboard_path(token: @attempt.token), notice: "This test has already been submitted."
    elsif @attempt.expired?
      @attempt.finish!
      redirect_to test_results_dashboard_path(token: @attempt.token), alert: "Time is up. Your test was submitted automatically."
    end
  end

  def find_question_in_attempt
    question = @attempt.questions.find_by(id: params[:question_id])
    redirect_to arena_dashboard_path(@attempt.token), alert: "That question is not part of this test." unless question
    question
  end

  # One answer per question per attempt: answering again replaces the old answer
  def save_response(question, chosen, correct)
    response = Current.user.user_responses.find_or_initialize_by(question: question, test_session_token: @attempt.token)
    response.update!(
      chosen_option: chosen,
      is_correct: correct,
      duration_seconds: response.duration_seconds.to_i + params[:duration_seconds].to_i
    )
  end

  # Next unanswered question after the current one; wraps round to earlier gaps; finishes when all are done
  def go_to_next_question(question)
    questions = @attempt.questions.to_a
    answered  = @attempt.user_responses.pluck(:question_id).to_set
    current   = questions.index { |q| q.id == question.id }.to_i + 1

    order = ((current + 1)..questions.size).to_a + (1...current).to_a
    next_n = order.find { |n| !answered.include?(questions[n - 1].id) }

    if next_n
      redirect_to arena_dashboard_path(@attempt.token, n: next_n)
    else
      @attempt.finish!
      redirect_to test_results_dashboard_path(token: @attempt.token), notice: "All questions answered. Test submitted."
    end
  end

  # ---------- dashboard metrics ----------

  def generate_streak_calendar_data
    (0..6).to_a.reverse.map do |day_offset|
      target_date = Date.current - day_offset
      solved_count = Current.user.user_responses.where(created_at: target_date.all_day).count

      {
        date: target_date,
        day_name: target_date.strftime("%a"),
        day_number: target_date.day,
        solved_count: solved_count,
        target_fulfilled: solved_count >= 25,
        is_today: target_date == Date.current
      }
    end
  end

  # Counts consecutive days (ending today or yesterday) with 25+ answers
  def calculate_active_streak
    daily = Current.user.user_responses
                   .where(created_at: 400.days.ago.beginning_of_day..)
                   .group("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{Time.zone.tzinfo.name}')")
                   .count
                   .transform_keys(&:to_date)

    day = Date.current
    day -= 1 if daily[day].to_i < 25
    streak = 0
    while daily[day].to_i >= 25
      streak += 1
      day -= 1
    end
    streak
  end

  def set_global_dashboard_metrics
    @current_streak_count = calculate_active_streak
    responses = Current.user.user_responses
    total_platform_questions = Question.count
    @bank_total = total_platform_questions

    @lifetime_correct_count = responses.where(is_correct: true).distinct.count(:question_id)
    @lifetime_wrong_count   = responses.where(is_correct: false).where.not(chosen_option: "SKIPPED").distinct.count(:question_id)
    unique_attempted        = responses.distinct.count(:question_id)
    @overall_completion_pct = total_platform_questions.positive? ? (unique_attempted * 100.0 / total_platform_questions).round : 0

    answered = responses.where.not(chosen_option: "SKIPPED").count
    @global_accuracy_pct = answered.positive? ? (responses.where(is_correct: true).count * 100.0 / answered).round(1) : 0.0
  end

  def ensure_student_access
    if Current.user&.faculty?
      redirect_to test_sessions_path, notice: "Teachers and admins manage tests from here."
    end
  end
end
