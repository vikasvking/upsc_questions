class Admin::InstitutionsController < Admin::BaseController
  self.admin_area = :institutions

  before_action :set_institution, only: [:edit, :update, :destroy, :merge, :regenerate_code, :subscription]

  def index
    scope = Institution.ordered.includes(:plan)
    scope = scope.where("name ILIKE :q OR city ILIKE :q", q: "%#{Institution.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?
    scope = scope.where(kind: params[:kind]) if Institution::KINDS.include?(params[:kind])
    @institutions = paginate(scope)
    ids = @institutions.map(&:id)
    @member_counts  = Membership.approved.joins(:user).where(institution_id: ids).group(:institution_id, "users.role").count
    @pending_counts = Membership.pending.where(institution_id: ids).group(:institution_id).count
  end

  def new
    @institution = Institution.new(kind: "coaching")
  end

  def create
    @institution = Institution.new(institution_params.merge(created_by: Current.user))
    if @institution.save
      log!("create_institution", record: @institution, label: @institution.label)
      redirect_to admin_institutions_path, notice: "Added #{@institution.label}. Join code: #{@institution.join_code}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @members = @institution.memberships.includes(:user).order(:status, :created_at)
    @others = Institution.ordered.where.not(id: @institution.id)
  end

  def update
    before = @institution.attributes.slice("name", "kind", "city")
    if @institution.update(institution_params)
      log!("update_institution", record: @institution, label: @institution.label,
           details: @institution.attributes.slice("name", "kind", "city").filter_map { |k, v| [k, { "from" => before[k], "to" => v }] unless before[k] == v }.to_h)
      redirect_to admin_institutions_path, notice: "Saved #{@institution.label}."
    else
      @members = @institution.memberships.includes(:user)
      @others = Institution.ordered.where.not(id: @institution.id)
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /admin/institutions/:id/merge  into_id=... -> this duplicate's members move into the other one
  def merge
    target = Institution.find_by(id: params[:into_id])
    return redirect_to(edit_admin_institution_path(@institution), alert: "Pick the institution to keep.") unless target

    label = @institution.label
    moved = @institution.memberships.count
    target.absorb!(@institution)
    log!("merge_institution", record: target, label: target.label, details: { merged: label, members_moved: moved })
    redirect_to admin_institutions_path, notice: "#{label} merged into #{target.label}."
  end

  # PATCH /admin/institutions/:id/subscription -> plan, status, dates and special limits (admins only; later set by payments)
  def subscription
    return deny("Only admins manage plans and payments.") unless Current.user.admin?

    before = @institution.attributes.slice(*SUBSCRIPTION_FIELDS)
    attrs = params.require(:institution).permit(*SUBSCRIPTION_FIELDS)
    %w[override_max_students override_max_teachers override_max_tests_per_month plan_id].each { |k| attrs[k] = attrs[k].presence if attrs.key?(k) }
    if @institution.update(attrs)
      changes = @institution.attributes.slice(*SUBSCRIPTION_FIELDS).filter_map { |k, v| [k, { "from" => before[k], "to" => v }] unless before[k] == v }.to_h
      log!("update_subscription", record: @institution, label: @institution.label, details: changes)
      redirect_to edit_admin_institution_path(@institution), notice: "Plan for #{@institution.name}: #{@institution.plan&.name || "none"} · #{@institution.subscription_label}."
    else
      redirect_to edit_admin_institution_path(@institution), alert: @institution.errors.full_messages.to_sentence
    end
  end

  def regenerate_code
    @institution.regenerate_join_code!
    log!("update_institution", record: @institution, label: @institution.label, details: { "join_code" => "regenerated" })
    redirect_to edit_admin_institution_path(@institution), notice: "New join code: #{@institution.join_code}"
  end

  def destroy
    return deny("Only admins can delete schools and coachings.") unless Current.user.admin?
    label = @institution.label
    members = @institution.memberships.count
    if members.positive? && !confirmed?(@institution.name)
      redirect_to edit_admin_institution_path(@institution), alert: "Type #{@institution.name} to confirm: #{members} membership(s) will be removed."
      return
    end
    @institution.destroy!
    log!("delete_institution", label: label, reason: reason_param, details: { memberships_removed: members })
    redirect_to admin_institutions_path, notice: "Deleted #{label}."
  end

  private

  def set_institution
    @institution = Institution.find(params[:id])
  end

  SUBSCRIPTION_FIELDS = %w[plan_id subscription_status subscription_started_on subscription_renews_on override_max_students
                           override_max_teachers override_max_tests_per_month billing_notes payment_reference].freeze

  def institution_params
    params.require(:institution).permit(:name, :kind, :city)
  end
end
