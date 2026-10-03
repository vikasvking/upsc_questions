class MailSettingsMailer < ApplicationMailer
  def test_email(to)
    mail subject: "Lakshyank test email", to: to, body: "Email sending from Lakshyank works. Sent #{Time.current}."
  end
end
