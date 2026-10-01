# Everything the public home page shows. Also used to show the page again, with the visitor's
# text kept, when the footer contact form has a mistake (ContactMessagesController).
module HomePage
  extend ActiveSupport::Concern

  private

  def load_home_page
    # Real numbers for the landing page (hidden while they are still zero)
    @site_stats = {
      questions: Question.count,
      topics: Question.where.not(topic: [nil, ""]).distinct.count(:topic),
      tests: TestSession.count,
      students: User.student.count
    }

    # Topper table: one exam at a time, only exams with at least 3 ranked students
    @topper_tables = Leaderboard.exam_codes_with_questions.filter_map do |code|
      rows = Leaderboard.rows(code)
      [Exam::BY_CODE[code], rows] if rows.size >= 3
    end
    @topper_exam = @topper_tables.find { |e, _| e.code == Exam.normalize(params[:exam]) } || @topper_tables.first

    # Pricing straight from Admin → Plans (only the plans offered now)
    plans = Plan.active.ordered.to_a
    @school_plans  = plans.select(&:school?)
    @student_plans = plans.reject(&:school?)

    # The footer contact form works only while email is on (Admin → Email)
    @contact_open = Mailing.enabled?
    @contact_message ||= ContactMessage.new(topic: params[:topic].presence_in(ContactMessage::TOPICS.keys) || "question")
  end
end
