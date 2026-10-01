# A question as the public home page shows it (see HomePage). Free samples carry their answer, so visitors can
# try them on the page; other questions show only their text and options, with a sign-up link.
class HomeQuestion
  MIN_ANSWERS_FOR_STATS = 20 # below this the "got this right" share would mislead ("100% of 1")

  # Shown on the answer sheet when no free sample question exists yet
  EXAMPLE = {
    exam_type: "UPSC_PRELIMS", topic: "Polity", free_sample: true, correct_answer: "D",
    content: "Which Article of the Constitution gives the Right to Constitutional Remedies?",
    option_a: "Article 14", option_b: "Article 19", option_c: "Article 21", option_d: "Article 32",
    explanation: "Article 32 lets anyone go straight to the Supreme Court to enforce their Fundamental Rights."
  }.freeze

  attr_reader :question, :answers

  delegate :id, :content, :topic, :year, :explanation, :correct_answer, :created_at, :exam, to: :question

  # Wraps questions with how often their answers were right (one query for all of them)
  def self.list(questions)
    questions = questions.to_a
    stats = UserResponse.where(question_id: questions.map(&:id)).where.not(chosen_option: "SKIPPED")
                        .group(:question_id)
                        .pluck(:question_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE is_correct)"))
                        .to_h { |id, all, right| [id, [all, right]] }
    questions.map { |q| new(q, *stats.fetch(q.id, [0, 0])) }
  end

  # The newest free sample, or the example when there is none
  def self.sample(question)
    question ? list([question]).first : new(Question.new(EXAMPLE), 0, 0, example: true)
  end

  def initialize(question, answers, right, example: false)
    @question = question
    @answers = answers
    @right = right
    @example = example
  end

  def example? = @example
  def free? = question.free_sample?

  # [[letter, text], ...] for the options that have text
  def options = question.option_letters.map { |letter| [letter, question.option_text(letter)] }

  def correct_text = question.option_text(correct_answer)
  def where_from = [exam&.name, topic, year].compact_blank.join(", ")

  def show_stats? = answers >= MIN_ANSWERS_FOR_STATS
  def right_pct = answers.positive? ? (@right * 100.0 / answers).round : 0

  # "+2, −0.67" in the margin, the way question papers print the marks
  def marks_label
    return nil unless exam
    right = exam.correct.round(2).to_s.sub(/\.0\z/, "")
    wrong = exam.wrong.round(2).to_s.sub(/\.0\z/, "")
    exam.wrong.zero? ? "+#{right}" : "+#{right}, −#{wrong}"
  end
end
