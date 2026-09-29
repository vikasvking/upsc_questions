# A teacher's saved group of students ("Batch A – UPSC 2027"), reusable when choosing who sees a test
class Batch < ApplicationRecord
  belongs_to :user
  belongs_to :institution, optional: true
  has_many :batch_members, dependent: :delete_all
  has_many :students, through: :batch_members, source: :user
  has_many :audience_grants, as: :grantee, dependent: :delete_all

  normalizes :name, with: ->(v) { v.to_s.squish }
  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :user_id, case_sensitive: false }

  scope :ordered, -> { order(:name) }

  def replace_students!(ids)
    ids = User.student.where(id: Array(ids).compact_blank).pluck(:id)
    transaction do
      batch_members.where.not(user_id: ids).delete_all
      (ids - batch_members.pluck(:user_id)).each { |uid| batch_members.create!(user_id: uid) }
    end
  end
end
