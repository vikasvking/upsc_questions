# Joining and leaving schools/coachings; teachers of an institution approve students' requests
class MembershipsController < ApplicationController
  skip_before_action :require_complete_profile, only: [:create, :destroy], raise: false
  before_action :set_membership, only: [:destroy, :approve]

  # POST /memberships  institution_id, join_code
  def create
    institution = Institution.find_by(id: params[:institution_id])
    return redirect_to(profile_path, alert: "Pick a school or coaching from the list.") unless institution

    code = params[:join_code].to_s.strip.upcase
    if code.present? && code != institution.join_code
      redirect_to profile_path, alert: "That join code does not match #{institution.name}. Leave it empty to ask a teacher there to approve you."
      return
    end

    m = Current.user.memberships.find_or_create_by!(institution: institution)
    if m.approved?
      redirect_to profile_path, notice: "You are already a member of #{institution.name}."
    elsif code.present?
      begin
        m.approve!
        redirect_to profile_path, notice: "You joined #{institution.name}."
      rescue Membership::LimitReached => e
        redirect_to profile_path, alert: "#{e.message} Your request is saved and can be approved when there is room."
      end
    else
      redirect_to profile_path, notice: "Request sent. A teacher at #{institution.name} will approve it."
    end
  end

  # PATCH /memberships/:id/approve (a sub-admin of that institution, or an admin)
  def approve
    unless can_manage_institution?(@membership.institution)
      return redirect_back(fallback_location: root_path, alert: "Only a sub-admin of #{@membership.institution.name} (or an admin) can approve requests.")
    end
    begin
      @membership.approve!(by: Current.user)
    rescue Membership::LimitReached => e
      return redirect_back(fallback_location: root_path, alert: e.message)
    end
    # approving a new teacher's request also approves the teacher account
    if @membership.user.pending_teacher?
      @membership.user.update_column(:approved_at, Time.current)
      AdminLog.record!(admin: Current.user, action: "approve_teacher", record: @membership.user, label: @membership.user.email_address,
                       details: { institution: @membership.institution.label })
    end
    redirect_back fallback_location: institutions_path, notice: "#{@membership.user.display_name} joined #{@membership.institution.name}."
  end

  # DELETE /memberships/:id (leave or cancel your own; a sub-admin can remove or reject someone at their institution)
  def destroy
    own = @membership.user_id == Current.user.id
    unless own || can_manage_institution?(@membership.institution)
      return redirect_back(fallback_location: root_path, alert: "You cannot change that membership.")
    end
    @membership.destroy!
    message = own ? "You left #{@membership.institution.name}." : "#{@membership.user.display_name} removed from #{@membership.institution.name}."
    redirect_back fallback_location: (own ? profile_path : institutions_path), notice: message
  end

  private

  def set_membership
    @membership = Membership.includes(:institution, :user).find(params[:id])
  end

  def can_manage_institution?(institution)
    Current.user.can_approve_at?(institution)
  end
end
