class AccountMailer < ApplicationMailer
  def confirm_email(user)
    @user = user
    @url = email_confirmation_url(token: user.generate_token_for(:email_confirmation))
    mail subject: "Confirm your Rankwise email", to: user.email_address
  end
end
