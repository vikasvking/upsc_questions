# Admin → Background work: switch each scheduled job on or off, and see how its last run went. Admins only.
class Admin::BackgroundJobsController < Admin::BaseController
  self.admin_area = :admin_only

  def index
    @settings = BackgroundJobSetting.all_jobs
  end

  # PATCH /admin/background_jobs/:key  enabled=true|false
  def update
    raise ActiveRecord::RecordNotFound unless BackgroundJobSetting::JOBS.key?(params[:key])

    setting = BackgroundJobSetting.for(params[:key])
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    return redirect_to(admin_background_jobs_path, alert: "Choose on or off.") if enabled.nil?

    if setting.enabled? != enabled
      setting.update!(enabled: enabled, updated_by: Current.user)
      log!("update_background_job", record: setting, label: setting.name, details: { "enabled" => { "from" => !enabled, "to" => enabled } })
    end
    redirect_to admin_background_jobs_path, notice: "#{setting.name} is #{enabled ? "ON" : "OFF"}."
  end
end
