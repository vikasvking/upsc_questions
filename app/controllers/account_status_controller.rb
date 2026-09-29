# Shown to teachers whose account an admin has not approved yet
class AccountStatusController < ApplicationController
  skip_before_action :require_complete_profile, raise: false

  def pending_approval
    redirect_to root_path unless Current.user.pending_teacher?
  end
end
