class TestSession < ApplicationRecord
  belongs_to :user
  has_many :test_questions, dependent: :destroy
  has_many :questions, through: :test_questions

  validates :title, :exam_type, :pin_code, presence: true
  validates :pin_code, uniqueness: true

  # Auto-generates a secure randomized classroom code on record initialization
  before_validation :generate_secure_pin, on: :create

  private

  def generate_secure_pin
    self.pin_code ||= SecureRandom.alphanumeric(6).upcase
  end
end
