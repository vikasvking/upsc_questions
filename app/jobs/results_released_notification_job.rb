# "Results are out" push notification for strict tests, whose marks and ranks stay hidden until they close.
# Every 5 minutes (config/recurring.yml): each strict test that closed in the last day and was not announced yet
# notifies the students who submitted it (first attempts, not blocked), with their rank.
class ResultsReleasedNotificationJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    TestSession.where(strict_mode: true, results_notified_at: nil, ends_at: (now - 1.day)..now).find_each do |test|
      test.update_column(:results_notified_at, now) # at most once

      ranking = test.rankings.index_by { |r| r.user.id }
      next if ranking.empty?

      PushNotifier.to_users(ranking.keys, pref: :push_results) do |user|
        result = ranking[user.id]
        {
          title: "Results are out: #{test.title}",
          body: "You ranked ##{result.rank} of #{ranking.size} with #{format_marks(result.marks)} / #{format_marks(result.max_marks)} marks. " \
                "Tap to see your answers.",
          data: { type: "result", token: result.attempt.token, test_id: test.id }
        }
      end
    end
  end

  private

  def format_marks(value) = value.to_f == value.to_i ? value.to_i.to_s : value.round(2).to_s
end
