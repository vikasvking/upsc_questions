# "Report a problem" on a question (anyone who can see it), and the teacher's list of reports on their questions
class QuestionReportsController < ApplicationController
  rate_limit to: 10, within: 1.hour, only: :create,
             with: -> { redirect_back fallback_location: root_path, alert: "You've sent many reports recently. Please try again later." }

  # GET /question_reports -> teachers: reports on their questions
  def index
    return redirect_to(profile_path, alert: "Only teachers have a reports page.") unless Current.user.faculty?
    scope = QuestionReport.for_teacher(Current.user).includes(:question, :user).open_first
    @status = params[:status].presence_in(QuestionReport::STATUSES.keys)
    scope = scope.where(status: @status) if @status
    @reports = scope.limit(200)
  end

  # POST /question_reports  question_id, question_report[kind], question_report[message]
  def create
    question = Question.find_by(id: params[:question_id])
    unless question && can_see?(question)
      return redirect_back(fallback_location: root_path, alert: "Question not found.")
    end

    report = question.question_reports.new(params.require(:question_report).permit(:kind, :message).merge(user: Current.user))
    if report.save
      ReportMailer.new_report(report).deliver_later if Mailing.enabled? && question.user&.faculty?
      redirect_back fallback_location: root_path, notice: "Thanks! Your report was sent to the teacher."
    else
      redirect_back fallback_location: root_path, alert: "Report not sent: #{report.errors.full_messages.to_sentence}"
    end
  end

  # PATCH /question_reports/:id -> the question's teacher (or an admin) marks it fixed / no change needed, with a reply
  def update
    report = QuestionReport.includes(:question).find(params[:id])
    unless report.question.user_id == Current.user.id || Current.user.can_manage?(:ratings)
      return redirect_back(fallback_location: root_path, alert: "Only the question's teacher can answer this report.")
    end

    status = params[:status].presence_in(%w[fixed dismissed open]) || "fixed"
    report.resolve!(status: status, by: Current.user, response: params[:response])
    redirect_back fallback_location: question_reports_path, notice: "Report marked “#{report.status_label}”."
  end

  private

  # Visible to the student, or part of a test they took
  def can_see?(question)
    question.visible_to?(Current.user) ||
      TestQuestion.where(question_id: question.id, test_session_id: Current.user.test_attempts.select(:test_session_id)).exists?
  end
end
