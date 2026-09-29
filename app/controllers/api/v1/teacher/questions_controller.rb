# Questions a teacher may use (and edit their own), with the same rules as the website.
#   GET   /api/v1/teacher/questions?exam=&topic=&q=&mine=1&page=1 -> 50 per page
#   GET   /api/v1/teacher/questions/:id
#   POST  /api/v1/teacher/questions      question[exam_type, year, topic, content, option_a..option_d, correct_answer,
#                                                 explanation, visibility, institution_id], audience[...]
#   PATCH /api/v1/teacher/questions/:id  same fields (own questions; admins any)
module Api
  module V1
    module Teacher
      class QuestionsController < BaseController
        PER_PAGE = 50

        before_action :set_question, only: [:show, :update]

        def index
          scope = Question.visible_to(current_user).includes(:user, :institution, :audience_grants).in_order
          exam = Exam.normalize(params[:exam])
          scope = scope.where(exam_type: exam) if exam
          scope = scope.where(topic: params[:topic]) if params[:topic].present?
          scope = scope.where(user_id: current_user.id) if params[:mine] == "1"
          if params[:q].present?
            scope = scope.where("questions.content ILIKE ?", "%#{Question.sanitize_sql_like(params[:q].strip)}%")
          end

          page = [params[:page].to_i, 1].max
          rows = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
          topics = Question.visible_to(current_user).where.not(topic: [nil, ""]).distinct.order(:topic).pluck(:topic)
          render json: { questions: rows.first(PER_PAGE).map { |q| question_full_json(q) },
                         next_page: rows.size > PER_PAGE ? page + 1 : nil, topics: topics }
        end

        def show
          render json: { question: question_full_json(@question).merge(audience: audience_json(@question)) }
        end

        def create
          question = Question.new(question_params.merge(user: current_user))
          if audience_valid?(question) && question.save
            apply_audience!(question)
            render json: { question: question_full_json(question), warning: warning, message: "Question added to #{question.topic}." }, status: :created
          else
            render_error("invalid", errors_of(question))
          end
        end

        def update
          unless editable?(@question)
            return render_error("not_yours", "Only the teacher who added this question or an admin can edit it.", status: :forbidden)
          end

          @question.assign_attributes(question_params)
          if audience_valid?(@question) && @question.save
            apply_audience!(@question)
            render json: { question: question_full_json(@question), warning: warning, message: "Question saved." }
          else
            render_error("invalid", errors_of(@question))
          end
        end

        private

        def set_question
          @question = Question.visible_to(current_user).find(params[:id])
        end

        def editable?(question) = current_user.admin? || question.user_id == current_user.id

        def question_params
          params.require(:question).permit(:exam_type, :year, :topic, :content, :option_a, :option_b, :option_c, :option_d,
                                           :correct_answer, :explanation, :visibility, :institution_id)
        end

        def question_full_json(q)
          { id: q.id, exam: q.exam_type, year: q.year, topic: q.topic, content: q.content,
            options: { "A" => q.option_a, "B" => q.option_b, "C" => q.option_c, "D" => q.option_d },
            correct_answer: q.correct_answer, explanation: q.explanation,
            visibility: q.visibility, audience: q.audience_label, institution_id: q.institution_id,
            author: q.user&.display_name || "Deleted teacher", mine: q.user_id == current_user.id, editable: editable?(q) }
        end
      end
    end
  end
end
