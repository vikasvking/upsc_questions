# A school or coaching. Students join with its join code (instantly) or by asking (a teacher approves).
class Institution < ApplicationRecord
  KINDS = %w[school coaching].freeze
  SUBSCRIPTION_STATUSES = {
    "none" => "No plan", "trial" => "Free trial", "active" => "Active",
    "past_due" => "Payment due", "suspended" => "Suspended", "cancelled" => "Cancelled"
  }.freeze
  ACTIVE_STATUSES = %w[trial active].freeze
  CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze # no 0/O or 1/I lookalikes

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :plan, optional: true
  has_many :memberships, dependent: :delete_all
  has_many :approved_memberships, -> { approved }, class_name: "Membership"
  has_many :members, through: :approved_memberships, source: :user
  has_many :audience_grants, as: :grantee, dependent: :delete_all

  normalizes :name, with: ->(v) { v.to_s.squish }
  normalizes :city, with: ->(v) { v.to_s.squish.presence }
  normalizes :join_code, with: ->(v) { v.to_s.strip.upcase }

  validates :name, presence: true, length: { maximum: 120 }
  validates :kind, inclusion: { in: KINDS }
  validates :join_code, presence: true, uniqueness: true
  validate  :name_and_city_unique
  validates :subscription_status, inclusion: { in: SUBSCRIPTION_STATUSES.keys }
  validates :override_max_students, :override_max_teachers, :override_max_tests_per_month,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :generate_join_code, on: :create

  scope :ordered, -> { order(:name, :city) }

  def label = [name, city].compact.join(", ") + " (#{kind.capitalize})"
  def teachers = members.where(role: :teacher)
  def students = members.where(role: :student)

  # ---------- plan and limits ----------

  # Only a school with an active (or trial) plan has limits, can publish school tests and gives its students a tier
  def subscribed? = ACTIVE_STATUSES.include?(subscription_status) && plan.present?
  def subscription_label = SUBSCRIPTION_STATUSES.fetch(subscription_status, subscription_status)
  def member_tier = subscribed? ? (plan.member_tier.presence || "plus") : nil

  # nil = no limit
  def limit_for(kind)
    case kind.to_sym
    when :students then override_max_students || plan&.max_students
    when :teachers then override_max_teachers || plan&.max_teachers
    when :tests    then override_max_tests_per_month || plan&.max_tests_per_month
    end
  end

  def students_count = approved_memberships.joins(:user).where(users: { role: User.roles[:student] }).count
  def teachers_count = approved_memberships.joins(:user).where(users: { role: User.roles[:teacher] }).count
  def tests_this_month(now = Time.current) = TestSession.where(institution_id: id, created_at: now.all_month).count

  # [used, limit] for each limit, for usage bars
  def usage
    { students: [students_count, limit_for(:students)], teachers: [teachers_count, limit_for(:teachers)],
      tests: [tests_this_month, limit_for(:tests)] }
  end

  # nil when this person can become a member now, otherwise the reason
  def admission_problem(user)
    return nil unless subscribed?
    kind = user.teacher? ? :teachers : (user.student? ? :students : nil)
    return nil unless kind
    limit = limit_for(kind)
    used = kind == :teachers ? teachers_count : students_count
    return nil if limit.nil? || used < limit
    "#{name} has reached its plan's limit of #{limit} #{kind}. The school can upgrade its plan with the Lakshyank admin."
  end

  # nil when a teacher may publish one more test for this school this month, otherwise the reason
  def test_quota_problem(now = Time.current)
    return "#{name} has no active plan, so tests cannot be published for it yet. Ask the Lakshyank admin." unless subscribed?
    limit = limit_for(:tests)
    return nil if limit.nil? || tests_this_month(now) < limit
    "#{name} has used all #{limit} tests of its plan this month. New tests can be published from #{(now.end_of_month + 1.day).to_date.strftime("%-d %B")}, or the school can upgrade."
  end

  def regenerate_join_code!
    self.join_code = self.class.new_code
    save!
  end

  # Admin: fold a duplicate into this institution
  def absorb!(other)
    transaction do
      other.memberships.find_each do |m|
        existing = memberships.find_by(user_id: m.user_id)
        if existing
          existing.update!(status: "approved", approved_at: existing.approved_at || m.approved_at) if m.approved? && !existing.approved?
          m.destroy!
        else
          m.update!(institution: self)
        end
      end
      # tests, questions and batches shown to the duplicate now belong to this one
      [TestSession, Question, Batch].each { |model| model.where(institution_id: other.id).update_all(institution_id: id) }
      mine = AudienceGrant.where(grantee_type: "Institution", grantee_id: id).pluck(:item_type, :item_id)
      AudienceGrant.where(grantee_type: "Institution", grantee_id: other.id).find_each do |g|
        mine.include?([g.item_type, g.item_id]) ? g.delete : g.update_columns(grantee_id: id)
      end
      other.reload.destroy!
    end
  end

  def self.new_code
    loop do
      code = Array.new(8) { CODE_CHARS.sample(random: SecureRandom) }.join
      break code unless exists?(join_code: code)
    end
  end

  private

  def generate_join_code
    self.join_code = self.class.new_code if join_code.blank?
  end

  def name_and_city_unique
    clash = self.class.where("lower(name) = ? AND lower(coalesce(city, '')) = ?", name.to_s.downcase, city.to_s.downcase)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:name, "is already registered#{" in #{city}" if city}; pick it from the list instead") if clash.exists?
  end
end
