# Whether the app may send email right now (Admin → Email switch)
module Mailing
  def self.enabled?
    MailSetting.current.active?
  end

  def self.from_address
    MailSetting.current.from_address.presence || ENV.fetch("MAIL_FROM", "no-reply@example.com")
  end
end
