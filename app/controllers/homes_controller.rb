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
  end
end
