# Sub-admins (area "approvals") approve new teachers and join requests at their own schools/coachings.
# Admins see everything here.
class Admin::ApprovalsController < Admin::BaseController
  self.admin_area = :approvals

  def index
    ids = Current.user.approvable_institution_ids
    memberships = Membership.pending.includes(:user, :institution).order(:created_at)
    memberships = memberships.where(institution_id: ids) unless ids.nil?
    @requests = memberships.to_a

    teachers = User.teacher.where(approved_at: nil).order(:created_at)
    # a sub-admin sees new teachers who asked to join (or joined) one of their institutions
    teachers = teachers.where(id: Membership.where(institution_id: ids).select(:user_id)) unless ids.nil?
    @pending_teachers = teachers.includes(memberships: :institution).to_a
    @institutions = ids.nil? ? nil : Institution.where(id: ids).ordered
  end

  # PATCH /admin/approvals/:id/approve_teacher (id = user)
  def approve_teacher
    teacher = User.teacher.find(params[:id])
    ids = Current.user.approvable_institution_ids
    unless ids.nil? || teacher.memberships.exists?(institution_id: ids)
      return deny("That teacher has not asked to join one of your schools or coachings.")
    end

    teacher.update_column(:approved_at, Time.current) unless teacher.approved?
    # their requests at the approver's institutions are approved too
    scope = teacher.memberships.pending
    scope = scope.where(institution_id: ids) unless ids.nil?
    scope.each { |m| m.approve!(by: Current.user) }
    log!("approve_teacher", record: teacher, label: teacher.email_address)
    redirect_to admin_approvals_path, notice: "#{teacher.display_name} can now create tests and questions."
  end
end
