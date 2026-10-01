# Long lists of tests and questions: one exam at a time (the choice is remembered per list) and
# one page at a time, so the pages stay fast however big the question bank grows.
#
#   @exam = remembered_exam(:admin_questions)  # ?exam=CBSE_XII picks an exam, ?exam=all shows every exam
#   @exam_counts = exam_counts(scope)          # rows per exam, for the exam tabs
#   @questions = paginate(scope)               # ?page=2, ?per=25|50|100
module ExamListing
  extend ActiveSupport::Concern

  PER_PAGE_CHOICES = [25, 50, 100].freeze
  DEFAULT_PER_PAGE = 50

  private

  # The exam chosen on this list, or nil for every exam. Kept in the session so the list
  # opens on the same exam next time.
  def remembered_exam(list)
    chosen = (session[:list_exams] || {}).to_h
    if params.key?(:exam)
      code = Exam.normalize(params[:exam])
      if code
        chosen[list.to_s] = code
      else
        chosen.delete(list.to_s)
      end
      session[:list_exams] = chosen
    end
    Exam.normalize(chosen[list.to_s])
  end

  # Rows per page: ?per=25|50|100, remembered in the session
  def per_page
    per = params[:per].to_i
    if PER_PAGE_CHOICES.include?(per)
      session[:list_per_page] = per
    else
      per = session[:list_per_page].to_i
    end
    PER_PAGE_CHOICES.include?(per) ? per : DEFAULT_PER_PAGE
  end

  # One page of a list (?page=2). Reads one extra row to know whether there is a next page.
  def paginate(scope, per: per_page)
    @per_page = per
    @page = [params[:page].to_i, 1].max
    rows = scope.offset((@page - 1) * per).limit(per + 1).to_a
    @next_page = rows.size > per ? @page + 1 : nil
    rows.first(per)
  end

  # { "CBSE_XII" => 70, "NEET" => 12, ... } for the exam tabs (one GROUP BY query, every other filter applied)
  def exam_counts(scope)
    scope.unscope(:order, :includes).group(:exam_type).count
         .each_with_object(Hash.new(0)) { |(code, n), counts| counts[Exam.normalize(code) || code.to_s] += n }
  end
end
