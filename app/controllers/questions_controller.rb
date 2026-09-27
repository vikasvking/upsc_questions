class QuestionsController < ApplicationController
  def index
    # 🚀 FIX: Correctly formats the SQL casting block without stray characters
    @questions = Question.order(year: :desc).order(Arel.sql("q_no::integer ASC"))
  end

  def upload_form
    # Renders the admin ingestion template view
  end

  def import
    if params[:file].present? && params[:year].present?
      begin
        Question.import_from_excel(params[:file].path, params[:year])
        redirect_to questions_path, notice: "Questions for #{params[:year]} imported successfully."
      rescue StandardError => e
        redirect_to upload_form_questions_path, alert: "Error importing file: #{e.message}"
      end
    else
      redirect_to upload_form_questions_path, alert: "Please provide both an Excel file and a year."
    end
  end
end
