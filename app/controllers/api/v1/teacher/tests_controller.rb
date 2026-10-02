# A teacher's tests (admins see every test), with the same rules as the website.
#   GET   /api/v1/teacher/form_options          -> exams, my schools/coachings (with test quota), my batches
#   GET   /api/v1/teacher/tests                 -> my tests, newest first, 50 a page: ?exam=CBSE_XII (blank = all) &page=2
#                                                    -> { tests, next_page, exam, exams: [{ code, name, count }] }
#   GET   /api/v1/teacher/tests/:id             -> one test with its questions and audience (for editing)
#   POST  /api/v1/teacher/tests                 -> test[title, exam_type, duration_minutes, pass_mark_percentage, access_type,
#                                                    starts_at, ends_at, strict_mode, visibility, institution_id, question_ids[]], audience[...]
#   PATCH /api/v1/teacher/tests/:id             -> same fields; refused once the test is locked
#   GET   /api/v1/teacher/tests/:id/results     -> ranking, averages, blocked students
#   GET   /api/v1/teacher/tests/:id/live        -> strict tests: who is writing, silent, blocked, submitted
#   POST  /api/v1/teacher/tests/:id/reinstate   attempt_id=... -> lets a blocked student continue
module Api
  module V1
    module Teacher
      class TestsController < BaseController
        ONLINE_WITHIN = TestSessionsController::ONLINE_WITHIN

        before_action :set_test, only: [:show, :update, :results, :live, :reinstate]

        def form_options
          user = current_user
          institutions = user.admin? ? Institution.ordered.to_a : user.institutions.ordered.to_a
          batches = user.admin? ? Batch.ordered.to_a : user.batches.ordered.to_a
          render json: {
            exams: Exam.all.map { |e| exam_json(e.code) },
            visibilities: Audience::VISIBILITIES.map { |value, label| { value: value, label: label } },
            institutions: institutions.map do |i|
              used, limit = i.subscribed? ? i.usage[:tests] : [nil, nil]
              { id: i.id, name: i.name, label: i.label, subscribed: i.subscribed?, tests_this_month: used, tests_limit: limit }
            end,
            batches: batches.map { |b| { id: b.id, name: b.name, students: b.batch_members.size } },
            defaults: { duration_minutes: 45, pass_mark_percentage: 40, access_type: "pin" }
          }
        end

        PER_PAGE = 50

        # One exam at a time (or all), one page at a time, so the list stays fast however many tests there are
        def index
          scope = current_user.admin? ? TestSession.all : current_user.test_sessions
          exam = Exam.normalize(params[:exam])
          counts = scope.group(:exam_type).count
          scope = scope.where(exam_type: exam) if exam

          page = [params[:page].to_i, 1].max
          rows = scope.includes(:user, :institution, :audience_grants).newest_first.order(id: :desc) # id keeps pages stable
                      .offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
          tests = rows.first(PER_PAGE)
          ids = tests.map(&:id)
          question_counts = TestQuestion.where(test_session_id: ids).group(:test_session_id).count
          attempt_counts = TestAttempt.first_tries.where(test_session_id: ids).group(:test_session_id).count # students, not retakes
          render json: {
            tests: tests.map { |t| teacher_card(t, question_counts[t.id].to_i, attempt_counts[t.id].to_i) },
            next_page: rows.size > PER_PAGE ? page + 1 : nil,
            exam: exam,
            exams: Exam.all.filter_map { |e| { code: e.code, name: e.name, count: counts[e.code] } if counts[e.code].to_i.positive? }
          }
        end

        def show
          render json: {
            test: teacher_card(@test, @test.questions.count, @test.test_attempts.first_tries.count).merge(
              question_ids: @test.ordered_questions.pluck(:id),
              questions: @test.ordered_questions.map { |q| teacher_question_json(q) },
              audience: audience_json(@test)
            )
          }
        end

        def create
          test = current_user.test_sessions.new(test_params)
          return render_error("invalid", "Pick at least one question for this test.") if question_ids_param.empty?

          if audience_valid?(test) && test.save
            apply_audience!(test)
            render json: { test: teacher_card(test.reload, test.questions.count, 0), warning: warning,
                           message: test.open_access? ? "Test created (#{test.audience_label.downcase})." : "Test created. Share PIN: #{test.pin_code}" },
                   status: :created
          else
            render_error("invalid", errors_of(test))
          end
        end

        def update
          if @test.editing_locked?
            return render_error("locked",
                                "“#{@test.title}” can no longer be edited: tests with a time window or strict mode lock " \
                                "#{TestSession::EDIT_LOCK_BEFORE.in_minutes.to_i} minutes before they open, once a student has started, and after they close.",
                                status: :conflict)
          end
          return render_error("invalid", "A test cannot be left empty. Keep at least one question.") if question_ids_param.empty?

          @test.assign_attributes(test_params)
          if audience_valid?(@test) && @test.save
            apply_audience!(@test)
            render json: { test: teacher_card(@test.reload, @test.questions.count, @test.test_attempts.first_tries.count), warning: warning, message: "Test updated." }
          else
            render_error("invalid", errors_of(@test))
          end
        end

        def results
          results = @test.rankings
          @test.block_silent_students!
          blocked = @test.test_attempts.blocked.includes(:user).order(:blocked_at)
          rating = Rating.summary_for(@test)
          question_stats = @test.question_analysis

          render json: {
            test: teacher_card(@test, @test.questions.count, @test.test_attempts.first_tries.count),
            participants: results.size,
            in_progress: @test.test_attempts.first_tries.in_progress.not_blocked.count,
            average_marks: results.any? ? (results.sum(&:marks) / results.size).round(2) : 0.0,
            average_pct: results.any? ? (results.sum(&:percentage) / results.size).round(1) : 0.0,
            rating: rating.count.positive? ? { average: rating.average&.round(1), count: rating.count } : nil,
            results: results.map do |r|
              { attempt_id: r.attempt.id, rank: r.rank, name: r.user.display_name, email_address: r.user.email_address,
                marks: r.marks, max_marks: r.max_marks, percentage: r.percentage, passed: r.passed,
                correct: r.correct, wrong: r.wrong, skipped: r.skipped, unattempted: r.unattempted, total: r.total,
                time_taken: r.time_taken, finished_at: time_json(r.attempt.finished_at),
                ended_reason: r.attempt.ended_reason } # strict open tests: why the test ended early
            end,
            blocked: blocked.map { |a| blocked_json(a) },
            questions: question_stats.map { |st| question_stat_json(st) },
            topics: @test.topic_analysis(question_stats).map { |t| { topic: t.topic, questions: t.questions, correct_pct: t.correct_pct } },
            # the website's downloads (the teacher signs in there): CSV for Excel, and a printable report
            export_path: export_test_session_path(@test),
            report_path: report_test_session_path(@test)
          }
        end

        # (shared between teachers for a few seconds, see TestSession#live_snapshot)
        def live
          now = Time.current
          snapshot = @test.live_snapshot(now)
          rows = snapshot.rows.map do |r|
            a = r.attempt
            { attempt_id: a.id, name: r.user.display_name, email_address: r.user.email_address, status: r.status.to_s,
              answered: r.answered, leave_count: a.leave_count, block_reason: a.block_reason,
              seconds_silent: r.seconds_silent, seconds_left: a.seconds_left(now),
              finished_at: time_json(a.finished_at), ended_reason: a.ended_reason }
          end

          render json: {
            live: @test.live_view?(now),
            refreshed_at: time_json(snapshot.refreshed_at),
            total_questions: snapshot.total_questions,
            counts: snapshot.counts.transform_keys(&:to_s).merge("not_started" => snapshot.not_started.size),
            rows: rows,
            not_started: snapshot.not_started.map { |e| { name: e.user.display_name, email_address: e.user.email_address, pin_entered_at: time_json(e.created_at) } }
          }
        end

        def reinstate
          attempt = @test.test_attempts.find(params[:attempt_id])
          if attempt.reinstate!
            render json: { message: "#{attempt.user.display_name} can continue the test." }
          else
            render_error("not_blocked", "That student is not blocked.", status: :conflict)
          end
        end

        private

        def set_test
          @test = TestSession.find(params[:id])
          unless @test.user_id == current_user.id || current_user.admin?
            render_error("not_yours", "You can only open tests you created.", status: :forbidden)
          end
        end

        def question_ids_param
          Array(params.dig(:test, :question_ids)).compact_blank
        end

        def test_params
          params.require(:test).permit(:title, :exam_type, :duration_minutes, :pass_mark_percentage, :access_type,
                                       :starts_at, :ends_at, :strict_mode, :visibility, :institution_id, question_ids: [])
        end

        def teacher_card(test, question_count, attempt_count)
          {
            id: test.id,
            title: test.title,
            exam: exam_json(test.exam_type),
            duration_minutes: test.duration_minutes,
            pass_mark_percentage: test.pass_mark_percentage,
            access: test.access_type,
            pin_code: test.pin_required? ? test.pin_code : nil,
            strict: test.strict_mode?,
            ends_on_leave: test.ends_on_leave?,
            starts_at: time_json(test.starts_at),
            ends_at: time_json(test.ends_at),
            window: test.window_status.to_s,
            locked: test.editing_locked?,
            live_view: test.live_view?,
            free_sample: test.free_sample?,
            author: test.author_name,
            visibility: test.visibility,
            audience: test.audience_label,
            question_count: question_count,
            attempt_count: attempt_count,
            created_at: time_json(test.created_at)
          }
        end

        def blocked_json(attempt)
          { attempt_id: attempt.id, name: attempt.user.display_name, email_address: attempt.user.email_address,
            reason: attempt.block_reason, blocked_at: time_json(attempt.blocked_at), in_progress: !attempt.finished? }
        end

        def teacher_question_json(q)
          { id: q.id, exam: q.exam_type, year: q.year, topic: q.topic, content: q.content,
            options: { "A" => q.option_a, "B" => q.option_b, "C" => q.option_c, "D" => q.option_d },
            correct_answer: q.correct_answer }
        end

        # One row of the question-wise analysis (letters are the question's own)
        def question_stat_json(stat)
          wrong = stat.common_wrong
          q = stat.question
          { id: q.id, number: stat.number, content: q.content, topic: q.topic, correct_answer: q.correct_answer,
            students: stat.students, correct: stat.correct, wrong: stat.wrong, skipped: stat.skipped,
            unattempted: stat.unattempted, correct_pct: stat.correct_pct, picks: stat.picks,
            common_wrong: wrong && { letter: wrong.first, count: wrong.last, pct: stat.percent(wrong.last),
                                     text: q.option_text(wrong.first) } }
        end
      end
    end
  end
end
