class Admin::QuestionsController < Admin::BaseController
  self.admin_area = :questions
  before_action :set_question, only: [:edit, :update, :destroy]

  def index
    scope = Question.includes(:user).in_order
    @exam    = Exam.normalize(params[:exam])
    @topic   = params[:topic].presence
    @teacher = params[:teacher].presence
    scope = scope.where(exam_type: @exam) if @exam
    scope = scope.where(topic: @topic) if @topic
    scope = @teacher == "none" ? scope.where(user_id: nil) : scope.where(user_id: @teacher) if @teacher
    scope = scope.where("content ILIKE ?", "%#{Question.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?

    @topics   = Question.where.not(topic: [nil, ""]).distinct.order(:topic).pluck(:topic)
    @teachers = User.where(id: Question.select(:user_id)).order(:email_address)
    @questions = paginate(scope)
    @test_counts = TestQuestion.where(question_id: @questions.map(&:id)).group(:question_id).count
  end

  def new
    @question = Question.new(exam_type: Exam.normalize(params[:exam]) || Exam::DEFAULT.code, correct_answer: "A")
  end

  def create
    @question = Question.new(question_params.merge(user: Current.user))
    if @question.save
      log!("create_question", record: @question, label: @question.content)
      redirect_to admin_questions_path, notice: "Question added to #{@question.exam.name} · #{@question.topic}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @locked_tests = @question.locked_tests
  end

  # Changing a question used by a locked test needs a reason (the teacher's request).
  # A new correct answer re-marks every saved answer (see Question#remark_saved_answers).
  def update
    @locked_tests = @question.locked_tests
    @question.assign_attributes(question_params)

    if @locked_tests.any? && @question.changed? && reason_param.blank?
      @question.errors.add(:base, "This question is in a locked test. Write the reason (e.g. the teacher's request) to change it.")
      render :edit, status: :unprocessable_entity
      return
    end

    changes = @question.changes.except("updated_at").transform_values { |from, to| { "from" => from, "to" => to } }
    answer_changed = @question.correct_answer_changed?
    if @question.save
      log!(@locked_tests.any? ? "update_locked_test" : "update_question", record: @question, label: @question.content,
           reason: reason_param, details: changes.merge("locked_tests" => @locked_tests.map(&:title)))
      notice = "Question saved."
      notice += " Every saved answer to it was re-marked with the new answer key." if answer_changed
      redirect_to admin_questions_path, notice: notice
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    locked = @question.locked_tests
    answers = @question.user_responses.count
    if (locked.any? || answers.positive?) && (!confirmed?("delete") || reason_param.blank?)
      redirect_to edit_admin_question_path(@question),
                  alert: "This question has #{answers} saved answer(s)#{locked.any? ? " and is in a locked test" : ""}. Type delete and give a reason to remove it."
      return
    end

    label = @question.content
    details = { exam: @question.exam.name, topic: @question.topic, answers_deleted: answers,
                removed_from_tests: @question.test_sessions.map(&:title) }
    @question.destroy!
    log!("delete_question", label: label, reason: reason_param, details: details)
    redirect_to admin_questions_path, notice: "Question deleted."
  end

  private

  def set_question
    @question = Question.find(params[:id])
  end

  def question_params
    params.require(:question).permit(:exam_type, :year, :topic, :content, :option_a, :option_b, :option_c, :option_d, :correct_answer, :explanation)
  end
end
