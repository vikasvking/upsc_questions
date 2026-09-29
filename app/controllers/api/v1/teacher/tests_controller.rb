# A teacher's tests (admins see every test), with the same rules as the website.
#   GET   /api/v1/teacher/form_options          -> exams, my schools/coachings (with test quota), my batches
#   GET   /api/v1/teacher/tests                 -> my tests
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

        def index
          scope = current_user.admin? ? TestSession.all : current_user.test_sessions
          tests = scope.includes(:user, :institution, :audience_grants).newest_first.limit(300).to_a
          ids = tests.map(&:id)
          question_counts = TestQuestion.where(test_session_id: ids).group(:test_session_id).count
          attempt_counts = TestAttempt.first_tries.where(test_session_id: ids).group(:test_session_id).count # students, not retakes
          render json: { tests: tests.map { |t| teacher_card(t, question_counts[t.id].to_i, attempt_counts[t.id].to_i) } }
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
          @test.test_attempts.in_progress.each(&:enforce_presence!) if @test.strict_mode?
          blocked = @test.test_attempts.blocked.includes(:user).order(:blocked_at)
          rating = Rating.summary_for(@test)

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
                time_taken: r.time_taken, finished_at: time_json(r.attempt.finished_at) }
            end,
            blocked: blocked.map { |a| blocked_json(a) }
          }
        end

        def live
          now = Time.current
          attempts = @test.test_attempts.first_tries.includes(:user).to_a # retakes are practice, not the live test
          attempts.each { |a| a.enforce_presence!(now) }
          answered = UserResponse.where(test_session_token: attempts.map(&:token)).group(:test_session_token).distinct.count(:question_id)

          rows = attempts.map do |a|
            status =
              if a.blocked? then "blocked"
              elsif a.finished? || a.expired?(now) then "submitted"
              elsif a.last_seen_at.nil? then "opening"
              elsif now - a.last_seen_at <= ONLINE_WITHIN then "writing"
              else "no_signal"
              end
            { attempt_id: a.id, name: a.user.display_name, email_address: a.user.email_address, status: status,
              answered: answered[a.token].to_i, leave_count: a.leave_count, block_reason: a.block_reason,
              seconds_silent: a.last_seen_at && (now - a.last_seen_at).to_i, seconds_left: a.seconds_left(now),
              finished_at: time_json(a.finished_at) }
          end
          order = %w[no_signal blocked opening writing submitted]
          rows.sort_by! { |r| [order.index(r[:status]), r[:name].downcase] }
          not_started = @test.test_pin_entries.includes(:user).where.not(user_id: attempts.map(&:user_id)).order(:created_at)

          render json: {
            live: @test.live_view?(now),
            refreshed_at: time_json(now),
            total_questions: @test.questions.count,
            counts: rows.map { |r| r[:status] }.tally.merge("not_started" => not_started.size),
            rows: rows,
            not_started: not_started.map { |e| { name: e.user.display_name, email_address: e.user.email_address, pin_entered_at: time_json(e.created_at) } }
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
      end
    end
  end
end
