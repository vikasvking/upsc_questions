# Question Bank: practise single questions by topic (same rules as the website).
#   GET  /api/v1/question_bank?exams=all                  -> topics with my progress (my exams by default)
#   GET  /api/v1/question_bank/topic?name=Physics&filter=all|solved|wrong|not_attempted
#   POST /api/v1/question_bank/answer  question_id, choice=A|B|C|D, duration_seconds
module Api
  module V1
    class QuestionBankController < BaseController
      FILTERS = %w[all solved wrong not_attempted].freeze

      before_action :require_student!
      before_action :require_ready_account!

      def index
        all_exams = params[:exams] == "all" || current_user.exam_codes.empty?
        progress = StudentProgress.new(current_user, exams: all_exams ? nil : current_user.exam_codes)
        focus = progress.focus_topic
        render json: {
          all_exams: all_exams,
          free_tier: current_user.free_tier?,
          focus_topic: focus&.topic,
          topics: progress.topic_stats.map { |t| topic_json(t) }
        }
      end

      def topic
        name = params[:name].to_s
        progress = StudentProgress.new(current_user) # every visible question of the topic, whichever exam
        stat = progress.topic_stat(name)
        return render_error("not_found", "Topic not found.", status: :not_found) unless stat

        questions = progress.questions.where(topic: name).in_order.to_a
        stats = progress.question_stats(questions)
        filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"

        render json: {
          topic: topic_json(stat),
          filter: filter,
          filter_counts: FILTERS.to_h { |f| [f, questions.count { |q| matches?(stats[q.id], f) }] },
          questions: questions.each_with_index.filter_map do |q, i|
            next unless matches?(stats[q.id], filter)
            practice_question_json(q, stats[q.id], number: i + 1)
          end
        }
      end

      def answer
        question = Question.available_to(current_user).find(params[:question_id])
        choice = params[:choice].to_s.strip.upcase
        return render_error("no_choice", "Pick an option first.") unless Question::ANSWER_KEYS.include?(choice)

        if current_user.free_tier? && current_user.user_responses.exists?(question: question)
          return render_error("free_limit",
                              "Free members can answer each sample question once. Join your school's plan (Plus) or become a Warrior to practise more.",
                              status: :forbidden, upgrade: upgrade_json(current_user))
        end

        correct = choice == question.correct_answer
        current_user.user_responses.create!(question: question, chosen_option: choice, is_correct: correct,
                                            duration_seconds: params[:duration_seconds].to_i.clamp(0, 3600),
                                            test_session_token: nil) # single-question practice, not tied to a test

        progress = StudentProgress.new(current_user)
        render json: {
          correct: correct,
          question: practice_question_json(question, progress.question_stats([question])[question.id]),
          topic: (stat = progress.topic_stat(question.topic)) ? topic_json(stat) : nil
        }
      end

      private

      def topic_json(t)
        { name: t.topic, total: t.total, solved: t.solved, attempted_questions: t.attempted_questions, attempts: t.attempts,
          accuracy_pct: t.accuracy_pct, progress_pct: t.progress_pct, completed: t.completed? }
      end

      # The answer and explanation appear once the student has attempted the question (as on the website)
      def practice_question_json(question, stat, number: nil)
        attempted = stat.attempted?
        question_json(question, number: number).merge(
          attempts: stat.attempts,
          solved: stat.solved?,
          last_choice: stat.last_response&.chosen_option,
          correct_answer: attempted ? question.correct_answer : nil,
          explanation: attempted ? question.explanation : nil
        )
      end

      def matches?(stat, filter)
        case filter
        when "solved"        then stat.solved?
        when "wrong"         then stat.attempted? && !stat.solved?
        when "not_attempted" then !stat.attempted?
        else true
        end
      end
    end
  end
end
