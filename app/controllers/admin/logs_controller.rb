class Admin::LogsController < Admin::BaseController
  self.admin_area = :admin_only
  def index
    scope = AdminLog.newest_first
    scope = scope.where(action: params[:action_name]) if AdminLog::LABELS.key?(params[:action_name])
    @logs = paginate(scope)
  end
end
