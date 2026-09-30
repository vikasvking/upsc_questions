# A phone that can receive push notifications (a Firebase Cloud Messaging registration token).
# The app sends it after signing in and removes it on sign-out. A token belongs to whoever signed in
# on that phone last, so a shared phone never gets another student's notifications.
class DeviceToken < ApplicationRecord
  PLATFORMS = %w[android ios].freeze

  belongs_to :user

  validates :token, presence: true, uniqueness: true, length: { maximum: 4096 }
  validates :platform, inclusion: { in: PLATFORMS }

  # Registers (or moves) a token to this user
  def self.register!(user, token, platform: "android")
    record = find_or_initialize_by(token: token)
    record.update!(user: user, platform: PLATFORMS.include?(platform.to_s) ? platform.to_s : "android", last_seen_at: Time.current)
    record
  end
end
