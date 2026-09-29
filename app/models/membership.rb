# A user belongs to a school or coaching once the membership is approved
class Membership < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  class LimitReached < StandardError; end

  belongs_to :user
  belongs_to :institution
  belongs_to :approved_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :institution_id }

  scope :approved, -> { where(status: "approved") }
  scope :pending,  -> { where(status: "pending") }

  def approved? = status == "approved"
  def pending?  = status == "pending"

  # Raises LimitReached when the school's plan has no room left for this student or teacher
  def approve!(by: nil)
    return true if approved?
    problem = institution.admission_problem(user)
    raise LimitReached, problem if problem
    update!(status: "approved", approved_by: by, approved_at: Time.current)
  end
end
