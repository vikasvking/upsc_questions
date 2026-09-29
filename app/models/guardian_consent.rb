# A parent's consent for an under-18 student's account, confirmed by a code sent to the parent's email.
# Only admins can see these (not sub-admins).
class GuardianConsent < ApplicationRecord
  VERSION = "2026-09".freeze

  # Shown on the signup page and in the email to the parent. Update VERSION whenever this text changes.
  TEXT = <<~TEXT.freeze
    Rankwise is an online practice and test platform. To create an account for a student under 18, we need a parent's or guardian's consent.
    We will store the student's name, email address, date of birth, the exams they prepare for, their school or coaching (if they add one), and their answers, marks and ranks.
    We store the parent's email and phone number only to confirm this consent and to contact the parent about the account.
    The student's answers and results are visible to their teachers. We do not sell this data or show advertising based on it.
    A parent can ask for the account and its data to be deleted at any time by writing to the Rankwise admin.
  TEXT

  belongs_to :user

  normalizes :parent_email, with: ->(v) { v.to_s.strip.downcase }
  normalizes :parent_phone, with: ->(v) { v.to_s.gsub(/[^\d+]/, "") }

  validates :parent_email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :parent_phone, format: { with: /\A\+?\d{10,13}\z/, message: "must be a 10-digit mobile number (with +91 if you like)" }
  validates :consent_version, :consented_at, presence: true
end
