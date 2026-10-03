# Evening reminder to keep the streak going (7 PM India time, config/recurring.yml).
# Goes to Plus and Warrior students who practised in the last two weeks and have not yet answered
# today's target of questions. Free students are left out: they only have the few sample questions.
class DailyPracticeReminderJob < ApplicationJob
  queue_as :default
  background_switch :daily_practice_reminder # on/off on Admin → Background work

  DAILY_TARGET = Api::V1::DashboardController::DAILY_TARGET
  ACTIVE_WITHIN = 14.days

  def perform(now = Time.current)
    active_ids = UserResponse.where(created_at: (now - ACTIVE_WITHIN)..now).distinct.pluck(:user_id)
    return if active_ids.empty?

    today = UserResponse.where(user_id: active_ids, created_at: now.all_day).group(:user_id).count
    candidates = User.student.where(id: active_ids, push_reminders: true).where(id: DeviceToken.select(:user_id))
                     .reject(&:free_tier?)
                     .select { |u| today[u.id].to_i < DAILY_TARGET }
    return if candidates.empty?

    PushNotifier.to_users(candidates.map(&:id), pref: :push_reminders) do |user|
      done = today[user.id].to_i
      left = DAILY_TARGET - done
      {
        title: done.zero? ? "Time for today's practice 📚" : "#{left} more to go today 🔥",
        body: done.zero? ? "#{DAILY_TARGET} questions a day keep your streak going. Start now?"
                         : "You've answered #{done} of #{DAILY_TARGET} today. Finish the rest to keep your streak.",
        data: { type: "practice" }
      }
    end
  end
end
