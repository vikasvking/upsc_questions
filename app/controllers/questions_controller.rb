class QuestionsController < ApplicationController
  def index
    @questions = Question.order(year: :desc).order(Arel.sql("q_no::integer ASC"))
  end

  def upload_form
    # Renders your premium Burgundy data ingestion view
  end
  # 🚀 NEW METHOD: Compiles and streams a native XML Excel Workbook document (.xlsx standard compatible)
  # 🚀 FIXED METHOD: Compiles a clean spreadsheet table matrix that Excel opens instantly with no extension warnings
  # 🚀 FIXED PRODUCTION METHOD: Compiles a clean tab-delimited Excel template that Excel and Roo open with zero errors
def download_template
  # Define our required system column sequences
  headers = ["Q.No", "Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer", "Explanation"]

  # Provide an illustrative row example for the admin to follow
  sample_row = ["1", "Indian Polity", "Who is the executive head of the State in India?", "Governor", "President", "Prime Minister", "Chief Minister", "A", "Article 154 states that the executive power of the State is vested in the Governor."]

  # Join column cells with a literal tab character ("\t") so Excel splits them into distinct columns instantly
  xls_data = headers.join("\t") + "\n" + sample_row.join("\t")

  # Stream out with an explicit .xls attachment filename token
  send_data xls_data, filename: "upsc_officer_question_template.xls", type: "application/vnd.ms-excel; charset=utf-8"
end


  def import
    file = params[:file]
    exam = params[:exam_type]
    year = params[:year]

    if file.blank? || exam.blank?
      redirect_to upload_form_questions_path, alert: "Please complete all required fields."
      return
    end

    # 🚀 EXCEL ENFORCEMENT GATE: Accepts both standard Excel spreadsheet formats seamlessly
    unless file.original_filename.end_with?('.xlsx') || file.original_filename.end_with?('.xls')
      redirect_to upload_form_questions_path, alert: "Invalid format. You must upload a native Excel Workbook sheet (.xlsx or .xls)."
      return
    end

    begin
      Question.import_from_excel(file.path, exam, year)
      redirect_to upload_form_questions_path, notice: "Questions for #{exam} successfully imported into your Question Bank!"
    rescue StandardError => e
      redirect_to upload_form_questions_path, alert: "Error parsing spreadsheet file: #{e.message}"
    end
  end

end
