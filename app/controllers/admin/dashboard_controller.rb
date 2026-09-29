class Admin::DashboardController < Admin::BaseController
  def show
    @counts = {
      teachers: User.teacher.count, students: User.student.count, admins: User.admin.count,
      questions: Question.count, tests: TestSession.count,
      live_tests: TestSession.where("starts_at IS NOT NULL OR ends_at IS NOT NULL")
                             .where("starts_at IS NULL OR starts_at <= :now", now: Time.current)
                             .where("ends_at IS NULL OR ends_at > :now", now: Time.current).count,
      writing: TestAttempt.in_progress.not_blocked.where("deadline_at IS NULL OR deadline_at > ?", Time.current).where.not(test_session_id: nil).count,
      blocked: TestAttempt.blocked.in_progress.count,
      pending_teachers: pending_teachers.count,
      pending_requests: pending_requests.count,
      institutions: Institution.count
    }
    @blocked = TestAttempt.blocked.in_progress.includes(:user, :test_session).order(blocked_at: :desc).limit(10)
    @logs = Current.user.admin? ? AdminLog.newest_first.limit(10) : AdminLog.where(admin: Current.user).newest_first.limit(10)
  end

  private

  # Sub-admins count only their own schools/coachings
  def pending_requests
    ids = Current.user.approvable_institution_ids
    ids.nil? ? Membership.pending : Membership.pending.where(institution_id: ids)
  end

  def pending_teachers
    ids = Current.user.approvable_institution_ids
    scope = User.teacher.where(approved_at: nil)
    ids.nil? ? scope : scope.where(id: Membership.where(institution_id: ids).select(:user_id))
  end
end
