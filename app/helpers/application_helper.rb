module ApplicationHelper
  # "UPSC_PRELIMS" -> "UPSC Prelims" (see Exam)
  def exam_name(code)
    Exam.name_for(code)
  end
end
