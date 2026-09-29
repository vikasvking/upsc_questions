# 1–5 stars and an optional comment from a student, for a test they submitted or a teacher whose test they took.
# One rating per student per test/teacher; they can change it. Averages show once there are MIN_SHOWN ratings.
class Rating < ApplicationRecord
  MIN_SHOWN = 3
  RATEABLE_TYPES = %w[TestSession User].freeze

  Summary = Struct.new(:average, :count) do
    def shown? = count >= MIN_SHOWN
    def stars_text = average ? format("%.1f", average) : "—"
  end

  belongs_to :rateable, polymorphic: true
  belongs_to :user
  belongs_to :comment_hidden_by, class_name: "User", optional: true

  normalizes :comment, with: ->(v) { v.to_s.strip.presence }

  validates :rateable_type, inclusion: { in: RATEABLE_TYPES }
  validates :stars, numericality: { only_integer: true, in: 1..5 }
  validates :comment, length: { maximum: 500 }
  validates :user_id, uniqueness: { scope: [:rateable_type, :rateable_id] }

  scope :newest_first, -> { order(updated_at: :desc) }
  scope :with_visible_comment, -> { where.not(comment: nil).where(comment_hidden_at: nil) }

  def comment_visible? = comment.present? && comment_hidden_at.nil?

  def self.summary_for(rateable)
    avg, count = where(rateable: rateable).pick(Arel.sql("AVG(stars)"), Arel.sql("COUNT(*)"))
    Summary.new(avg&.to_f, count.to_i)
  end

  # One combined summary for many items, e.g. all of a teacher's tests
  def self.summary_for_ids(type, ids)
    avg, count = where(rateable_type: type, rateable_id: ids).pick(Arel.sql("AVG(stars)"), Arel.sql("COUNT(*)"))
    Summary.new(avg&.to_f, count.to_i)
  end

  # { id => Summary } for many tests (or teachers) at once
  def self.summaries(type, ids)
    where(rateable_type: type, rateable_id: ids).group(:rateable_id)
      .pluck(:rateable_id, Arel.sql("AVG(stars)"), Arel.sql("COUNT(*)"))
      .to_h { |id, avg, count| [id, Summary.new(avg.to_f, count.to_i)] }
  end

  # Only students who submitted the test
  def self.can_rate_test?(user, test)
    user&.student? && user.can_rate? &&
      user.test_attempts.finished.not_blocked.exists?(test_session_id: test.id)
  end

  # Only students who submitted at least one of the teacher's tests
  def self.can_rate_teacher?(user, teacher)
    user&.student? && user.can_rate? && teacher&.teacher? &&
      user.test_attempts.finished.not_blocked.joins(:test_session).exists?(test_sessions: { user_id: teacher.id })
  end
end
