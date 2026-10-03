# JSON API for the Lakshyank mobile app.
#
# Signing in (POST /api/v1/session) returns a token. Every other request sends it as
#   Authorization: Bearer <token>
# The token is a signed id of a normal Session row, so signing out (or an admin deleting the
# user's sessions) ends it, exactly like on the website.
#
# Errors always look like { "error": { "code": "pin_required", "message": "..." } } so the app can
# react to the code and show the message.
module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::RateLimiting unless include?(ActionController::RateLimiting)

      TOKEN_PURPOSE = :api

      before_action :authenticate!

      rescue_from ActiveRecord::RecordNotFound do
        render_error "not_found", "Not found.", status: :not_found
      end
      rescue_from ActionController::ParameterMissing do |e|
        render_error "bad_request", e.message, status: :bad_request
      end
      rescue_from ActiveRecord::RecordInvalid do |e|
        render_error "invalid", e.record.errors.full_messages.to_sentence
      end

      private

      # ---------- authentication ----------

      def authenticate!
        token = request.authorization.to_s[/\ABearer\s+(.+)\z/, 1]
        api_session = token.present? ? Session.find_signed(token, purpose: TOKEN_PURPOSE) : nil
        return render_error("unauthorized", "Please sign in again.", status: :unauthorized) unless api_session

        Current.session = api_session
      end

      def current_user = Current.user

      # Same checks the website makes after login; the app sends the user to the website to finish them
      def require_ready_account!
        issue = account_issue(current_user)
        render_error(issue[:code], issue[:message], status: :forbidden) if issue
      end

      def require_student!
        return if performed?
        render_error("students_only", "This part of the app is for students.", status: :forbidden) unless current_user.student?
      end

      def require_faculty!
        return if performed?
        render_error("teachers_only", "Only approved teachers and admins can do this.", status: :forbidden) unless current_user.faculty?
      end

      def account_issue(user)
        if user.missing_profile_items.any?
          { code: "profile_incomplete", message: "Please add #{user.missing_profile_items.to_sentence} to continue." }
        elsif user.needs_parent_consent?
          { code: "parent_consent_needed", message: "Students under 18 need a parent's consent. Finish this on the Lakshyank website." }
        elsif user.pending_teacher?
          { code: "pending_approval", message: "Your teacher account is waiting for approval by the Lakshyank admin." }
        end
      end

      # ---------- responses ----------

      def render_error(code, message, status: :unprocessable_entity, **extra)
        render json: { error: { code: code, message: message }.merge(extra) }, status: status
      end

      def time_json(value) = value&.iso8601

      def exam_json(code)
        exam = Exam.find(code)
        { code: exam.code, name: exam.name, marking: exam.marking_text }
      end

      def user_json(user)
        {
          id: user.id,
          name: user.display_name,
          email_address: user.email_address,
          role: user.role,
          faculty: user.faculty?,
          approved: user.approved?,
          tier: user.student? ? user.tier : nil,
          tier_label: user.student? ? Tiers.label(user.tier) : nil,
          exam_codes: user.exam_codes,
          target_exam: user.target_exam,
          ranking_exam: user.student? ? user.ranking_exam_code : nil,
          subjects: user.subject_names,
          email_confirmed: user.email_confirmed?,
          account_issue: account_issue(user),
          # push notification switches (students) and the Firebase topics the phone should subscribe to
          notifications: { new_tests: user.push_new_tests?, results: user.push_results?, reminders: user.push_reminders? },
          push_topics: user.push_topics
        }
      end

      def attempt_status(attempt)
        return nil unless attempt
        if attempt.blocked? then "blocked"
        elsif attempt.finished? || attempt.expired? then "finished"
        else "in_progress"
        end
      end

      # Cards for a list of tests (a few queries in total, like the website's test cards)
      def test_cards(tests)
        ids = tests.map(&:id)
        # the latest attempt per test (a retake once the student has retaken it)
        attempts = current_user.test_attempts.where(test_session_id: ids).order(:id).index_by(&:test_session_id)
        attempt_counts = current_user.test_attempts.where(test_session_id: ids).group(:test_session_id).count
        open_ids = TestSession.available_to(current_user).where(id: ids).pluck(:id).to_set
        subjects = TestQuestion.joins(:question).where(test_session_id: ids).distinct.order("questions.topic")
                               .pluck(:test_session_id, "questions.topic")
                               .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(id, topic), h| h[id] << topic if topic.present? }
        tests.map do |t|
          test_card(t, attempt: attempts[t.id], locked: !attempts[t.id] && !open_ids.include?(t.id), subjects: subjects[t.id],
                       attempt_count: attempt_counts[t.id].to_i)
        end
      end

      # my_attempt is the student's latest attempt. can_retake: they may start another (practice) attempt;
      # retake: this attempt is one (only the first attempt is ranked).
      def test_card(test, attempt:, locked:, subjects:, attempt_count: nil)
        {
          id: test.id,
          title: test.title,
          exam: exam_json(test.exam_type),
          duration_minutes: test.duration_minutes,
          pass_mark_percentage: test.pass_mark_percentage,
          access: test.access_type,
          strict: test.strict_mode?,
          strict_ends_on_leave: test.ends_on_leave?, # strict open test: leaving ends it (PIN tests warn, then block)
          starts_at: time_json(test.starts_at),
          ends_at: time_json(test.ends_at),
          window: test.window_status.to_s,
          author: test.author_name,
          audience: test.audience_label,
          free_sample: test.free_sample?,
          locked: locked,
          subjects: subjects,
          my_attempt: attempt && { token: attempt.token, status: attempt_status(attempt), results_released: attempt.results_released?,
                                   retake: attempt.retake?, can_retake: attempt.retake_allowed?,
                                   attempt_count: attempt_count || current_user.test_attempts.where(test_session: test).count }
        }
      end

      # What unlocks a test the student cannot take yet
      def upgrade_json(user)
        if user.free_tier?
          { tier: "free",
            message: "You're on the free trial: only the #{Tiers::FREE_SAMPLE_TESTS} sample tests and #{Tiers::FREE_SAMPLE_QUESTIONS} sample questions are included.",
            options: ["⭐ Plus — free through your school's plan: school tests and public tests in your exams.",
                      "⚔️ Warrior — every exam, all public tests and practice."] }
        else
          covered = user.allowed_exam_codes.map { |c| Exam.name_for(c) }.to_sentence.presence || "your school's exams"
          { tier: user.tier,
            message: "Your #{Tiers.name(user.tier)} plan covers #{covered}.",
            options: ["⚔️ Warrior — every exam, all public tests and practice."] }
        end
      end

      def not_available_message
        case current_user.tier
        when "free" then "Free members can take the #{Tiers::FREE_SAMPLE_TESTS} sample tests. Join your school's plan (Plus) or become a Warrior to unlock more."
        when "plus" then "This test is for an exam outside your school's plan. Become a Warrior to take every exam."
        else "That test is not available to you."
        end
      end

      # A question as a student sees it before answering: no correct answer
      def question_json(question, number: nil)
        { id: question.id, number: number, topic: question.topic, exam: question.exam_type, year: question.year,
          content: question.content,
          options: { "A" => question.option_a, "B" => question.option_b, "C" => question.option_c, "D" => question.option_d } }
      end
    end
  end
end
