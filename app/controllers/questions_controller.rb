# app/controllers/questions_controller.rb
class QuestionsController < ApplicationController
  before_action :ensure_teacher_or_admin_access
  before_action :set_question, only: [:edit, :update]
  before_action :ensure_modification_permission, only: [:edit, :update]

  def index
    @questions = Question.includes(:user).in_order
  end

  def upload_form
    # Renders your premium Burgundy data ingestion view
  end

  def import
    file = params[:file]
    exam = params[:exam_type]
    year = params[:year]

    if file.blank? || exam.blank?
      redirect_to upload_form_questions_path, alert: "Please complete all required fields."
      return
    end

    unless file.original_filename.downcase.end_with?(".xlsx", ".xls")
      redirect_to upload_form_questions_path, alert: "Invalid format. You must upload a native Excel Workbook sheet (.xlsx or .xls)."
      return
    end

    begin
      # 🚀 PASSING EXACTLY 4 PARAMETERS: file, exam, year, creator_id
      Question.import_from_excel(file.path, exam, year, Current.user.id)

      redirect_to upload_form_questions_path, notice: "Questions for #{exam} successfully imported into your Question Bank!"
    rescue StandardError => e
      redirect_to upload_form_questions_path, alert: "Error parsing spreadsheet file: #{e.message}"
    end
  end

  def download_template
    headers = ["Q.No", "Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer", "Explanation"]
    sample_row = ["1", "Physics", "What is the formula for Acceleration?", "MA", "MV", "v/t", "MV2", "C", "Acceleration is the change in velocity per unit time (v/t)."]
    xls_data = headers.join("\t") + "\n" + sample_row.join("\t")
    send_data xls_data, filename: "upsc_officer_question_template.xls", type: "application/vnd.ms-excel; charset=utf-8"
  end

  def edit
  end

  def update
    if @question.update(question_params)
      redirect_to questions_path, notice: "Question sequence updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_question
    @question = Question.find(params[:id])
  end

  def ensure_modification_permission
    unless Current.user.admin? || @question.user_id == Current.user.id
      creator = @question.user&.email_address || "another teacher"
      redirect_to questions_path, alert: "You are not the creator of this question. Only #{creator} or an admin can edit it."
    end
  end

  def ensure_teacher_or_admin_access
    unless Current.user&.faculty?
      redirect_to dashboard_path, alert: "Access Denied: Only teachers or administrators can view this workspace area."
    end
  end

  def question_params
    params.require(:question).permit(:exam_type, :year, :q_no, :topic, :content, :option_a, :option_b, :option_c, :option_d, :correct_answer, :explanation)
  end
end
