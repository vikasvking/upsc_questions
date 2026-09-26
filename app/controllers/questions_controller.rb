# app/controllers/questions_controller.rb
class QuestionsController < ApplicationController
  def index
    @questions = Question.order(year: :desc, q_no: :asc)
  end

  def upload_form
  end

  def import
    if params[:file].present? && params[:year].present?
      begin
        Question.import_from_excel(params[:file].tempfile.path, params[:year])
        redirect_to questions_path, notice: "Questions for #{params[:year]} imported successfully."
      rescue StandardError => e
        redirect_to upload_form_questions_path, alert: "Error importing file: #{e.message}"
      end
    else
      redirect_to upload_form_questions_path, alert: "Please provide both an Excel file and a year."
    end
  end
end
