# "New test" push notification, a minute after a teacher creates a test (see TestSession).
# Public open tests go to their exam's Firebase topic; school and selected tests to each student it is for.
class NewTestNotificationJob < ApplicationJob
  queue_as :default
  background_switch :new_test_notifications # on/off on Admin → Background work

  def perform(test_id)
    test = TestSession.find_by(id: test_id)
    return unless test && test.new_test_notified_at.nil?
    return if test.questions.none? || (test.ends_at && test.ends_at <= Time.current)

    test.update_column(:new_test_notified_at, Time.current) # at most once, even if the job runs twice

    title = "New test: #{test.title}"
    body = [
      "#{test.author_name} · #{Exam.find(test.exam_type).name} · #{test.duration_minutes} min",
      when_line(test)
    ].compact.join(". ")
    data = { type: "test", test_id: test.id }

    if (topic = test.push_topic)
      PushNotifier.to_topic(topic, title: title, body: body, data: data)
    else
      PushNotifier.to_users(test.push_recipient_ids, pref: :push_new_tests, title: title, body: body, data: data)
    end
  end

  private

  def when_line(test)
    if test.starts_at && test.starts_at > Time.current
      "Opens #{I18n.l(test.starts_at, format: :short)}"
    elsif test.ends_at
      "Open now, until #{I18n.l(test.ends_at, format: :short)}"
    else
      "Open now"
    end
  end
end
