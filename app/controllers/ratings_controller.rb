# Students rate a test they submitted, or a teacher whose test they took. Rating again replaces the old rating.
class RatingsController < ApplicationController
  # POST /ratings  rateable=test|teacher  rateable_id=...  rating[stars] rating[comment]
  def create
    rateable = find_rateable
    return redirect_back(fallback_location: root_path, alert: "Not found.") unless rateable

    unless allowed?(rateable)
      message = Current.user.can_rate? ? "You can rate only tests you submitted, and teachers whose tests you took." : "Please confirm your email before rating."
      return redirect_back(fallback_location: root_path, alert: message)
    end

    rating = Rating.find_or_initialize_by(rateable: rateable, user: Current.user)
    rating.assign_attributes(params.require(:rating).permit(:stars, :comment))
    rating.comment_hidden_at = nil if rating.comment_changed? # a new comment starts visible again
    if rating.save
      redirect_back fallback_location: root_path, notice: "Thanks for your rating."
    else
      redirect_back fallback_location: root_path, alert: "Rating not saved: #{rating.errors.full_messages.to_sentence}"
    end
  end

  # DELETE /ratings/:id (your own)
  def destroy
    Current.user.ratings.find(params[:id]).destroy!
    redirect_back fallback_location: root_path, notice: "Your rating was removed."
  end

  private

  def find_rateable
    case params[:rateable]
    when "test" then TestSession.find_by(id: params[:rateable_id])
    when "teacher" then User.teacher.find_by(id: params[:rateable_id])
    end
  end

  def allowed?(rateable)
    rateable.is_a?(TestSession) ? Rating.can_rate_test?(Current.user, rateable) : Rating.can_rate_teacher?(Current.user, rateable)
  end
end
