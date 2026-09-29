class Admin::UsersController < Admin::BaseController
  # People's accounts are managed by admins only. An admin makes a teacher a sub-admin by ticking areas.
  self.admin_area = :admin_only

  before_action :set_user, only: [:show, :edit, :update, :destroy, :approve]
  before_action :require_user_access, only: [:show, :edit, :update, :destroy, :approve]
  before_action :require_admin_for_delete, only: :destroy

  def index
    scope = User.where(role: visible_roles).order(:role, :email_address)
    @role = params[:role].presence_in(visible_roles)
    scope = scope.where(role: @role) if @role
    if params[:q].present?
      q = "%#{User.sanitize_sql_like(params[:q].strip.downcase)}%"
      scope = scope.where("email_address ILIKE :q OR name ILIKE :q", q: q)
    end
    scope = scope.where(approved_at: nil) if params[:pending] == "1"
    @counts = User.where(role: visible_roles).group(:role).count
    @users = paginate(scope)
  end

  def show
    @attempts = @user.test_attempts.includes(:test_session).order(started_at: :desc).limit(50)
    @tests = @user.test_sessions.newest_first.limit(50) if @user.faculty?
    @answers_count = @user.user_responses.count
    @questions_count = @user.questions.count
    @memberships = @user.memberships.includes(:institution)
    @consents = @user.guardian_consents.order(consented_at: :desc) if Current.user.admin?
  end

  def new
    @user = User.new(role: params[:role].presence_in(assignable_roles) || assignable_roles.first)
  end

  def create
    @user = User.new(user_params)
    @user.approved_at = Time.current if @user.teacher? # created by staff, so already checked
    if @user.save
      @user.replace_exams!(exam_param) if @user.student? && exam_param.any?
      @user.replace_subjects!(params.dig(:user, :subjects)) if @user.teacher?
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
      @user.replace_exams!(exam_param) if @user.student? && params.dig(:user, :exam_codes)
      @user.replace_subjects!(params.dig(:user, :subjects)) if @user.teacher? && params.dig(:user, :subjects)
      @user.sessions.destroy_all if password_reset && @user != Current.user # signs them out everywhere
      log!("update_user", record: @user, label: @user.email_address,
           details: changes.merge(password_reset ? { "password" => "reset by #{Current.user.role.humanize.downcase}" } : {}))
      redirect_to admin_user_path(@user), notice: "Saved #{@user.email_address}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # PATCH /admin/users/:id/approve -> a new teacher account may now create tests and questions
  def approve
    if @user.pending_teacher?
      @user.update_column(:approved_at, Time.current)
      log!("approve_teacher", record: @user, label: @user.email_address)
    end
    redirect_back fallback_location: admin_users_path(role: "teacher", pending: "1"), notice: "#{@user.display_name} can now create tests."
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

  def visible_roles = User.roles.keys
  helper_method :visible_roles

  def assignable_roles = %w[student teacher admin]
  helper_method :assignable_roles

  def set_user
    @user = User.find(params[:id])
  end

  def require_user_access = nil
  def require_admin_for_delete = nil

  def has_results?(user)
    user.test_attempts.exists? || user.user_responses.exists?
  end

  def role_change_problem(new_role)
    return nil if new_role.blank? || new_role == @user.role
    return "cannot be changed to #{new_role.humanize.downcase} by you" unless assignable_roles.include?(new_role)
    return "cannot be removed from your own account" if @user == Current.user
    return "cannot be changed: Rankwise needs at least one admin" if @user.admin? && User.admin.count <= 1
    nil
  end

  def exam_param
    Array(params.dig(:user, :exam_codes)).filter_map { |c| Exam.normalize(c) }
  end

  def user_params
    keys = [:name, :email_address, :role, :password, :password_confirmation, :date_of_birth, :bio, :approved,
            :membership_tier, :tier_until, { permissions: [] }]
    permitted = params.require(:user).permit(*keys)

    permitted.delete(:role) unless assignable_roles.include?(permitted[:role].to_s)
    if permitted.key?(:approved)
      permitted[:approved_at] = permitted.delete(:approved) == "1" ? (@user&.approved_at || Time.current) : nil
    end
    permitted[:permissions] = Array(permitted[:permissions]) & User::ADMIN_AREAS.keys if permitted.key?(:permissions)
    if permitted.key?(:membership_tier) # a tier set here counts as set by the admin (until payments do it)
      permitted[:tier_source] = permitted[:membership_tier] == "free" ? nil : "admin"
      permitted[:tier_until] = permitted[:tier_until].presence
    end
    # Only teachers can be sub-admins
    permitted[:permissions] = [] if permitted.key?(:permissions) && (permitted[:role] || @user&.role || "student") != "teacher"
    permitted
  end
end
