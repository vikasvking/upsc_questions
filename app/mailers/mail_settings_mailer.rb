class MailSettingsMailer < ApplicationMailer
  def test_email(to)
    mail subject: "Rankwise test email", to: to, body: "Email sending from Rankwise works. Sent #{Time.current}."
  end
end
