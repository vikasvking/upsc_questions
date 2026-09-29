# A subject a teacher teaches (free text, suggested from question topics)
class TeacherSubject < ApplicationRecord
  belongs_to :user
  normalizes :name, with: ->(v) { v.to_s.squish }
  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }
end
