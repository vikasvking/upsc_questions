# Admin → Payments → Settings: Razorpay keys with an on/off switch, and the UPI ID for the QR
# shown while the gateway is off. The key secret is stored encrypted (like the SMTP password).
class PaymentSetting < ApplicationRecord
  UPI_FORMAT = /\A[\w.\-]{2,256}@[a-zA-Z][a-zA-Z0-9.]{1,63}\z/

  normalizes :razorpay_key_id, :upi_id, with: ->(v) { v.to_s.strip.presence }
  normalizes :payee_name, with: ->(v) { v.to_s.squish.presence }

  validates :upi_id, format: { with: UPI_FORMAT, message: "should look like name@bank" }, allow_blank: true
  validates :razorpay_key_id, format: { with: /\Arzp_(test|live)_\w+\z/, message: "should start with rzp_test_ or rzp_live_" }, allow_blank: true
  validates :payee_name, length: { maximum: 60 }
  validates :instructions, length: { maximum: 1000 }
  validate :gateway_has_keys, if: :gateway_enabled?

  def self.current
    first || create!
  end

  # Blank keeps the saved secret (the form never shows it)
  def razorpay_key_secret=(plain)
    self.encrypted_razorpay_key_secret = self.class.encryptor.encrypt_and_sign(plain.to_s.strip) if plain.present?
  end

  def razorpay_key_secret
    encrypted_razorpay_key_secret.present? ? self.class.encryptor.decrypt_and_verify(encrypted_razorpay_key_secret) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil # secret_key_base changed; the admin has to enter the secret again
  end

  def secret_saved? = encrypted_razorpay_key_secret.present?
  def gateway_ready? = gateway_enabled? && razorpay_key_id.present? && razorpay_key_secret.present?
  def qr_ready? = upi_id.present?
  def live_mode? = razorpay_key_id.to_s.start_with?("rzp_live_")

  # What the UPI QR / "Open UPI app" link contains: the exact amount is filled in for the payer
  def upi_uri(amount_inr, note)
    "upi://pay?" + URI.encode_www_form(pa: upi_id, pn: payee_name.presence || "Lakshyank", am: format("%.2f", amount_inr),
                                       cu: "INR", tn: note.to_s.first(50))
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key("payment_settings/razorpay_secret", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  private

  def gateway_has_keys
    errors.add(:base, "Enter the Razorpay Key ID and Key Secret before switching online payment on.") unless razorpay_key_id.present? && secret_saved?
  end
end
