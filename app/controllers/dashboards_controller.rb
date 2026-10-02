class DashboardsController < ApplicationController
  include ExamListing # paginate, for My Tests
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
      @total_q_count = Question.available_to(Current.user).where(topic: @topic).count
      @resume_attempt = Current.user.test_attempts.in_progress.find_by(topic: @topic, test_session_id: nil)
      render :test_confirmation
      return
    end

    set_global_dashboard_metrics
    @streak_days = generate_streak_calendar_data
    @progress    = StudentProgress.new(Current.user, exams: Current.user.exam_codes)

    # Ranks are per exam: "Preparing for" (profile) unless the student picks another exam here
    @rank_exams  = (Exam.codes & ([Current.user.target_exam] + Current.user.exam_codes + Current.user.practised_exam_codes)).map { |c| Exam::BY_CODE[c] }
    @rank_exam   = Exam.normalize(params[:exam]) || Current.user.ranking_exam_code
    @comparison  = Leaderboard.comparison_for(Current.user, @rank_exam)

    # Only the 3 newest tests that are live or opening soon; the rest are on "All Tests".
    # Tests outside the student's tier are listed too, marked 🔒 with an upgrade button.
    latest = TestSession.visible_to(Current.user).includes(:user, :institution, :audience_grants)
                        .where("test_sessions.ends_at IS NULL OR test_sessions.ends_at > ?", Time.current)
    latest = latest.where(exam_type: Current.user.exam_codes) if Current.user.exam_codes.any?
    @latest_tests = latest.newest_first.limit(3).to_a
    load_card_data(@latest_tests)
  end

  # GET /dashboard/all_tests?exam=mine|all|UPSC_PRELIMS&subject=Physics&institution=3&teacher=7&attempted=1
  # Lists every test the student can see; ones their tier does not include show 🔒 Upgrade (see load_card_data).
  # Tests the student has already attempted (submitted, or blocked from) are left out unless attempted=1;
  # a test they are still writing stays, so they can carry on.
  def all_tests
    visible = TestSession.visible_to(Current.user)
    my_exams = Current.user.exam_codes
    @exam_choice = params[:exam].presence || (my_exams.any? ? "mine" : "all")
    @exam    = Exam.normalize(@exam_choice)
    @subject = params[:subject].presence
    @institution = Current.user.institutions.find_by(id: params[:institution]) if params[:institution].present?
    @teacher_id = params[:teacher].presence&.to_i
    @show_attempted = params[:attempted] == "1"

    used = visible.distinct.pluck(:exam_type)
    @exam_options    = Exam.options.select { |_, code| used.include?(code) }
    @subject_options = Question.joins(:test_questions).where(test_questions: { test_session_id: visible.select(:id) })
                               .where.not(topic: [nil, ""]).distinct.order(:topic).pluck(:topic)
    @institution_options = Current.user.institutions.ordered
    @teacher_options = User.where(id: visible.select(:user_id)).order(:name, :email_address)

    scope = visible.includes(:user, :institution, :audience_grants)
    scope =
      if @exam then scope.where(exam_type: @exam)
      elsif @exam_choice == "mine" && my_exams.any? then scope.where(exam_type: my_exams)
      else scope
      end
    if @subject
      scope = scope.where(id: TestQuestion.joins(:question).where(questions: { topic: @subject }).select(:test_session_id))
    end
    if @institution
      teacher_ids = @institution.teachers.select(:id)
      scope = scope.where(institution_id: @institution.id).or(scope.where(user_id: teacher_ids))
    end
    scope = scope.where(user_id: @teacher_id) if @teacher_id

    # Live first, then opening soon, then closed; newest first inside each group
    rank = { live: 0, upcoming: 1, closed: 2 }
    @tests = scope.newest_first.to_a.sort_by.with_index { |t, i| [rank[t.window_status], i] }

    attempted = attempted_test_ids
    @hidden_attempted = @show_attempted ? 0 : @tests.count { |t| attempted.include?(t.id) }
    @tests.reject! { |t| attempted.include?(t.id) } unless @show_attempted
    load_card_data(@tests)
  end

  # GET /dashboard/my_tests?kind=all|tests|practice -> every test and practice the student has started, newest first
  # (each retake is its own line; every line opens its result or carries on where it stopped)
  MY_TESTS_KINDS = { "all" => "All", "tests" => "Teacher tests", "practice" => "Topic practice" }.freeze

  def my_tests
    @kind = params[:kind].presence_in(MY_TESTS_KINDS.keys) || "all"
    scope = Current.user.test_attempts.includes(:test_session)
    scope = scope.where.not(test_session_id: nil) if @kind == "tests"
    scope = scope.where(test_session_id: nil) if @kind == "practice"
    @total = scope.count
    @rows = AttemptSummary.for(paginate(scope.order(started_at: :desc, id: :desc)))
  end

  # GET /dashboard/tests/:id -> rules page for a teacher test
  # (for a test outside the student's tier: its details plus the upgrade options instead of Start)
  def test_intro
    @test_session = TestSession.visible_to(Current.user).find_by(id: params[:id])
    return redirect_to(all_tests_dashboard_path, alert: "That test is not available to you.") unless @test_session
    @total_q_count = @test_session.questions.count
    # the details the compact test cards leave out: subjects and the students' rating
    @subjects = @test_session.questions.where.not(topic: [nil, ""]).distinct.order(:topic).pluck(:topic)
    @rating_summary = Rating.summary_for(@test_session)
    @locked = !TestSession.available_to(Current.user).exists?(@test_session.id)
    return render(:test_confirmation) if @locked

    @existing_attempt = TestAttempt.latest_for(Current.user, @test_session)
    @existing_attempt&.enforce_presence!
    @can_retake = @existing_attempt&.retake_allowed? || false
    @attempt_count = Current.user.test_attempts.where(test_session: @test_session).count

    unless can_access_test?(@test_session)
      redirect_to join_test_sessions_path, alert: "This test needs a PIN. Enter the code from your teacher."
      return
    end

    render :test_confirmation
  end

  # POST /dashboard/start_test (topic=... OR test_session_id=...)
  def start_test
    if params[:test_session_id].present?
      test = TestSession.available_to(Current.user).find_by(id: params[:test_session_id])
      unless test
        # a test they can see but their tier does not include -> its page with the upgrade options
        visible = TestSession.visible_to(Current.user).find_by(id: params[:test_session_id])
        return redirect_to(visible ? test_intro_dashboard_path(visible) : all_tests_dashboard_path, alert: not_available_message)
      end
      start_teacher_test(test)
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
    @options = @attempt.options_for(@question)
    @marked_ids = @attempt.marked_ids_in(@questions).to_set
    @unanswered_count = @questions.count { |q| !@responses.key?(q.id) }
    @attempt.record_presence! if @attempt.strict?
    render :quiz_arena
  end

  # "Save & Next" saves the chosen option and clears any review mark.
  # "Mark for Review & Next" (teacher tests, params[:mark]) flags the question, saving the option too if one is chosen.
  def submit_answer
    question = find_question_in_attempt
    return unless question

    mark = params[:mark].present? && @attempt.test_session.present?
    chosen = @attempt.own_letter(question, params[:answer_choice]) # strict tests: the letter on screen may differ

    if chosen.nil? && !mark
      redirect_to arena_dashboard_path(@attempt.token, n: params[:n]), alert: "Please select an option before submitting."
      return
    end

    save_response(question, chosen, chosen == question.correct_answer.to_s.strip.upcase) if chosen
    @attempt.mark!(question, mark)
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

    # Rank among everyone who has submitted this teacher test so far (a retake shows the first attempt's rank)
    if (test = @attempt.test_session)
      ranked = @attempt.retake? ? test.first_attempt_for(Current.user) : @attempt
      ranking = test.rankings(for_attempt: ranked)
      @my_result = ranked && ranking.find { |r| r.attempt.id == ranked.id }
      @ranked_count = ranking.size
      @can_retake = TestAttempt.latest_for(Current.user, test)&.retake_allowed? || false
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
      # open strict tests end here, and the student reads "…because you switched to another tab or app for 12s"
      reason = @attempt.ends_on_leave? ? "#{where} for #{seconds}s" : "Left the test (#{where}) for #{seconds}s"
      @attempt.record_violation!(reason, left_at: seconds.seconds.ago)
    end
    render json: strict_state(present: params[:kind] != "navigated")
  end

  private

  def strict_state(present:)
    if @attempt.blocked?
      { status: "blocked", message: BLOCKED_MESSAGE, redirect_to: test_intro_dashboard_path(@attempt.test_session) }
    elsif @attempt.finished? || @attempt.expired?
      { status: "finished", message: @attempt.ended_message, redirect_to: test_results_dashboard_path(token: @attempt.token) }.compact
    else
      @attempt.record_presence! if present && @attempt.strict?
      { status: "ok", leave_count: @attempt.leave_count, warnings_left: @attempt.warnings_left }
    end
  end

  def upgrade_hint = "Join your school's plan (Plus) or become a Warrior to unlock more."

  def not_available_message
    case Current.user.tier
    when "free" then "Free members can take the #{Tiers::FREE_SAMPLE_TESTS} sample tests. #{upgrade_hint}"
    when "plus" then "This test is for an exam outside your school's plan. Become a Warrior to take every exam."
    else "That test is not available to you."
    end
  end

  # Teacher tests the student has attempted: submitted (or out of time), or blocked from
  def attempted_test_ids
    Current.user.test_attempts.where.not(test_session_id: nil)
           .where("finished_at IS NOT NULL OR blocked_at IS NOT NULL OR deadline_at < ?", Time.current - TestAttempt::GRACE_PERIOD)
           .distinct.pluck(:test_session_id).to_set
  end

  # Attempts, ranks, question counts and 🔒 locks for a list of test cards
  def load_card_data(tests)
    ids = tests.map(&:id)
    # tests shown but not included in the student's tier (Free: all but the samples; Plus: other exams)
    @locked_test_ids = ids - TestSession.available_to(Current.user).where(id: ids).pluck(:id)
    # the latest attempt per test (a retake once the student has retaken it); ranks come from the first attempt
    @my_attempts_by_test = Current.user.test_attempts.where(test_session_id: ids).order(:id).index_by(&:test_session_id)
    first_tries = Current.user.test_attempts.first_tries.where(test_session_id: ids).index_by(&:test_session_id)
    @question_counts = TestQuestion.where(test_session_id: ids).group(:test_session_id).count

    # My rank on each test I have submitted: { test_id => [rank, number of students] }
    @ranks_by_test = {}
    tests.each do |t|
      mine = first_tries[t.id]
      next unless mine&.finished? || mine&.expired?
      next if mine.blocked? || !t.results_released? # strict tests show ranks only after they close
      ranking = t.rankings(for_attempt: mine)
      me = ranking.find { |r| r.attempt.id == mine.id }
      @ranks_by_test[t.id] = [me.rank, ranking.size] if me
    end
  end

  # ---------- starting ----------

  def start_practice(topic)
    if Current.user.free_tier?
      redirect_to question_bank_path, alert: "Free members practise the #{Tiers::FREE_SAMPLE_QUESTIONS} sample questions in the Question Bank. #{upgrade_hint}"
      return
    end
    if topic.blank? || !Question.available_to(Current.user).exists?(topic: topic)
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

    existing = TestAttempt.latest_for(Current.user, test)
    existing&.enforce_presence!
    if existing&.blocked?
      redirect_to test_intro_dashboard_path(test), alert: BLOCKED_MESSAGE
      return
    end
    if existing&.finished? || existing&.expired?
      existing.finish!
      return start_retake(test, existing) if params[:retake].present?
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

    attempt = TestAttempt.start_first_try!(Current.user, test)
    redirect_to arena_dashboard_path(attempt.token, n: 1)
  end

  # Another go at a submitted test: practice, never ranked (the first attempt keeps the rank)
  def start_retake(test, previous)
    unless previous.retake_allowed?
      redirect_to test_results_dashboard_path(token: previous.token),
                  alert: "You can retake this test after it closes at #{I18n.l(test.ends_at, format: :long)}."
      return
    end
    if test.questions.none?
      redirect_to dashboard_path, alert: "This test has no questions yet."
      return
    end

    attempt = Current.user.test_attempts.create!(test_session: test, retake: true)
    redirect_to arena_dashboard_path(attempt.token, n: 1), notice: "Retake started. This is practice: your rank stays from your first attempt."
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
    if @attempt.finished? && @attempt.ended_early?
      redirect_to test_results_dashboard_path(token: @attempt.token), alert: @attempt.ended_message
    elsif @attempt.finished?
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

  # Next unanswered question after the current one, wrapping round to earlier gaps. Once everything is answered:
  # topic practice finishes; a teacher test goes through the questions marked for review and then waits for Submit.
  def go_to_next_question(question)
    questions = @attempt.questions.to_a
    answered  = @attempt.user_responses.pluck(:question_id).to_set
    marked    = @attempt.marked_ids_in(questions).to_set
    current   = questions.index { |q| q.id == question.id }.to_i + 1

    order = ((current + 1)..questions.size).to_a + (1...current).to_a
    next_n = order.find { |n| !answered.include?(questions[n - 1].id) }

    if next_n
      redirect_to arena_dashboard_path(@attempt.token, n: next_n)
    elsif @attempt.submits_when_all_answered?
      @attempt.finish!
      redirect_to test_results_dashboard_path(token: @attempt.token), notice: "All questions answered. Test submitted."
    elsif (next_marked = order.find { |n| marked.include?(questions[n - 1].id) })
      redirect_to arena_dashboard_path(@attempt.token, n: next_marked),
                  notice: "All questions answered. Here is the next one you marked for review (#{marked.size} marked)."
    else
      still = marked.any? ? " #{marked.size} still marked for review." : ""
      redirect_to arena_dashboard_path(@attempt.token, n: current),
                  notice: "All questions answered.#{still} Check any answer from the question grid, then press Finish & Submit."
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
    total_platform_questions = Question.available_to(Current.user).count
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
