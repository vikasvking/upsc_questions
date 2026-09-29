# app/models/student_progress.rb
# Topic-by-topic progress for one student.
#
# Rules:
# - A question is "solved" once the student has answered it correctly at least once (in any practice or test).
# - An "attempt" is one answer to one question (skips don't count). Re-answering the same question
#   inside one test replaces the earlier answer, so it counts once per test/practice run.
# - A topic is "completed" when every question in it is solved.
class StudentProgress
  TopicStat = Struct.new(:topic, :total, :solved, :attempted_questions, :attempts, :correct_attempts, keyword_init: true) do
    def completed?   = total.positive? && solved >= total
    def progress_pct = total.positive? ? (solved * 100.0 / total).round : 0
    def accuracy_pct = attempts.positive? ? (correct_attempts * 100.0 / attempts).round(1) : nil
    def started?     = attempts.positive?
  end

  QuestionStat = Struct.new(:attempts, :correct_attempts, :last_response, keyword_init: true) do
    def attempted? = attempts.positive?
    def solved?    = correct_attempts.positive?
  end

  attr_reader :user, :questions

  # Only questions this student may see; optionally only some exams (their own by default on the pages)
  def initialize(user, exams: nil)
    @user = user
    @questions = Question.available_to(user)
    @questions = @questions.where(exam_type: exams) if exams.present?
  end

  # All topics, alphabetical, with this student's numbers (2 queries)
  def topic_stats
    @topic_stats ||= begin
      totals = questions.where.not(topic: [nil, ""]).group(:topic).order(:topic).count

      mine = user.user_responses.joins(:question).where(question_id: questions.select(:id))
                 .where.not(chosen_option: "SKIPPED")
                 .group("questions.topic")
                 .pluck(Arel.sql("questions.topic"),
                        Arel.sql("COUNT(*)"),
                        Arel.sql("COUNT(*) FILTER (WHERE user_responses.is_correct)"),
                        Arel.sql("COUNT(DISTINCT user_responses.question_id)"),
                        Arel.sql("COUNT(DISTINCT user_responses.question_id) FILTER (WHERE user_responses.is_correct)"))
                 .to_h { |topic, attempts, correct, attempted_q, solved| [topic, [attempts, correct, attempted_q, solved]] }

      totals.map do |topic, total|
        attempts, correct, attempted_q, solved = mine[topic] || [0, 0, 0, 0]
        TopicStat.new(topic: topic, total: total, solved: solved, attempted_questions: attempted_q,
                      attempts: attempts, correct_attempts: correct)
      end
    end
  end

  def topic_stat(topic)
    topic_stats.find { |t| t.topic == topic }
  end

  def completed_topics = topic_stats.select(&:completed?)
  def topics_completed_count = completed_topics.size

  # Per-question numbers for a list of questions (2 queries)
  def question_stats(questions)
    ids = questions.map(&:id)

    counts = user.user_responses.where(question_id: ids)
                 .where.not(chosen_option: "SKIPPED")
                 .group(:question_id)
                 .pluck(:question_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE is_correct)"))
                 .to_h { |qid, attempts, correct| [qid, [attempts, correct]] }

    latest = user.user_responses.where(question_id: ids)
                 .where.not(chosen_option: "SKIPPED")
                 .order(:updated_at)
                 .index_by(&:question_id)

    ids.to_h do |qid|
      attempts, correct = counts[qid] || [0, 0]
      [qid, QuestionStat.new(attempts: attempts, correct_attempts: correct, last_response: latest[qid])]
    end
  end

  # Weakest started topic (lowest accuracy, needs 5+ attempts); otherwise the first topic not started yet
  def focus_topic
    started = topic_stats.select { |t| t.attempts >= 5 && !t.completed? }
    started.min_by { |t| [t.accuracy_pct, -t.attempts] } || topic_stats.find { |t| !t.started? }
  end
end
