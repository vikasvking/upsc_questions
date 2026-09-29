# A teacher's public profile: subjects, schools/coachings, tests the viewer may see, and ratings. No email shown.
class TeachersController < ApplicationController
  def show
    @teacher = User.teacher.where.not(approved_at: nil).find_by(id: params[:id])
    return redirect_to(root_path, alert: "Teacher not found.") unless @teacher

    @tests = TestSession.available_to(Current.user).where(user: @teacher).includes(:institution, :audience_grants).newest_first.limit(30).to_a
    @test_ratings = Rating.summaries("TestSession", @tests.map(&:id))
    @summary = Rating.summary_for(@teacher)
    all_test_ids = @teacher.test_sessions.pluck(:id)
    @tests_summary = Rating.summary_for_ids("TestSession", all_test_ids)
    @comments = @teacher.received_ratings.with_visible_comment.includes(:user).newest_first.limit(10)
    @my_rating = @teacher.received_ratings.find_by(user: Current.user)
    @can_rate = Rating.can_rate_teacher?(Current.user, @teacher)
  end
end
