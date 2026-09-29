# An under-18 signup waiting for the parent's code. The account is created only after the code is entered.
# Also used when an existing under-18 account still needs consent (user is set).
class PendingSignup < ApplicationRecord
  CODE_TTL = 30.minutes
  MAX_ATTEMPTS = 5

  belongs_to :user, optional: true

  before_validation :set_token_and_expiry, on: :create
  validates :email_address, :code_digest, :token, :expires_at, presence: true

  # Returns [pending_signup, code]; the code itself is never stored
  def self.start!(email_address:, data:, user: nil)
    code = format("%06d", SecureRandom.random_number(1_000_000))
    where(email_address: email_address.to_s.downcase).delete_all # one pending signup per email
    record = create!(email_address: email_address.to_s.downcase, data: data, user: user,
                     code_digest: BCrypt::Password.create(code))
    [record, code]
  end

  def expired? = expires_at < Time.current
  def locked? = attempts >= MAX_ATTEMPTS
  def attempts_left = [MAX_ATTEMPTS - attempts, 0].max
  def parent_email = data["parent_email"]

  # Counts the try; true when the code matches and is still valid
  def verify(code)
    return false if expired? || locked?
    increment!(:attempts)
    BCrypt::Password.new(code_digest).is_password?(code.to_s.gsub(/\D/, ""))
  end

  private

  def set_token_and_expiry
    self.token ||= SecureRandom.urlsafe_base64(24)
    self.expires_at ||= CODE_TTL.from_now
  end
end
