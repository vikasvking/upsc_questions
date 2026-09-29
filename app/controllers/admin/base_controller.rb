# Admin pages: admins only. Every change is written to AdminLog.
class Admin::BaseController < ApplicationController
  PER_PAGE = 50

  before_action :require_admin

  private

  def require_admin
    return if Current.user&.admin?
    redirect_to (Current.user&.faculty? ? test_sessions_path : dashboard_path), alert: "Only admins can open the admin pages."
  end

  # Simple page-by-page lists (?page=2) without extra gems
  def paginate(scope)
    @page = [params[:page].to_i, 1].max
    rows = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @next_page = rows.size > PER_PAGE ? @page + 1 : nil
    rows.first(PER_PAGE)
  end

  def log!(action, record: nil, label: nil, reason: nil, details: {})
    AdminLog.record!(admin: Current.user, action: action, record: record, label: label, reason: reason, details: details)
  end

  # Text typed into a "type X to confirm" box
  def confirmed?(expected)
    params[:confirm_text].to_s.strip.casecmp?(expected.to_s.strip)
  end

  def reason_param = params[:reason].to_s.strip
end
