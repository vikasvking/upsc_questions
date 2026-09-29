class HomesController < ApplicationController
  allow_unauthenticated_access only: [ :index ]

  def index
    redirect_to dashboard_path and return if authenticated?

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
  end
end
