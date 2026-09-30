require "test_helper"

# Push notifications are collected in PushNotifier.deliveries in tests (nothing is sent to Firebase)
class PushNotificationsTest < ActiveJob::TestCase
  setup do
    PushNotifier.deliveries.clear
    @phone_one = DeviceToken.register!(users(:one), "token-one")
    @phone_two = DeviceToken.register!(users(:two), "token-two")
  end

  def new_test(**attrs)
    TestSession.create!({ user: users(:teacher), title: "Weekly Polity", exam_type: "UPSC_PRELIMS", duration_minutes: 30,
                          pass_mark_percentage: 40, access_type: "open", question_ids: [questions(:one).id] }.merge(attrs))
  end

  test "creating a test queues the announcement a minute later" do
    assert_enqueued_with(job: NewTestNotificationJob) { new_test }
  end

  test "a public open test goes to its exam's topic, once" do
    test = new_test
    NewTestNotificationJob.perform_now(test.id)
    NewTestNotificationJob.perform_now(test.id)

    assert_equal 1, PushNotifier.deliveries.size
    sent = PushNotifier.deliveries.first
    assert_equal "tests_UPSC_PRELIMS", sent.topic
    assert_equal "New test: Weekly Polity", sent.title
    assert_equal({ "type" => "test", "test_id" => test.id.to_s }, sent.data)
  end

  test "free sample tests go to every student of the exam; public PIN tests are not announced" do
    sample = new_test(free_sample: true)
    NewTestNotificationJob.perform_now(sample.id)
    assert_equal ["all_UPSC_PRELIMS"], PushNotifier.deliveries.map(&:topic)

    PushNotifier.deliveries.clear
    pin_test = new_test(access_type: "pin")
    NewTestNotificationJob.perform_now(pin_test.id)
    assert_empty PushNotifier.deliveries
  end

  test "a school test goes only to that school's students who have the app, unless they turned it off" do
    school = Institution.create!(name: "Sunrise Academy", kind: "school")
    Membership.create!(user: users(:one), institution: school, status: "approved")
    Membership.create!(user: users(:teacher), institution: school, status: "approved")

    test = new_test(visibility: "institution", institution: school)
    NewTestNotificationJob.perform_now(test.id)
    assert_equal ["token-one"], PushNotifier.deliveries.map(&:token) # not student two, not the teacher

    PushNotifier.deliveries.clear
    users(:one).update!(push_new_tests: false)
    NewTestNotificationJob.perform_now(new_test(visibility: "institution", institution: school, title: "Another").id)
    assert_empty PushNotifier.deliveries
  end

  test "strict test results are announced once, after the test closes, with each student's rank" do
    strict = test_sessions(:two) # PIN test with one question
    strict.update!(strict_mode: true, ends_at: 1.hour.from_now)
    best = users(:one).test_attempts.create!(test_session: strict, started_at: 50.minutes.ago)
    users(:one).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, test_session_token: best.token)
    best.update!(finished_at: 40.minutes.ago)
    users(:two).test_attempts.create!(test_session: strict, started_at: 50.minutes.ago).update!(finished_at: 30.minutes.ago)

    ResultsReleasedNotificationJob.perform_now # still open: nothing yet
    assert_empty PushNotifier.deliveries

    travel 2.hours do
      ResultsReleasedNotificationJob.perform_now
      ResultsReleasedNotificationJob.perform_now
    end
    assert_equal %w[token-one token-two], PushNotifier.deliveries.map(&:token).sort
    mine = PushNotifier.deliveries.find { |d| d.token == "token-one" }
    assert_match "You ranked #1 of 2", mine.body
    assert_equal({ "type" => "result", "token" => best.token, "test_id" => strict.id.to_s }, mine.data)
  end

  test "the evening reminder goes to active students short of today's target" do
    users(:one).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true, created_at: 2.days.ago)
    users(:one).user_responses.create!(question: questions(:two), chosen_option: "B", is_correct: true)
    # student two practised today and already met the target
    DailyPracticeReminderJob::DAILY_TARGET.times do
      users(:two).user_responses.create!(question: questions(:one), chosen_option: "A", is_correct: true)
    end

    DailyPracticeReminderJob.perform_now
    assert_equal ["token-one"], PushNotifier.deliveries.map(&:token)
    assert_match "You've answered 1 of #{DailyPracticeReminderJob::DAILY_TARGET} today", PushNotifier.deliveries.first.body

    PushNotifier.deliveries.clear
    users(:one).update!(push_reminders: false)
    DailyPracticeReminderJob.perform_now
    assert_empty PushNotifier.deliveries
  end

  test "topics follow the student's exams, tier and switch" do
    assert_equal %w[all_UPSC_PRELIMS tests_UPSC_PRELIMS], users(:one).push_topics # Warrior
    users(:one).update!(membership_tier: "free")
    assert_equal %w[all_UPSC_PRELIMS], users(:one).reload.push_topics
    users(:one).update!(push_new_tests: false)
    assert_empty users(:one).push_topics
    assert_empty users(:teacher).push_topics
  end
end
