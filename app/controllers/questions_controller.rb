# app/controllers/questions_controller.rb
class QuestionsController < ApplicationController
  include AudienceAssignment
  include ExamListing
  before_action :ensure_teacher_or_admin_access
  before_action :set_question, only: [:edit, :update]
  before_action :ensure_modification_permission, only: [:edit, :update]

  # Questions this teacher may use, one exam at a time (tabs, remembered) and one page at a time,
  # filtered by subject (topic) and who can see them
  def index
    scope = Question.visible_to(Current.user).includes(:user, :institution, :audience_grants).in_order
    @exam = remembered_exam(:question_bank)
    @topic = params[:topic].presence
    @visibility = params[:visibility].presence_in(Audience::VISIBILITIES.keys)
    scope = scope.where(topic: @topic) if @topic
    scope = scope.where(visibility: @visibility) if @visibility
    scope = scope.where(user_id: Current.user.id) if params[:mine] == "1"
    @exam_counts = exam_counts(scope)
    scope = scope.where(exam_type: @exam) if @exam

    topics = Question.visible_to(Current.user)
    topics = topics.where(exam_type: @exam) if @exam
    @topics = topics.where.not(topic: [nil, ""]).distinct.order(:topic).limit(500).pluck(:topic)
    @questions = paginate(scope)
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

    audience = Question.new(visibility: params[:visibility].presence || "public", institution_id: params[:institution_id])
    unless audience_valid?(audience)
      redirect_to upload_form_questions_path, alert: audience.errors.full_messages.to_sentence
      return
    end

    begin
      imported = Question.import_from_excel(file.path, exam, year, Current.user.id,
                                            visibility: audience.visibility, institution_id: audience.institution_id)
      imported.each { |q| apply_audience!(q) } unless audience.everyone?

      redirect_to upload_form_questions_path, notice: "Questions for #{Exam.name_for(exam)} successfully imported into your Question Bank!"
    rescue StandardError => e
      redirect_to upload_form_questions_path, alert: "Error parsing spreadsheet file: #{e.message}"
    end
  end

  def download_template
    headers = ["Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer", "Explanation"]
    sample_row = ["Physics", "What is the formula for Acceleration?", "MA", "MV", "v/t", "MV2", "C", "Acceleration is the change in velocity per unit time (v/t)."]
    xls_data = headers.join("\t") + "\n" + sample_row.join("\t")
    send_data xls_data, filename: "lakshyank_question_template.xls", type: "application/vnd.ms-excel; charset=utf-8"
  end

  # Add one question by hand (goes straight into the question bank)
  def new
    @question = Question.new(
      exam_type: Exam.normalize(params[:exam_type]) || Exam::DEFAULT.code,
      year: params[:year].presence,
      topic: params[:topic].presence,
      correct_answer: "A"
    )
  end

  def create
    @question = Question.new(question_params.merge(user: Current.user))

    if audience_valid?(@question) && @question.save
      apply_audience!(@question)
      if params[:add_another]
        redirect_to new_question_path(exam_type: @question.exam_type, year: @question.year, topic: @question.topic),
                    notice: "Saved in #{@question.topic}. Add the next one."
      else
        redirect_to questions_path, notice: "Question added to the #{@question.topic} question bank."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @question.assign_attributes(question_params)
    if audience_valid?(@question) && @question.save
      apply_audience!(@question)
      redirect_to questions_path, notice: "Question saved."
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
    params.require(:question).permit(:exam_type, :year, :topic, :content, :option_a, :option_b, :option_c, :option_d, :correct_answer, :explanation,
                                     :visibility, :institution_id)
  end
end
