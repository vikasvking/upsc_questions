class RegistrationsController < ApplicationController
  # Skip user validation requirements so non-logged-in users can reach the page
  allow_unauthenticated_access only: [ :new, :create ]

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      # Securely stamp session token cookie mapping upon successful sign up
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome aboard! Your account has been initialized."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.permit(:email_address, :password, :password_confirmation)
  end
end
