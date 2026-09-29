class Admin::LogsController < Admin::BaseController
  def index
    scope = AdminLog.newest_first
    scope = scope.where(action: params[:action_name]) if AdminLog::LABELS.key?(params[:action_name])
    @logs = paginate(scope)
  end
end
