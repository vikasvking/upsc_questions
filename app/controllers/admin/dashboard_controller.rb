class Admin::DashboardController < Admin::BaseController
  def show
    @counts = {
      teachers: User.teacher.count, students: User.student.count, admins: User.admin.count,
      questions: Question.count, tests: TestSession.count,
      live_tests: TestSession.where("starts_at IS NOT NULL OR ends_at IS NOT NULL")
                             .where("starts_at IS NULL OR starts_at <= :now", now: Time.current)
                             .where("ends_at IS NULL OR ends_at > :now", now: Time.current).count,
      writing: TestAttempt.in_progress.not_blocked.where("deadline_at IS NULL OR deadline_at > ?", Time.current).where.not(test_session_id: nil).count,
      blocked: TestAttempt.blocked.in_progress.count
    }
    @blocked = TestAttempt.blocked.in_progress.includes(:user, :test_session).order(blocked_at: :desc).limit(10)
    @logs = AdminLog.newest_first.limit(10)
  end
end
