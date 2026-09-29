class ProfilesController < ApplicationController
  skip_before_action :require_complete_profile, raise: false
  before_action :set_user

  def show
    @memberships = @user.memberships.includes(:institution).order(:created_at)
    @institutions = Institution.ordered.where.not(id: @memberships.map(&:institution_id))
    @consent = @user.guardian_consents.order(:consented_at).last if @user.minor?
  end

  def edit
    @subject_suggestions = subject_suggestions
  end

  # PATCH /profile/details -> name, about, date of birth (once), exams or subjects. No password needed.
  def update_details
    attrs = params.require(:user).permit(:name, :bio, :date_of_birth)
    attrs.delete(:bio) unless @user.teacher?
    # A saved date of birth can only be corrected by an admin (it decides whether parent consent is needed)
    attrs.delete(:date_of_birth) unless @user.student? && @user.date_of_birth.blank?
    @user.assign_attributes(attrs)

    exams = Array(params.dig(:user, :exam_codes)).filter_map { |c| Exam.normalize(c) }
    subjects = params.dig(:user, :subjects).to_s.split(",").map(&:squish).compact_blank
    @user.errors.add(:base, "Pick at least one exam you are preparing for") if @user.student? && exams.empty?
    @user.errors.add(:base, "Add at least one subject you teach") if @user.teacher? && subjects.empty?

    if @user.errors.none? && @user.save
      @user.replace_exams!(exams) if @user.student?
      @user.replace_subjects!(subjects) if @user.teacher?
      redirect_to profile_path, notice: "Profile saved."
    else
      @subject_suggestions = subject_suggestions
      render :edit, status: :unprocessable_entity
    end
  end

  # PATCH /profile/exam -> the exam used for the dashboard rank (added to the student's exams if missing)
  def update_exam
    code = Exam.normalize(params[:target_exam])
    if code
      @user.replace_exams!(@user.exam_codes | [code]) if @user.student?
      @user.update_column(:target_exam, code)
      redirect_to profile_path, notice: "Your dashboard rank now uses #{Exam.name_for(code)}."
    else
      redirect_to profile_path, alert: "Please pick an exam from the list."
    end
  end

  # PATCH /profile -> email or password; confirmed with the current password
  def update
    unless @user.authenticate(params.dig(:user, :current_password).to_s)
      @user.assign_attributes(user_params.except(:password, :password_confirmation))
      @user.errors.add(:base, "Current password is incorrect")
      @subject_suggestions = subject_suggestions
      render :edit, status: :unprocessable_entity
      return
    end

    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    email_changed = attrs[:email_address].present? && attrs[:email_address].strip.downcase != @user.email_address

    if @user.update(attrs.merge(email_changed ? { email_confirmed_at: nil } : {}))
      @user.sessions.where.not(id: Current.session.id).destroy_all if attrs[:password].present?
      AccountMailer.confirm_email(@user).deliver_later if email_changed && Mailing.enabled?
      redirect_to profile_path, notice: "Profile updated"
    else
      @subject_suggestions = subject_suggestions
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

  def subject_suggestions
    (Question.where.not(topic: [nil, ""]).distinct.pluck(:topic) + TeacherSubject.distinct.pluck(:name)).uniq.sort
  end
end
