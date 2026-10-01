# Admin pages: admins, and sub-admins for the areas an admin gave them. Every change is written to AdminLog.
class Admin::BaseController < ApplicationController
  include ExamListing # paginate (?page, ?per), exam tabs

  class_attribute :admin_area, default: nil # nil = any admin or sub-admin; :admin_only = admins only

  before_action :require_staff
  before_action :require_area

  helper_method :can_manage?

  private

  def require_staff
    return if Current.user&.staff?
    redirect_to (Current.user&.faculty? ? test_sessions_path : dashboard_path), alert: "Only admins can open the admin pages."
  end

  def require_area
    case admin_area
    when nil then nil
    when :admin_only then deny unless Current.user.admin?
    else deny unless can_manage?(admin_area)
    end
  end

  def can_manage?(area) = Current.user.can_manage?(area)

  def deny(message = "You do not have access to that admin area. Ask an admin.")
    redirect_to admin_root_path, alert: message
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
