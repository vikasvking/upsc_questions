class ApplicationMailer < ActionMailer::Base
  default from: -> { Mailing.from_address }
  layout "mailer"

  # Admin → Email decides whether and how mail goes out. Tests keep the :test delivery method.
  after_action :apply_mail_settings

  private

  def apply_mail_settings
    settings = MailSetting.current
    unless settings.active?
      message.perform_deliveries = false
      return
    end
    message.delivery_method(Mail::SMTP, settings.smtp_settings) unless Rails.env.test?
  end
end
