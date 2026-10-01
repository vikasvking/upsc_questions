# The "Question Library" in the test form (teacher and admin): one exam at a time, newest first,
# 50 questions per page with "Load more", searched on the server. It is loaded into a Turbo Frame,
# so the test form opens fast however big the question bank grows.
#
#   GET /question_library?exam=CBSE_XII&q=matrix&page=2
#   all=1 (admin test form): every question in the bank, for admins and sub-admins who manage tests
class QuestionLibrariesController < ApplicationController
  PER_PAGE = 50

  before_action :ensure_faculty

  def show
    @exam  = Exam.normalize(params[:exam])
    @query = params[:q].to_s.strip.first(100)
    @page  = [params[:page].to_i, 1].max

    scope = library_scope
    scope = scope.where(exam_type: @exam) if @exam
    if @query.present?
      like = "%#{Question.sanitize_sql_like(@query)}%"
      scope = scope.where("questions.content ILIKE :q OR questions.topic ILIKE :q", q: like)
    end

    rows = scope.order(id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = rows.size > PER_PAGE
    @questions = rows.first(PER_PAGE)
    @total = scope.count if @page == 1

    render layout: false
  end

  private

  def library_scope
    if params[:all] == "1" && Current.user.can_manage?(:tests)
      Question.all
    else
      Question.visible_to(Current.user) # questions this teacher may use
    end
  end

  def ensure_faculty
    head :forbidden unless Current.user&.faculty?
  end
end
