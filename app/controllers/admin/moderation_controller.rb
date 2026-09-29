# Admin → Ratings & reports: hide abusive rating comments and answer reported problems on any question
class Admin::ModerationController < Admin::BaseController
  self.admin_area = :ratings

  def index
    @tab = params[:tab] == "ratings" ? "ratings" : "reports"
    if @tab == "reports"
      scope = QuestionReport.includes(question: :user).includes(:user).open_first
      @status = params[:status].presence_in(QuestionReport::STATUSES.keys)
      scope = scope.where(status: @status) if @status
      @reports = paginate(scope)
    else
      scope = Rating.where.not(comment: nil).includes(:user, :rateable).newest_first
      scope = scope.where(comment_hidden_at: nil) unless params[:hidden] == "1"
      @ratings = paginate(scope)
    end
    @open_reports = QuestionReport.unresolved.count
  end

  # PATCH /admin/moderation/:id/hide_comment (and unhide)
  def hide_comment
    rating = Rating.find(params[:id])
    rating.update_columns(comment_hidden_at: Time.current, comment_hidden_by_id: Current.user.id)
    log!("hide_rating_comment", record: rating, label: rating.comment.to_s.truncate(80), reason: reason_param)
    redirect_back fallback_location: admin_moderation_index_path(tab: "ratings"), notice: "Comment hidden. The stars still count."
  end

  def unhide_comment
    rating = Rating.find(params[:id])
    rating.update_columns(comment_hidden_at: nil, comment_hidden_by_id: nil)
    log!("unhide_rating_comment", record: rating, label: rating.comment.to_s.truncate(80))
    redirect_back fallback_location: admin_moderation_index_path(tab: "ratings"), notice: "Comment shown again."
  end
end
