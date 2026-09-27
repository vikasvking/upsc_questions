class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :user_responses, dependent: :destroy
  has_many :test_sessions, dependent: :destroy

  has_many :attempted_questions,->{distinct}, through: :user_responses,source: :question
  enum :role,{student: 0, teacher:1,admin:2},default: :student
  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
