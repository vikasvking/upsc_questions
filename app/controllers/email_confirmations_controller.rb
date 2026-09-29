class EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access only: :show
  skip_before_action :require_complete_profile, raise: false
  rate_limit to: 3, within: 10.minutes, only: :create, with: -> { redirect_to profile_path, alert: "Please wait a few minutes before asking again." }

  # GET /confirm_email/:token (link in the email)
  def show
    user = User.find_by_token_for(:email_confirmation, params[:token])
    if user
      user.update_column(:email_confirmed_at, Time.current)
      redirect_to (authenticated? ? profile_path : new_session_path), notice: "Thanks, your email #{user.email_address} is confirmed."
    else
      redirect_to (authenticated? ? profile_path : new_session_path), alert: "That confirmation link is invalid or has expired."
    end
  end

  # POST /confirm_email (send the link again)
  def create
    if !Mailing.enabled?
      redirect_to profile_path, alert: "Email sending is not set up yet. You can confirm your email later."
    elsif Current.user.email_confirmed?
      redirect_to profile_path, notice: "Your email is already confirmed."
    else
      AccountMailer.confirm_email(Current.user).deliver_later
      redirect_to profile_path, notice: "Confirmation link sent to #{Current.user.email_address}."
    end
  end
end
