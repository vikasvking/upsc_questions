class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :edit, :update, :destroy]

  def index
    scope = User.order(:role, :email_address)
    @role = params[:role].presence_in(User.roles.keys)
    scope = scope.where(role: @role) if @role
    if params[:q].present?
      scope = scope.where("email_address ILIKE ?", "%#{User.sanitize_sql_like(params[:q].strip.downcase)}%")
    end
    @counts = User.group(:role).count
    @users = paginate(scope)
  end

  def show
    @attempts = @user.test_attempts.includes(:test_session).order(started_at: :desc).limit(50)
    @tests = @user.test_sessions.newest_first.limit(50) if @user.faculty?
    @answers_count = @user.user_responses.count
    @questions_count = @user.questions.count
  end

  def new
    @user = User.new(role: params[:role].presence_in(User.roles.keys) || "student")
  end

  def create
    @user = User.new(user_params)
    if @user.save
      log!("create_user", record: @user, label: @user.email_address, details: { role: @user.role })
      redirect_to admin_user_path(@user), notice: "Account created for #{@user.email_address}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

    if (problem = role_change_problem(attrs[:role]))
      @user.assign_attributes(attrs.except(:password, :password_confirmation))
      @user.errors.add(:role, problem)
      render :edit, status: :unprocessable_entity
      return
    end

    @user.assign_attributes(attrs)
    changes = @user.changes.except("password_digest", "updated_at").transform_values { |from, to| { "from" => from, "to" => to } }
    password_reset = attrs[:password].present?

    if @user.save
      @user.sessions.destroy_all if password_reset && @user != Current.user # signs them out everywhere
      log!("update_user", record: @user, label: @user.email_address,
           details: changes.merge(password_reset ? { "password" => "reset by admin" } : {}))
      redirect_to admin_user_path(@user), notice: "Saved #{@user.email_address}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Deleting a teacher keeps their tests and questions (shown under the exam's name).
  # Deleting a student removes their answers and results, so it needs typed confirmation.
  def destroy
    if @user == Current.user
      redirect_to edit_admin_user_path(@user), alert: "You cannot delete your own account."
      return
    end
    if @user.admin? && User.admin.count <= 1
      redirect_to edit_admin_user_path(@user), alert: "Rankwise needs at least one admin."
      return
    end
    if has_results?(@user) && !confirmed?(@user.email_address)
      redirect_to edit_admin_user_path(@user), alert: "Type #{@user.email_address} to confirm: this deletes their answers and test results."
      return
    end

    label = @user.email_address
    details = { role: @user.role, tests_kept: @user.test_sessions.count, questions_kept: @user.questions.count,
                attempts_deleted: @user.test_attempts.count }
    @user.destroy!
    log!("delete_user", label: label, reason: reason_param, details: details)
    redirect_to admin_users_path, notice: "Deleted #{label}." + (details[:tests_kept].positive? ? " Their #{details[:tests_kept]} test(s) were kept." : "")
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def has_results?(user)
    user.test_attempts.exists? || user.user_responses.exists?
  end

  def role_change_problem(new_role)
    return nil if new_role.blank? || new_role == @user.role
    return "cannot be removed from your own account" if @user == Current.user
    return "cannot be changed: Rankwise needs at least one admin" if @user.admin? && User.admin.count <= 1
    nil
  end

  def user_params
    permitted = params.require(:user).permit(:email_address, :role, :password, :password_confirmation, :target_exam)
    permitted.delete(:role) unless User.roles.key?(permitted[:role].to_s)
    permitted[:target_exam] = permitted[:target_exam].presence if permitted.key?(:target_exam)
    permitted
  end
end
