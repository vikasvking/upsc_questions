class ProfilesController < ApplicationController
  before_action :set_user
  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to profile_path,notice: "Biodata updated"
    else
      render :edit,status: :unprocessable_entity
    end
  end

  private
  def set_user
    @user=Current.user
  end
  def user_params
    params.require(:user).permit(:email_address,:password,:password_confirmation)
  end
end
