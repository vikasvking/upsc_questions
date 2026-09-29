# Outgoing email (SMTP) set up on Admin → Email, with an on/off switch.
# The SMTP password is stored encrypted with a key derived from the app's secret_key_base.
class MailSetting < ApplicationRecord
  AUTHENTICATIONS = %w[plain login cram_md5].freeze

  validates :port, numericality: { only_integer: true, in: 1..65_535 }, allow_nil: true
  validates :authentication, inclusion: { in: AUTHENTICATIONS }, allow_blank: true
  validates :from_address, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :address, :from_address, presence: true, if: :enabled?

  def self.current
    first || create!
  end

  # Blank keeps the saved password (the form never shows it)
  def password=(plain)
    self.encrypted_password = self.class.encryptor.encrypt_and_sign(plain) if plain.present?
  end

  def password
    encrypted_password.present? ? self.class.encryptor.decrypt_and_verify(encrypted_password) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil # secret_key_base changed; the admin has to enter the password again
  end

  def password_saved? = encrypted_password.present?
  def complete? = address.present? && from_address.present?
  def active? = enabled? && complete?

  def smtp_settings
    {
      address: address, port: port || 587, domain: domain.presence, user_name: user_name.presence,
      password: password, authentication: authentication.presence&.to_sym,
      enable_starttls_auto: enable_starttls
    }.compact
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key("mail_settings/password", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end
end
