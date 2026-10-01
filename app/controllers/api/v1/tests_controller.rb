# Teacher tests, as students see them (same rules as the website's "All Tests" and test pages).
#   GET  /api/v1/tests?exam=mine|all|UPSC_PRELIMS -> every test the student can see; 🔒 locked = outside their tier
#   GET  /api/v1/tests/:id                        -> details, whether a PIN is needed, upgrade options when locked
#   POST /api/v1/tests/verify_pin  pin_code=...   -> unlocks a PIN test for this student
#   POST /api/v1/tests/:id/start                  -> { attempt_token } (new or resumed)
#   POST /api/v1/tests/:id/start  retake=true     -> a new practice attempt at a submitted test (my_attempt.can_retake);
#                                                    only the first attempt is ranked
module Api
  module V1
    class TestsController < BaseController
      BLOCKED_MESSAGE = DashboardsController::BLOCKED_MESSAGE

      before_action :require_student!
      before_action :require_ready_account!

      rate_limit to: 10, within: 5.minutes, only: :verify_pin,
                 with: -> { render_error("rate_limited", "Too many attempts. Try again in a few minutes.", status: :too_many_requests) }

      def index
        user = current_user
        my_exams = user.exam_codes
        choice = params[:exam].presence || (my_exams.any? ? "mine" : "all")
        exam = Exam.normalize(choice)

        scope = TestSession.visible_to(user).includes(:user, :institution, :audience_grants)
        scope =
          if exam then scope.where(exam_type: exam)
          elsif choice == "mine" && my_exams.any? then scope.where(exam_type: my_exams)
          else scope
          end

        # Live first, then opening soon, then closed; newest first inside each group
        order = { live: 0, upcoming: 1, closed: 2 }
        tests = scope.newest_first.limit(300).to_a.sort_by.with_index { |t, i| [order[t.window_status], i] }
        used = TestSession.visible_to(user).distinct.pluck(:exam_type)
        render json: { exam: choice, exam_options: (Exam.codes & used).map { |c| exam_json(c) }, tests: test_cards(tests) }
      end

      def show
        test = TestSession.visible_to(current_user).find(params[:id])
        attempt = TestAttempt.latest_for(current_user, test)
        attempt&.enforce_presence!
        locked = !attempt && !TestSession.available_to(current_user).exists?(test.id)
        rating = Rating.summary_for(test)

        render json: {
          test: test_card(test, attempt: attempt, locked: locked, subjects: test.questions.where.not(topic: [nil, ""]).distinct.order(:topic).pluck(:topic)).merge(
            question_count: test.questions.count,
            needs_pin: !locked && !can_access?(test),
            rating: rating.count.positive? ? { average: rating.average&.round(1), count: rating.count } : nil
          ),
          upgrade: locked ? upgrade_json(current_user) : nil,
          blocked_message: attempt&.blocked? ? BLOCKED_MESSAGE : nil
        }
      end

      # A PIN from the teacher. Remembered as a TestPinEntry (which also shows the student on the teacher's live panel).
      def verify_pin
        test = TestSession.visible_to(current_user).find_by(pin_code: params[:pin_code].to_s.strip.upcase)
        unless test && test.questions.exists?
          return render_error("invalid_pin", "Invalid PIN. Please check it with your teacher.", status: :not_found)
        end

        locked = !TestSession.available_to(current_user).exists?(test.id)
        TestPinEntry.create_or_find_by!(test_session: test, user: current_user) unless locked
        render json: { test_id: test.id, title: test.title, locked: locked }
      end

      def start
        test = TestSession.available_to(current_user).find_by(id: params[:id])
        unless test
          TestSession.visible_to(current_user).find(params[:id]) # 404 when the student cannot even see it
          return render_error("upgrade_required", not_available_message, status: :forbidden, upgrade: upgrade_json(current_user))
        end
        unless can_access?(test)
          return render_error("pin_required", "This test needs a PIN. Enter the code from your teacher.", status: :forbidden)
        end

        existing = TestAttempt.latest_for(current_user, test)
        existing&.enforce_presence!
        return render_error("blocked", BLOCKED_MESSAGE, status: :conflict) if existing&.blocked?
        if existing&.finished? || existing&.expired?
          existing.finish!
          return start_retake(test, existing) if ActiveModel::Type::Boolean.new.cast(params[:retake])
          return render json: { attempt_token: existing.token, status: "finished", can_retake: existing.retake_allowed?,
                                message: "You have already submitted this test." }
        end
        return render json: { attempt_token: existing.token, status: "in_progress", retake: existing.retake?, message: "Resuming your test." } if existing

        case test.window_status
        when :upcoming
          return render_error("not_open", "This test opens at #{I18n.l(test.starts_at, format: :long)}.", status: :conflict)
        when :closed
          return render_error("closed", "This test closed at #{I18n.l(test.ends_at, format: :long)}.", status: :conflict)
        end
        return render_error("empty", "This test has no questions yet.", status: :conflict) if test.questions.none?

        attempt = TestAttempt.start_first_try!(current_user, test)
        render json: { attempt_token: attempt.token, status: "in_progress" }, status: :created
      end

      private

      # Another go at a submitted test: practice, never ranked (the first attempt keeps the rank)
      def start_retake(test, previous)
        unless previous.retake_allowed?
          return render_error("retake_not_open", "You can retake this test after it closes at #{I18n.l(test.ends_at, format: :long)}.",
                              status: :conflict)
        end
        return render_error("empty", "This test has no questions yet.", status: :conflict) if test.questions.none?

        attempt = current_user.test_attempts.create!(test_session: test, retake: true)
        render json: { attempt_token: attempt.token, status: "in_progress", retake: true,
                       message: "Retake started. This is practice: your rank stays from your first attempt." }, status: :created
      end

      # Open tests: anyone. PIN tests: after the student entered the PIN (here or on the website).
      def can_access?(test)
        test.open_access? ||
          current_user.test_pin_entries.exists?(test_session: test) ||
          current_user.test_attempts.exists?(test_session: test)
      end
    end
  end
end
