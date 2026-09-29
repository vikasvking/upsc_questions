# GET /membership -> a student's tier, what it includes, and how to get more
class TiersController < ApplicationController
  def show
    @user = Current.user
    @tier = @user.tier
    @sample_tests = TestSession.where(free_sample: true).order(:created_at)
    @taken_samples = @user.test_attempts.where(test_session_id: @sample_tests.select(:id)).count
    @answered_samples = @user.user_responses.joins(:question).where(questions: { free_sample: true }).distinct.count(:question_id)
    @schools = @user.subscribed_institutions
    @warrior = Plan.warrior
  end
end
