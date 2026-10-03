class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]
  skip_before_action :require_complete_profile, raise: false
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again in a few minutes." }

  def new
    @form = SignupForm.new(role: params[:role].presence_in(SignupForm::ROLES) || "student")
    load_choices
  end

  def create
    @form = SignupForm.new(signup_params)
    @form.exam_codes = params.dig(:signup, :exam_codes)

    unless @form.save
      load_choices
      render :new, status: :unprocessable_entity
      return
    end

    if @form.pending_signup
      send_parent_code(@form.pending_signup, @form.parent_code)
      redirect_to consent_path(@form.pending_signup.token)
      return
    end

    user = @form.user
    start_new_session_for user
    AccountMailer.confirm_email(user).deliver_later if Mailing.enabled?
    if user.teacher?
      redirect_to pending_approval_path, notice: "Welcome! An admin will approve your teacher account soon."
    else
      redirect_to dashboard_path, notice: "Welcome to Lakshyank, #{user.display_name}!"
    end
  end

  private

  def signup_params
    params.require(:signup).permit(:role, :name, :email_address, :password, :password_confirmation, :date_of_birth,
                                   :parent_email, :parent_phone, :bio, :subjects, :institution_id, :join_code,
                                   :new_institution_name, :new_institution_kind, :new_institution_city)
  end

  def load_choices
    @institutions = Institution.ordered
    @subject_suggestions = (Question.where.not(topic: [nil, ""]).distinct.pluck(:topic) + TeacherSubject.distinct.pluck(:name)).uniq.sort
  end

  def send_parent_code(pending, code)
    if Mailing.enabled?
      ConsentMailer.parent_code(pending, code).deliver_now
    else
      # Development only (SignupForm refuses under-18 signups elsewhere while email is off)
      Rails.logger.warn("[parent consent] email is off; code for #{pending.email_address} is #{code}")
      flash[:notice] = "Development: email is off, so the parent's code is #{code}."
    end
  end
end
