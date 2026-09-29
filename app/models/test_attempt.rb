# app/models/test_attempt.rb
# One student's run through either a practice topic or a teacher's test.
class TestAttempt < ApplicationRecord
  GRACE_PERIOD = 30.seconds # allows for slow networks on the final auto-submit

  # Strict mode (see TestSession#strict_mode)
  HEARTBEAT_EVERY  = 15.seconds # how often the test page pings the server while visible
  LEAVE_TIMEOUT    = 90.seconds # no ping for this long = the student left (closed the tab, locked the phone...)
  AWAY_GRACE       = 5.seconds  # being away for less than this is ignored (page refresh, a quick glance)
  WARNINGS_ALLOWED = 1          # leaves that only warn; the next one blocks

  belongs_to :user
  belongs_to :test_session, optional: true
  has_many :user_responses, primary_key: :token, foreign_key: :test_session_token, inverse_of: false

  validates :token, presence: true, uniqueness: true
  validate  :topic_or_test_present

  before_validation :set_defaults, on: :create

  scope :finished,    -> { where.not(finished_at: nil) }
  scope :in_progress, -> { where(finished_at: nil) }
  scope :blocked,     -> { where.not(blocked_at: nil) }
  scope :not_blocked, -> { where(blocked_at: nil) }

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
  def strict?   = test_session&.strict_mode? || false
  def blocked?  = blocked_at.present?

  # ---------- strict mode ----------

  # True while the student can still get into trouble for leaving
  def watched?(now = Time.current)
    strict? && !finished? && !blocked? && !expired?(now)
  end

  # Called on every heartbeat and test page load
  def record_presence!(now = Time.current)
    update_column(:last_seen_at, now)
  end

  # Blocks the student if the test page has been silent for too long.
  # Runs whenever the attempt is touched, so no background job is needed.
  def enforce_presence!(now = Time.current)
    return unless watched?(now) && last_seen_at
    block!("No connection from the test page for over #{LEAVE_TIMEOUT.in_minutes.round(1)} minutes", now) if now - last_seen_at > LEAVE_TIMEOUT
  end

  # The test page reported that the student left. Returns :warned, :blocked or :ignored.
  def record_violation!(reason, now = Time.current)
    with_lock do
      if !watched?(now)
        :ignored
      elsif leave_count + 1 > WARNINGS_ALLOWED
        self.leave_count += 1
        block!(reason, now)
        :blocked
      else
        self.leave_count += 1
        save!
        :warned
      end
    end
  end

  def warnings_left
    [WARNINGS_ALLOWED - leave_count, 0].max
  end

  def block!(reason, now = Time.current)
    update!(blocked_at: now, block_reason: reason.to_s.truncate(250))
  end

  # Teacher lets the student continue. The time spent blocked is given back,
  # but never beyond the test's closing time.
  def reinstate!(now = Time.current)
    return false unless blocked?

    new_deadline = deadline_at && [deadline_at + (now - blocked_at), test_session&.ends_at].compact.min
    update!(blocked_at: nil, block_reason: nil, leave_count: 0, last_seen_at: nil, deadline_at: new_deadline)
  end

  # Strict tests hide marks, rank and answers until the test closes
  def results_released?(now = Time.current)
    !test_session || test_session.results_released?(now)
  end

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

  # Marking scheme: the teacher test's exam; topic practice uses UPSC Prelims marking
  def exam
    test_session ? test_session.exam : Exam::DEFAULT
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
      marks: exam.marks_for(correct, wrong), max_marks: (total * exam.correct).round(2),
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
