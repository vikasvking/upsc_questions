# "Report a problem" on a question. The question's teacher and admins see it and reply.
class QuestionReport < ApplicationRecord
  KINDS = {
    "wrong_answer" => "The correct answer is wrong",
    "typo"         => "Typo or wrong wording",
    "unclear"      => "Question or options are unclear",
    "other"        => "Something else"
  }.freeze
  STATUSES = { "open" => "Open", "fixed" => "Fixed", "dismissed" => "No change needed" }.freeze

  belongs_to :question
  belongs_to :user
  belongs_to :resolved_by, class_name: "User", optional: true

  normalizes :message, with: ->(v) { v.to_s.strip.presence }
  normalizes :response, with: ->(v) { v.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :message, length: { maximum: 1000 }
  validates :message, presence: { message: "please describe the problem" }, if: -> { kind == "other" }
  validates :response, length: { maximum: 1000 }

  scope :unresolved, -> { where(status: "open") }
  scope :open_first, -> { order(Arel.sql("CASE WHEN status = 'open' THEN 0 ELSE 1 END"), created_at: :desc) }

  def open? = status == "open"
  def kind_label = KINDS.fetch(kind, kind)
  def status_label = STATUSES.fetch(status, status)

  def resolve!(status:, by:, response: nil)
    update!(status: status, response: response, resolved_by: by, resolved_at: Time.current)
  end

  # Teachers see reports on their own questions
  def self.for_teacher(user) = joins(:question).where(questions: { user_id: user.id })
end
