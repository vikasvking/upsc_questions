# Student home screen data (same numbers as the website's dashboard).
#   GET /api/v1/dashboard            -> streak, week, accuracy, latest tests, rank card
#   GET /api/v1/leaderboard?exam=... -> "You vs Toppers" for one exam
#   GET /api/v1/membership           -> tier, what it includes, how to get more
module Api
  module V1
    class DashboardController < BaseController
      DAILY_TARGET = 25 # answers a day that count toward the streak (as on the website)

      before_action :require_student!
      before_action :require_ready_account!

      def show
        user = current_user
        responses = user.user_responses
        bank_total = Question.available_to(user).count
        attempted = responses.distinct.count(:question_id)
        answered = responses.where.not(chosen_option: "SKIPPED").count

        latest = TestSession.visible_to(user).includes(:user, :institution, :audience_grants)
                            .where("test_sessions.ends_at IS NULL OR test_sessions.ends_at > ?", Time.current)
        latest = latest.where(exam_type: user.exam_codes) if user.exam_codes.any?

        render json: {
          user: user_json(user),
          streak_days: streak_days,
          daily_target: DAILY_TARGET,
          week: week,
          stats: {
            bank_total: bank_total,
            solved: responses.where(is_correct: true).distinct.count(:question_id),
            wrong: responses.where(is_correct: false).where.not(chosen_option: "SKIPPED").distinct.count(:question_id),
            completion_pct: bank_total.positive? ? (attempted * 100.0 / bank_total).round : 0,
            accuracy_pct: answered.positive? ? (responses.where(is_correct: true).count * 100.0 / answered).round(1) : 0.0
          },
          latest_tests: test_cards(latest.newest_first.limit(3).to_a),
          rank: comparison_json(user.ranking_exam_code)
        }
      end

      def leaderboard
        code = Exam.normalize(params[:exam]) || current_user.ranking_exam_code
        exams = Exam.codes & ([current_user.target_exam] + current_user.exam_codes + current_user.practised_exam_codes)
        render json: { exams: exams.map { |c| exam_json(c) }, rank: comparison_json(code) }
      end

      def membership
        user = current_user
        samples = TestSession.where(free_sample: true)
        warrior = Plan.warrior
        render json: {
          tier: user.tier,
          tier_label: Tiers.label(user.tier),
          tier_until: user.tier_until&.iso8601,
          allowed_exams: user.allowed_exam_codes.map { |c| Exam.name_for(c) },
          sample_tests: { taken: user.test_attempts.where(test_session_id: samples.select(:id)).distinct.count(:test_session_id), total: samples.count },
          sample_questions: { answered: user.user_responses.joins(:question).where(questions: { free_sample: true }).distinct.count(:question_id),
                              total: Question.where(free_sample: true).count },
          schools: user.subscribed_institutions.map { |i| { id: i.id, name: i.name, plan: i.plan&.name } },
          plans: [
            { key: "free", name: "Free", price: "₹0", points: ["#{Tiers::FREE_SAMPLE_TESTS} sample tests", "#{Tiers::FREE_SAMPLE_QUESTIONS} sample practice questions", "Each only once"] },
            { key: "plus", name: "Plus", price: "Through your school", points: ["Your school's tests", "Public tests and practice in your exams"] },
            { key: "warrior", name: "Warrior",
              price: warrior ? "₹#{warrior.price_month_inr}/month or ₹#{warrior.price_year_inr}/year" : "Coming soon",
              points: ["Every exam: UPSC, JEE, NEET, SSC, IBPS, CBSE", "All public tests and practice", "Everything in Plus"] }
          ],
          how_to_upgrade: "Online payment is coming soon. To become a Warrior now, contact the Lakshyank admin. For Plus, ask your school to join Lakshyank."
        }
      end

      private

      def comparison_json(code)
        c = Leaderboard.comparison_for(current_user, code)
        metrics = Leaderboard::METRICS.map do |key, label, better|
          { key: key, label: label, better: better, me: c[:me].public_send(key), top: c[:top][key], platform: c[:platform][key] }
        end
        { exam: exam_json(code), rank: c[:rank], students: c[:students], top_count: c[:top_count], metrics: metrics }
      end

      # The last 7 days, oldest first
      def week
        counts = current_user.user_responses.where(created_at: 6.days.ago.beginning_of_day..).pluck(:created_at)
                             .group_by(&:to_date).transform_values(&:size)
        (0..6).to_a.reverse.map do |offset|
          day = Date.current - offset
          solved = counts[day].to_i
          { date: day.iso8601, day_name: day.strftime("%a"), solved: solved, target_met: solved >= DAILY_TARGET, today: day == Date.current }
        end
      end

      # Consecutive days (ending today or yesterday) with DAILY_TARGET+ answers
      def streak_days
        daily = current_user.user_responses
                            .where(created_at: 400.days.ago.beginning_of_day..)
                            .group("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{Time.zone.tzinfo.name}')")
                            .count
                            .transform_keys(&:to_date)
        day = Date.current
        day -= 1 if daily[day].to_i < DAILY_TARGET
        streak = 0
        while daily[day].to_i >= DAILY_TARGET
          streak += 1
          day -= 1
        end
        streak
      end
    end
  end
end
