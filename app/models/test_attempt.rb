# app/models/test_attempt.rb
# One student's run through either a practice topic or a teacher's test.
class TestAttempt < ApplicationRecord
  GRACE_PERIOD = 30.seconds # allows for slow networks on the final auto-submit

  belongs_to :user
  belongs_to :test_session, optional: true
  has_many :user_responses, primary_key: :token, foreign_key: :test_session_token, inverse_of: false

  validates :token, presence: true, uniqueness: true
  validate  :topic_or_test_present

  before_validation :set_defaults, on: :create

  scope :finished,    -> { where.not(finished_at: nil) }
  scope :in_progress, -> { where(finished_at: nil) }

  def questions
    if test_session
      test_session.ordered_questions
    else
      Question.where(topic: topic).in_order
    end
  end

  def title
    test_session ? test_session.title : topic
  end

  def finished? = finished_at.present?
  def timed?    = deadline_at.present?

  def expired?(now = Time.current)
    timed? && now > deadline_at + GRACE_PERIOD
  end

  def seconds_left(now = Time.current)
    return nil unless timed?
    [(deadline_at - now).to_i, 0].max
  end

  def finish!
    update!(finished_at: [Time.current, deadline_at].compact.min) unless finished?
  end

  # Latest answer for each question in this attempt, keyed by question_id
  def responses_by_question
    user_responses.order(:updated_at).index_by(&:question_id)
  end

  # UPSC-style marking used for ranking inside a teacher test
  MARKS_CORRECT = 2.0
  MARKS_WRONG   = -2.0 / 3 # one third of the marks for a correct answer

  def self.marks_for(correct, wrong)
    (correct * MARKS_CORRECT + wrong * MARKS_WRONG).round(2)
  end

  # Seconds from Start to Submit
  def time_taken
    return nil unless finished_at
    (finished_at - started_at).to_i
  end

  def score_summary
    question_ids = questions.pluck(:id)
    total     = question_ids.size
    # ignore answers to questions a teacher later removed from the test
    responses = responses_by_question.values_at(*question_ids).compact
    correct   = responses.count(&:is_correct)
    skipped   = responses.count { |r| r.chosen_option == "SKIPPED" }
    wrong     = responses.size - correct - skipped
    pct       = total.positive? ? (correct * 100.0 / total).round(1) : 0.0
    passed    = test_session ? pct >= test_session.pass_mark_percentage : nil

    { total: total, correct: correct, wrong: wrong, skipped: skipped,
      unattempted: total - responses.size, percentage: pct, passed: passed,
      marks: self.class.marks_for(correct, wrong), max_marks: (total * MARKS_CORRECT).round(2),
      time_taken: time_taken }
  end

  private

  def set_defaults
    self.token      ||= SecureRandom.hex(8)
    self.started_at ||= Time.current

    if test_session && deadline_at.nil?
      limits = [started_at + test_session.duration_minutes.to_i.minutes, test_session.ends_at].compact
      self.deadline_at = limits.min
    end
  end

  def topic_or_test_present
    errors.add(:base, "Attempt needs a topic or a test") if topic.blank? && test_session_id.blank?
  end
end
