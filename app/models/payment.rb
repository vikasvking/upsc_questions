# One payment for a plan: Warrior for a student, or a school plan paid by one of the school's teachers.
#
#   UPI QR (gateway off): the payer pays by QR and types the transaction ID (UTR) -> "pending" until an
#                         admin checks the bank and approves (activates the plan) or rejects it.
#   Razorpay (gateway on): "created" when the order is made -> approved automatically once Razorpay's
#                         signature checks out (no admin step).
class Payment < ApplicationRecord
  PERIODS  = { "month" => "1 month", "year" => "1 year" }.freeze
  STATUSES = { "created" => "Not finished", "pending" => "Waiting for check", "approved" => "Approved", "rejected" => "Rejected" }.freeze
  METHODS  = { "upi_qr" => "UPI (QR)", "razorpay" => "Razorpay" }.freeze
  UTR_FORMAT = /\A[A-Z0-9]{6,35}\z/

  belongs_to :user
  belongs_to :plan
  belongs_to :institution, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  normalizes :utr, with: ->(v) { v.to_s.gsub(/[\s-]/, "").upcase.presence }
  normalizes :admin_note, with: ->(v) { v.to_s.squish.presence }

  validates :period, inclusion: { in: PERIODS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :pay_method, inclusion: { in: METHODS.keys }
  validates :amount_inr, numericality: { only_integer: true, greater_than: 0 }
  validates :utr, presence: { message: "is needed" }, if: :upi_qr?
  validates :utr, format: { with: UTR_FORMAT, message: "should be the 12-digit UPI reference or the bank's transaction ID (letters and numbers only)" },
                  uniqueness: { message: "has already been submitted" }, allow_nil: true
  validates :admin_note, length: { maximum: 300 }
  validate :plan_suits_payer, on: :create

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :submitted, -> { where.not(status: "created") } # Razorpay orders that were never paid stay hidden

  def self.human_attribute_name(attribute, options = {})
    { "utr" => "Transaction ID", "institution" => "School or coaching" }.fetch(attribute.to_s) { super }
  end

  # The price for this payer: Plus students get Warrior at the plan's lower monthly upgrade price
  def self.amount_for(plan, period, user)
    return plan.price_year_inr if period == "year"
    return plan.price_month_upgrade_inr if !plan.school? && plan.price_month_upgrade_inr && user&.tier == "plus"
    plan.price_month_inr
  end

  def school? = institution_id.present?
  def upi_qr? = pay_method == "upi_qr"
  def razorpay? = pay_method == "razorpay"
  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def status_label = STATUSES.fetch(status, status)
  def period_label = PERIODS.fetch(period, period)
  def months = period == "year" ? 12 : 1
  def what = school? ? "#{plan.name} plan for #{institution&.name || "a deleted school"}" : "#{plan.name} membership"

  # Activates the plan and marks the payment approved. reviewer is nil for Razorpay (checked automatically).
  def approve!(reviewer = nil, note: nil)
    raise ArgumentError, "already #{status_label.downcase}" if approved? || rejected?

    transaction do
      self.paid_until = activate_plan!
      update!(status: "approved", reviewed_by: reviewer, reviewed_at: Time.current, admin_note: note)
    end
  end

  def reject!(reviewer, note:)
    raise ArgumentError, "already #{status_label.downcase}" if approved? || rejected?
    update!(status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current, admin_note: note)
  end

  private

  # Extends from today, or from the current end date when the same plan is still running. Returns the new end date.
  def activate_plan!
    if school?
      school = institution or raise ActiveRecord::RecordNotFound, "The school was deleted"
      continuing = school.subscribed? && school.plan_id == plan_id && school.subscription_renews_on&.>=(Date.current)
      ends_on = (continuing ? school.subscription_renews_on : Date.current) + months.months
      school.update!(plan: plan, subscription_status: "active", subscription_renews_on: ends_on,
                     subscription_started_on: continuing ? (school.subscription_started_on || Date.current) : Date.current)
    else
      tier = plan.member_tier.presence || "warrior"
      continuing = user.membership_tier == tier && user.tier_until&.>=(Date.current)
      ends_on = (continuing ? user.tier_until : Date.current) + months.months
      # update_columns: the payment must not fail because of an unrelated profile check on the account
      user.update_columns(membership_tier: tier, tier_until: ends_on, tier_source: "payment", updated_at: Time.current)
    end
    ends_on
  end

  def plan_suits_payer
    return errors.add(:plan, "is not offered right now") unless plan&.active?

    if plan.school?
      if institution.nil?
        errors.add(:institution, "must be chosen for a school plan")
      elsif !(user&.admin? || user&.institutions&.exists?(institution.id))
        errors.add(:base, "You can only pay for a school or coaching you teach at")
      end
      errors.add(:base, "Only teachers can pay for a school plan") unless user&.faculty?
    else
      errors.add(:base, "Student plans are for students") unless user&.student?
      errors.add(:institution, "is only for school plans") if institution
    end
  end
end
