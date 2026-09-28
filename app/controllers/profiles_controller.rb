class ProfilesController < ApplicationController
  before_action :set_user

  def show
  end

  def edit
  end

  # Email or password changes must be confirmed with the current password
  def update
    unless @user.authenticate(params.dig(:user, :current_password).to_s)
      @user.assign_attributes(user_params.except(:password, :password_confirmation))
      @user.errors.add(:base, "Current password is incorrect")
      render :edit, status: :unprocessable_entity
      return
    end

    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

    if @user.update(attrs)
      @user.sessions.where.not(id: Current.session.id).destroy_all if attrs[:password].present?
      redirect_to profile_path, notice: "Profile updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
