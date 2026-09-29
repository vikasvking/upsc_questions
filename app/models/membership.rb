# A user belongs to a school or coaching once the membership is approved
class Membership < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :user
  belongs_to :institution
  belongs_to :approved_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :institution_id }

  scope :approved, -> { where(status: "approved") }
  scope :pending,  -> { where(status: "pending") }

  def approved? = status == "approved"
  def pending?  = status == "pending"

  def approve!(by: nil)
    update!(status: "approved", approved_by: by, approved_at: Time.current)
  end
end
