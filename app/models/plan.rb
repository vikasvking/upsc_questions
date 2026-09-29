# A price list entry the admin edits. School plans set a school's limits and give its students a tier (Plus);
# student plans (Warrior) are bought by a student.
class Plan < ApplicationRecord
  KINDS = { "school" => "School plan", "student" => "Student plan" }.freeze

  has_many :institutions, dependent: :nullify

  normalizes :name, with: ->(v) { v.to_s.squish }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :price_month_inr, :price_year_inr, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_month_upgrade_inr, :max_students, :max_teachers, :max_tests_per_month, :member_max_exams,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :member_tier, inclusion: { in: Tiers::NAMES.keys }, allow_blank: true

  scope :ordered, -> { order(:kind, :position, :price_month_inr) }
  scope :active,  -> { where(active: true) }
  scope :for_schools,  -> { where(kind: "school") }
  scope :for_students, -> { where(kind: "student") }

  def school? = kind == "school"

  def limits_text
    return "All exams" unless school?
    [["students", max_students], ["teachers", max_teachers], ["tests a month", max_tests_per_month]]
      .map { |label, n| "#{n.nil? ? "unlimited" : n} #{label}" }.join(" · ")
  end

  def self.warrior = for_students.active.where(member_tier: "warrior").order(:price_month_inr).first
end
