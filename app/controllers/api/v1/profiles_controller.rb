# GET   /api/v1/me    -> the signed-in user (with any account step still to finish on the website)
# PATCH /api/v1/me    name, exam_codes[] (students), target_exam (students), subjects (teachers, "Physics, Chemistry")
# GET   /api/v1/exams -> every exam with its marking scheme
module Api
  module V1
    class ProfilesController < BaseController
      def show
        render json: { user: user_json(current_user) }
      end

      # Same rules as the website's profile page (email, password and date of birth stay on the website)
      def update
        user = current_user
        user.name = params[:name] if params.key?(:name)

        if user.student? && params.key?(:exam_codes)
          exams = Array(params[:exam_codes]).filter_map { |c| Exam.normalize(c) }.uniq
          return render_error("invalid", "Pick at least one exam you are preparing for") if exams.empty?
        end
        if user.teacher? && params.key?(:subjects)
          subjects = Array(params[:subjects]).flat_map { |s| s.to_s.split(",") }.map(&:squish).compact_blank
          return render_error("invalid", "Add at least one subject you teach") if subjects.empty?
        end
        target = Exam.normalize(params[:target_exam]) if user.student? && params[:target_exam].present?
        return render_error("invalid", "Please pick an exam from the list.") if user.student? && params[:target_exam].present? && target.nil?

        return render_error("invalid", user.errors.full_messages.to_sentence) unless user.save

        user.replace_exams!(exams) if exams
        user.replace_subjects!(subjects) if subjects
        if target
          user.replace_exams!(user.exam_codes | [target])
          user.update_column(:target_exam, target)
        end
        render json: { user: user_json(user.reload) }
      end

      def exams
        render json: { exams: Exam.all.map { |e| exam_json(e.code) } }
      end
    end
  end
end
