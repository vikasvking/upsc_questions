# Taking a test or a topic practice, and its result (same rules as the website's test pages).
#   POST /api/v1/practice  topic=Physics                  -> { attempt_token } (Plus and Warrior)
#   GET  /api/v1/attempts  page=2 kind=tests|practice     -> my tests and practices, newest first, with marks and rank
#   GET  /api/v1/attempts/:token                          -> questions, my saved answers, marked for review, time left
#   POST /api/v1/attempts/:token/answer  question_id, choice=A|B|C|D|SKIPPED, duration_seconds, marked=true|false (optional)
#   POST /api/v1/attempts/:token/mark    question_id, marked=true|false -> mark for review without answering
#   POST /api/v1/attempts/:token/finish
#   GET  /api/v1/attempts/:token/result                   -> marks, rank and answer review (after a strict test closes);
#                                                            for a retake: rank of the first attempt, retake: true, can_retake
#   POST /api/v1/attempts/:token/heartbeat                -> strict tests: the app is open (every 15 s)
#   POST /api/v1/attempts/:token/report_leave  seconds=12 kind=background|other_app_on_screen
#                                                         -> strict tests: the app was in the background, or another
#                                                            app had the screen (split screen, chat bubble...)
#
# Strict tests shuffle each question's options for each student: choices and answers use the letters the
# student sees, the server turns them into the question's own letters.
module Api
  module V1
    class AttemptsController < BaseController
      BLOCKED_MESSAGE = DashboardsController::BLOCKED_MESSAGE

      before_action :require_student!
      before_action :require_ready_account!
      before_action :set_attempt, except: [:practice, :index]
      before_action :stop_if_blocked, only: [:show, :answer, :mark, :finish, :result]
      before_action :stop_if_closed, only: [:show, :answer, :mark]

      def practice
        if current_user.free_tier?
          return render_error("upgrade_required",
                              "Free members practise the #{Tiers::FREE_SAMPLE_QUESTIONS} sample questions in the Question Bank. Join your school's plan (Plus) or become a Warrior to unlock more.",
                              status: :forbidden, upgrade: upgrade_json(current_user))
        end
        topic = params[:topic].to_s
        if topic.blank? || !Question.available_to(current_user).exists?(topic: topic)
          return render_error("empty", "That topic has no questions.", status: :not_found)
        end

        attempt = current_user.test_attempts.in_progress.find_by(topic: topic, test_session_id: nil) ||
                  current_user.test_attempts.create!(topic: topic)
        render json: { attempt_token: attempt.token, status: "in_progress" }
      end

      # Newest first, 30 a page (?page=2, ?kind=tests|practice), with marks and rank once results are out
      # (the same lines as the website's My Tests page, see AttemptSummary)
      PER_PAGE = 30

      def index
        page = [params[:page].to_i, 1].max
        scope = current_user.test_attempts.includes(:test_session).order(started_at: :desc, id: :desc)
        scope = scope.where.not(test_session_id: nil) if params[:kind] == "tests"
        scope = scope.where(test_session_id: nil) if params[:kind] == "practice"
        attempts = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
        rows = AttemptSummary.for(attempts.first(PER_PAGE))

        render json: {
          page: page,
          has_more: attempts.size > PER_PAGE,
          attempts: rows.map { |row| attempt_line_json(row) }
        }
      end

      def show
        @attempt.record_presence! if @attempt.strict?
        questions = @attempt.questions.to_a
        return render_error("empty", "This test has no questions yet.", status: :conflict) if questions.empty?

        by_id = questions.index_by(&:id)
        answers = @attempt.responses_by_question.filter_map do |qid, r|
          [qid.to_s, @attempt.shown_letter(by_id[qid], r.chosen_option)] if by_id[qid] # skips questions since removed
        end
        render json: {
          attempt: attempt_json(@attempt),
          questions: questions.each_with_index.map { |q, i| paper_question_json(q, i + 1) },
          answers: answers.to_h,
          marked: @attempt.marked_ids_in(questions)
        }
      end

      # One answer per question per attempt: answering again replaces it. Like the website, topic practice is
      # submitted once every question has an answer (or a skip); teacher tests wait for /finish or the time limit,
      # so students can go back over their answers ("all_answered" tells the app when everything is answered).
      def answer
        question = @attempt.questions.find_by(id: params[:question_id])
        return render_error("not_in_test", "That question is not part of this test.", status: :not_found) unless question

        shown = params[:choice].to_s.strip.upcase
        choice = shown == "SKIPPED" ? "SKIPPED" : @attempt.own_letter(question, shown)
        return render_error("no_choice", "Please select an option before submitting.") unless choice

        response = current_user.user_responses.find_or_initialize_by(question: question, test_session_token: @attempt.token)
        response.update!(chosen_option: choice,
                         is_correct: choice != "SKIPPED" && choice == question.correct_answer.to_s.strip.upcase,
                         duration_seconds: response.duration_seconds.to_i + params[:duration_seconds].to_i.clamp(0, 3600))
        @attempt.mark!(question, boolean_param(:marked)) if params.key?(:marked) && @attempt.test_session

        question_ids = @attempt.questions.pluck(:id)
        total = question_ids.size
        answered = @attempt.user_responses.where(question_id: question_ids).distinct.count(:question_id)
        all_answered = answered >= total
        @attempt.finish! if all_answered && @attempt.submits_when_all_answered?
        message =
          if @attempt.finished? then "All questions answered. Test submitted."
          elsif all_answered then "All questions answered. Go over your answers, then submit the test."
          end
        render json: { saved: true, answered: answered, total: total, all_answered: all_answered, finished: @attempt.finished?,
                       marked: @attempt.marked_ids_in(@attempt.questions.to_a), message: message }
      end

      # Mark for review on or off, without answering (teacher tests)
      def mark
        question = @attempt.questions.find_by(id: params[:question_id])
        return render_error("not_in_test", "That question is not part of this test.", status: :not_found) unless question
        return render_error("practice", "Marking for review is for teacher tests.", status: :unprocessable_entity) unless @attempt.test_session

        @attempt.mark!(question, params.key?(:marked) ? boolean_param(:marked) : true)
        render json: { marked: @attempt.marked_ids_in(@attempt.questions.to_a) }
      end

      def finish
        @attempt.finish!
        render json: { finished: true }
      end

      def result
        @attempt.finish! if @attempt.expired?
        return render_error("not_finished", "Finish the test to see your results.", status: :conflict) unless @attempt.finished?

        unless @attempt.results_released?
          return render json: { released: false, attempt: attempt_json(@attempt), release_at: time_json(@attempt.test_session.ends_at),
                                message: "Marks, rank and answers are shown after the test closes." }
        end

        questions = @attempt.questions.to_a
        responses = @attempt.responses_by_question
        summary = @attempt.score_summary
        rank = nil
        can_retake = false
        if (test = @attempt.test_session)
          # a retake is never ranked: show the rank the student's first attempt earned
          ranked = @attempt.retake? ? test.first_attempt_for(current_user) : @attempt
          ranking = test.rankings(for_attempt: ranked)
          mine = ranked && ranking.find { |r| r.attempt.id == ranked.id }
          rank = mine && { rank: mine.rank, of: ranking.size, from_first_attempt: @attempt.retake?, marks: mine.marks }
          can_retake = TestAttempt.latest_for(current_user, test)&.retake_allowed? || false
        end

        render json: {
          released: true,
          attempt: attempt_json(@attempt),
          summary: summary,
          rank: rank,
          can_retake: can_retake,
          review: questions.each_with_index.map do |q, i|
            mine = responses[q.id]
            paper_question_json(q, i + 1).merge(correct_answer: @attempt.shown_letter(q, q.correct_answer), explanation: q.explanation,
                                                my_choice: @attempt.shown_letter(q, mine&.chosen_option), correct: mine&.is_correct || false)
          end
        }
      end

      # ---------- strict mode ----------

      def heartbeat
        @attempt.enforce_presence!
        render json: strict_state(present: true)
      end

      # The app was in the background (or closed) for `seconds`; short absences are ignored
      def report_leave
        @attempt.enforce_presence!
        seconds = params[:seconds].to_i
        if seconds >= TestAttempt::AWAY_GRACE.to_i
          where = params[:kind] == "other_app_on_screen" ? "used another app on the screen" : "switched to another app"
          # open strict tests end here, and the student reads "…because you switched to another app for 12s"
          reason = @attempt.ends_on_leave? ? "#{where} for #{seconds}s" : "Left the test (#{where}) for #{seconds}s"
          @attempt.record_violation!(reason, left_at: seconds.seconds.ago)
        end
        render json: strict_state(present: true)
      end

      private

      def set_attempt
        @attempt = current_user.test_attempts.find_by!(token: params[:token])
      end

      # One line of the student's list of tests (website: My Tests)
      def attempt_line_json(row)
        a = row.attempt
        line = { token: a.token, title: a.title, kind: row.kind.to_s, status: attempt_status(a), state: row.status.to_s,
                 started_at: time_json(a.started_at), finished_at: time_json(a.finished_at),
                 results_released: a.results_released?, exam: exam_json(a.exam.code), retake: a.retake?,
                 retake_number: row.retake_number, ended_reason: a.ended_reason }
        case row.status
        when :in_progress
          answered, total = row.progress
          line.merge(answered: answered, total: total)
        when :waiting
          line.merge(release_at: time_json(row.release_at))
        when :done
          s = row.summary
          rank = row.rank
          line.merge(marks: s[:marks], max_marks: s[:max_marks], percentage: s[:percentage], correct: s[:correct],
                     total: s[:total], passed: s[:passed], rank: rank && { rank: rank.first, of: rank.last })
        else
          line
        end
      end

      # A question on this student's paper: options under the letters they see (shuffled on strict tests)
      def paper_question_json(question, number)
        question_json(question, number: number).merge(options: @attempt.options_for(question).to_h { |shown, _own, text| [shown, text] })
      end

      def boolean_param(key) = ActiveModel::Type::Boolean.new.cast(params[key]) || false

      def stop_if_blocked
        @attempt.enforce_presence!
        render_error("blocked", BLOCKED_MESSAGE, status: :conflict) if @attempt.blocked?
      end

      def stop_if_closed
        return if performed?
        if @attempt.finished?
          render_error("finished", @attempt.ended_message || "This test has already been submitted.", status: :conflict)
        elsif @attempt.expired?
          @attempt.finish!
          render_error("finished", "Time is up. Your test was submitted automatically.", status: :conflict)
        end
      end

      def attempt_json(attempt)
        test = attempt.test_session
        {
          token: attempt.token,
          title: attempt.title,
          kind: test ? "test" : "practice",
          test_id: test&.id,
          exam: exam_json(attempt.exam.code),
          status: attempt_status(attempt),
          retake: attempt.retake?,
          strict: attempt.strict?,
          # strict open tests: leaving ends the test (no warning); strict PIN tests warn, then block
          ends_on_leave: attempt.ends_on_leave?,
          ended_early: attempt.ended_early?,
          ended_message: attempt.ended_message,
          submits_when_all_answered: attempt.submits_when_all_answered?,
          started_at: time_json(attempt.started_at),
          deadline_at: time_json(attempt.deadline_at),
          seconds_left: attempt.seconds_left,
          leave_count: attempt.leave_count,
          warnings_left: attempt.warnings_left,
          heartbeat_every: TestAttempt::HEARTBEAT_EVERY.to_i,
          away_grace: TestAttempt::AWAY_GRACE.to_i
        }
      end

      def strict_state(present:)
        if @attempt.blocked?
          { status: "blocked", message: BLOCKED_MESSAGE }
        elsif @attempt.finished? || @attempt.expired?
          { status: "finished", message: @attempt.ended_message }.compact
        else
          @attempt.record_presence! if present && @attempt.strict?
          { status: "ok", leave_count: @attempt.leave_count, warnings_left: @attempt.warnings_left }
        end
      end
    end
  end
end
