# Admin → Plans: prices and limits for school plans and student plans. Admins only.
class Admin::PlansController < Admin::BaseController
  self.admin_area = :admin_only

  before_action :set_plan, only: [:edit, :update]

  def index
    @plans = Plan.ordered
    @school_counts = Institution.where.not(plan_id: nil).group(:plan_id, :subscription_status).count
  end

  def new
    @plan = Plan.new(kind: params[:kind].presence_in(Plan::KINDS.keys) || "school", member_tier: params[:kind] == "student" ? "warrior" : "plus")
  end

  def create
    @plan = Plan.new(plan_params)
    if @plan.save
      log!("create_plan", record: @plan, label: @plan.name, details: plan_params.to_h)
      redirect_to admin_plans_path, notice: "Plan “#{@plan.name}” added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Plans are never deleted (schools may use them); switch "active" off to stop offering one
  def update
    before = @plan.attributes
    if @plan.update(plan_params)
      changes = @plan.attributes.filter_map { |k, v| [k, { "from" => before[k], "to" => v }] unless before[k] == v || k == "updated_at" }.to_h
      log!("update_plan", record: @plan, label: @plan.name, details: changes)
      redirect_to admin_plans_path, notice: "Plan “#{@plan.name}” saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_plan
    @plan = Plan.find(params[:id])
  end

  def plan_params
    p = params.require(:plan).permit(:name, :kind, :price_month_inr, :price_year_inr, :price_month_upgrade_inr, :max_students,
                                     :max_teachers, :max_tests_per_month, :member_tier, :member_max_exams, :active, :position)
    %i[price_month_upgrade_inr max_students max_teachers max_tests_per_month member_max_exams].each { |k| p[k] = p[k].presence if p.key?(k) }
    p
  end
end
