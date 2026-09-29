class ReportMailer < ApplicationMailer
  def new_report(report)
    @report = report
    @url = question_reports_url
    mail subject: "A student reported a problem with one of your questions", to: report.question.user.email_address
  end
end
