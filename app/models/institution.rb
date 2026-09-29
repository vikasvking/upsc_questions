# A school or coaching. Students join with its join code (instantly) or by asking (a teacher approves).
class Institution < ApplicationRecord
  KINDS = %w[school coaching].freeze
  CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze # no 0/O or 1/I lookalikes

  belongs_to :created_by, class_name: "User", optional: true
  has_many :memberships, dependent: :delete_all
  has_many :approved_memberships, -> { approved }, class_name: "Membership"
  has_many :members, through: :approved_memberships, source: :user

  normalizes :name, with: ->(v) { v.to_s.squish }
  normalizes :city, with: ->(v) { v.to_s.squish.presence }
  normalizes :join_code, with: ->(v) { v.to_s.strip.upcase }

  validates :name, presence: true, length: { maximum: 120 }
  validates :kind, inclusion: { in: KINDS }
  validates :join_code, presence: true, uniqueness: true
  validate  :name_and_city_unique

  before_validation :generate_join_code, on: :create

  scope :ordered, -> { order(:name, :city) }

  def label = [name, city].compact.join(", ") + " (#{kind.capitalize})"
  def teachers = members.where(role: :teacher)
  def students = members.where(role: :student)

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
