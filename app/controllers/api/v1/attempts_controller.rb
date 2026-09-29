# Taking a test or a topic practice, and its result (same rules as the website's test pages).
#   POST /api/v1/practice  topic=Physics                  -> { attempt_token } (Plus and Warrior)
#   GET  /api/v1/attempts                                 -> my recent tests and practices
#   GET  /api/v1/attempts/:token                          -> questions, my saved answers, time left
#   POST /api/v1/attempts/:token/answer  question_id, choice=A|B|C|D|SKIPPED, duration_seconds
#   POST /api/v1/attempts/:token/finish
#   GET  /api/v1/attempts/:token/result                   -> marks, rank and answer review (after a strict test closes);
#                                                            for a retake: rank of the first attempt, retake: true, can_retake
#   POST /api/v1/attempts/:token/heartbeat                -> strict tests: the app is open (every 15 s)
#   POST /api/v1/attempts/:token/report_leave  seconds=12 -> strict tests: the app was in the background
module Api
  module V1
    class AttemptsController < BaseController
      BLOCKED_MESSAGE = DashboardsController::BLOCKED_MESSAGE

      before_action :require_student!
      before_action :require_ready_account!
      before_action :set_attempt, except: [:practice, :index]
      before_action :stop_if_blocked, only: [:show, :answer, :finish, :result]
      before_action :stop_if_closed, only: [:show, :answer]

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

      def index
        attempts = current_user.test_attempts.includes(:test_session).order(started_at: :desc).limit(30)
        render json: {
          attempts: attempts.map do |a|
            { token: a.token, title: a.title, kind: a.test_session ? "test" : "practice", status: attempt_status(a),
              started_at: time_json(a.started_at), finished_at: time_json(a.finished_at),
              results_released: a.results_released?, exam: exam_json(a.exam.code), retake: a.retake? }
          end
        }
      end

      def show
        @attempt.record_presence! if @attempt.strict?
        questions = @attempt.questions.to_a
        return render_error("empty", "This test has no questions yet.", status: :conflict) if questions.empty?

        answers = @attempt.responses_by_question.transform_values(&:chosen_option)
        render json: {
          attempt: attempt_json(@attempt),
          questions: questions.each_with_index.map { |q, i| question_json(q, number: i + 1) },
          answers: answers.transform_keys(&:to_s)
        }
      end

      # One answer per question per attempt: answering again replaces it. Like the website, the
      # test is submitted as soon as every question has an answer (or a skip).
      def answer
        question = @attempt.questions.find_by(id: params[:question_id])
        return render_error("not_in_test", "That question is not part of this test.", status: :not_found) unless question

        choice = params[:choice].to_s.strip.upcase
        unless Question::ANSWER_KEYS.include?(choice) || choice == "SKIPPED"
          return render_error("no_choice", "Please select an option before submitting.")
        end

        response = current_user.user_responses.find_or_initialize_by(question: question, test_session_token: @attempt.token)
        response.update!(chosen_option: choice,
                         is_correct: choice != "SKIPPED" && choice == question.correct_answer.to_s.strip.upcase,
                         duration_seconds: response.duration_seconds.to_i + params[:duration_seconds].to_i.clamp(0, 3600))

        question_ids = @attempt.questions.pluck(:id)
        total = question_ids.size
        answered = @attempt.user_responses.where(question_id: question_ids).distinct.count(:question_id)
        @attempt.finish! if answered >= total
        render json: { saved: true, answered: answered, total: total, finished: @attempt.finished?,
                       message: (@attempt.finished? ? "All questions answered. Test submitted." : nil) }
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
          ranking = test.rankings
          # a retake is never ranked: show the rank the student's first attempt earned
          ranked = @attempt.retake? ? test.first_attempt_for(current_user) : @attempt
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
            question_json(q, number: i + 1).merge(correct_answer: q.correct_answer, explanation: q.explanation,
                                                  my_choice: mine&.chosen_option, correct: mine&.is_correct || false)
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
          @attempt.record_violation!("Left the test (switched to another app) for #{seconds}s")
        end
        render json: strict_state(present: true)
      end

      private

      def set_attempt
        @attempt = current_user.test_attempts.find_by!(token: params[:token])
      end

      def stop_if_blocked
        @attempt.enforce_presence!
        render_error("blocked", BLOCKED_MESSAGE, status: :conflict) if @attempt.blocked?
      end

      def stop_if_closed
        return if performed?
        if @attempt.finished?
          render_error("finished", "This test has already been submitted.", status: :conflict)
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
          { status: "finished" }
        else
          @attempt.record_presence! if present && @attempt.strict?
          { status: "ok", leave_count: @attempt.leave_count, warnings_left: @attempt.warnings_left }
        end
      end
    end
  end
end
