class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :user_responses, dependent: :destroy
  has_many :test_attempts, dependent: :destroy
  has_many :test_sessions, dependent: :destroy
  has_many :test_pin_entries, dependent: :delete_all

  has_many :attempted_questions, -> { distinct }, through: :user_responses, source: :question
  enum :role, { student: 0, teacher: 1, admin: 2 }, default: :student
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :target_exam, with: ->(v) { Exam.normalize(v) }
  validates :target_exam, inclusion: { in: Exam.codes }, allow_nil: true

  # Exams this student has answered questions from, most answered first
  def practised_exam_codes
    user_responses.joins(:question).where.not(questions: { exam_type: [nil, ""] })
                  .group("questions.exam_type").order(Arel.sql("COUNT(*) DESC")).count.keys & Exam.codes
  end

  # The exam used for ranks when none is picked: "Preparing for", else the most practised, else UPSC Prelims
  def ranking_exam_code
    target_exam.presence || practised_exam_codes.first || Exam::DEFAULT.code
  end

  def faculty? = teacher? || admin?
end
