class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # After login: finish the profile, get parent consent (under 18), or wait for teacher approval
  before_action :require_complete_profile

  private

  def require_complete_profile
    user = Current.user
    return unless user

    if user.missing_profile_items.any?
      redirect_to edit_profile_path, alert: "Please add #{user.missing_profile_items.to_sentence} to continue."
    elsif user.needs_parent_consent?
      redirect_to new_parent_consent_path, alert: "Students under 18 need a parent's consent to continue."
    elsif user.pending_teacher?
      redirect_to pending_approval_path
    end
  end
end
