# An exam a student is preparing for (one student can pick several)
class UserExam < ApplicationRecord
  belongs_to :user
  normalizes :exam_type, with: ->(v) { Exam.normalize(v) }
  validates :exam_type, inclusion: { in: Exam.codes }
  validates :exam_type, uniqueness: { scope: :user_id }
end
