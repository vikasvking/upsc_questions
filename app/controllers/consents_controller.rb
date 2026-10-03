# Parent consent for under-18 students.
#  - New signups: the account is created only when the code from the parent's email is entered (show/verify).
#  - Existing accounts found to be under 18: the student gives the parent's contact (new/create), then the code.
class ConsentsController < ApplicationController
  allow_unauthenticated_access only: [:show, :verify, :resend]
  skip_before_action :require_complete_profile, raise: false
  before_action :set_pending, only: [:show, :verify, :resend]
  rate_limit to: 5, within: 10.minutes, only: [:resend, :create], with: -> { redirect_back fallback_location: root_path, alert: "Please wait a few minutes before asking for another code." }

  # GET /consent/:token
  def show
  end

  # POST /consent/:token
  def verify
    if @pending.expired? || @pending.locked?
      redirect_to consent_path(@pending.token), alert: "This code has #{@pending.locked? ? "had too many wrong tries" : "expired"}. Send a new one."
      return
    end
    unless @pending.verify(params[:code])
      redirect_to consent_path(@pending.token), alert: "That code is not right. #{@pending.attempts_left} tries left."
      return
    end

    user = @pending.user ? attach_consent_to_existing : create_account_from_pending
    return unless user

    @pending.destroy!
    start_new_session_for(user) unless authenticated? && Current.user == user
    AccountMailer.confirm_email(user).deliver_later if Mailing.enabled? && !user.email_confirmed?
    redirect_to dashboard_path, notice: "Thank you — your parent's consent is recorded. Welcome to Lakshyank!"
  end

  # POST /consent/:token/resend
  def resend
    data = @pending.data
    fresh, code = PendingSignup.start!(email_address: @pending.email_address, data: data, user: @pending.user)
    deliver(fresh, code)
    redirect_to consent_path(fresh.token), notice: "A new code was sent to #{helpers.mask(fresh.parent_email)}."
  end

  # GET /parent_consent/new (logged-in student under 18 without consent)
  def new
    redirect_to dashboard_path and return unless Current.user.needs_parent_consent?
    @consent = GuardianConsent.new
  end

  # POST /parent_consent
  def create
    redirect_to dashboard_path and return unless Current.user.needs_parent_consent?

    @consent = GuardianConsent.new(params.require(:guardian_consent).permit(:parent_email, :parent_phone)
                                          .merge(consent_version: GuardianConsent::VERSION, consented_at: Time.current))
    @consent.errors.add(:base, "Email sending is not set up yet, so we cannot send your parent a code. Please try again later.") unless Mailing.enabled? || Rails.env.development?
    @consent.errors.add(:parent_email, "must be your parent's email, not yours") if @consent.parent_email == Current.user.email_address
    if @consent.errors.any? || !@consent.valid?
      render :new, status: :unprocessable_entity
      return
    end

    pending, code = PendingSignup.start!(email_address: Current.user.email_address, user: Current.user,
                                         data: { "name" => Current.user.name, "parent_email" => @consent.parent_email,
                                                 "parent_phone" => @consent.parent_phone })
    deliver(pending, code)
    redirect_to consent_path(pending.token)
  end

  private

  def set_pending
    @pending = PendingSignup.find_by(token: params[:token])
    redirect_to new_registration_path, alert: "That consent link is no longer valid. Please sign up again." unless @pending
  end

  def create_account_from_pending
    d = @pending.data
    if User.exists?(email_address: @pending.email_address)
      redirect_to new_session_path, alert: "An account with this email already exists. Please log in."
      return nil
    end

    User.transaction do
      user = User.new(role: "student", name: d["name"], email_address: @pending.email_address,
                      date_of_birth: d["date_of_birth"], password_digest: d["password_digest"])
      user.save!
      record_consent!(user, d)
      SignupForm.finish_setup!(user, exam_codes: d["exam_codes"], institution: d["institution"] || {})
      user
    end
  end

  def attach_consent_to_existing
    record_consent!(@pending.user, @pending.data)
    @pending.user
  end

  def record_consent!(user, d)
    user.guardian_consents.create!(parent_email: d["parent_email"], parent_phone: d["parent_phone"],
                                   consent_version: GuardianConsent::VERSION, consented_at: Time.current,
                                   ip_address: request.remote_ip)
  end

  def deliver(pending, code)
    if Mailing.enabled?
      ConsentMailer.parent_code(pending, code).deliver_now
    else
      Rails.logger.warn("[parent consent] email is off; code for #{pending.email_address} is #{code}")
      flash[:notice] = "Development: email is off, so the parent's code is #{code}." if Rails.env.development?
    end
  end
end
