# Everything the public home page shows. Also used to show the page again, with the visitor's
# text kept, when the footer contact form has a mistake (ContactMessagesController).
module HomePage
  extend ActiveSupport::Concern

  private

  FRESH_QUESTIONS = 6

  def load_home_page
    public_questions = Question.visible_to(nil)

    # The answer sheet at the top: the newest free sample (anyone may answer those), or an example
    @sample_question = HomeQuestion.sample(public_questions.where(free_sample: true).order(created_at: :desc, id: :desc).first)

    # Always the newest questions in the Question Bank
    @fresh_questions = HomeQuestion.list(public_questions.order(created_at: :desc, id: :desc).limit(FRESH_QUESTIONS))

    # Exams with their question counts (every exam, without counts, until questions are added)
    counts = public_questions.group(:exam_type).count
    @exam_counts = Exam.all.filter_map { |e| [e, counts[e.code]] if counts[e.code].to_i.positive? }
    @exam_counts = Exam.all.map { |e| [e, nil] } if @exam_counts.empty?

    # Topper table: one exam at a time, only exams with at least 3 ranked students
    @topper_tables = Leaderboard.exam_codes_with_questions.filter_map do |code|
      rows = Leaderboard.rows(code)
      [Exam::BY_CODE[code], rows] if rows.size >= 3
    end
    @topper_exam = @topper_tables.find { |e, _| e.code == Exam.normalize(params[:exam]) } || @topper_tables.first

    # Pricing straight from Admin → Plans (only the plans offered now)
    plans = Plan.active.ordered.to_a
    @school_plans  = plans.select(&:school?)
    @student_plans = plans.reject(&:school?)

    # The footer contact form works only while email is on (Admin → Email)
    @contact_open = Mailing.enabled?
    @contact_message ||= ContactMessage.new(topic: params[:topic].presence_in(ContactMessage::TOPICS.keys) || "question")
  end
end
