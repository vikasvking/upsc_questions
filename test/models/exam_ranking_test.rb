require "test_helper"

class ExamRankingTest < ActiveSupport::TestCase
  def answer(user, question, choice)
    user.user_responses.create!(question: question, chosen_option: choice,
                                is_correct: choice == question.correct_answer,
                                duration_seconds: 30, test_session_token: SecureRandom.hex(4))
  end

  test "students are ranked only within one exam" do
    jee_q = Question.create!(topic: "Physics", content: "JEE question", exam_type: "JEE_MAIN", correct_answer: "A", option_a: "x")
    answer(users(:one), questions(:one), "A") # UPSC
    answer(users(:two), jee_q, "A")           # JEE Main

    assert_equal [users(:one).id], Leaderboard.build_rows("UPSC_PRELIMS").map(&:user_id)
    assert_equal [users(:two).id], Leaderboard.build_rows("JEE_MAIN").map(&:user_id)
    assert_equal 1, Leaderboard.comparison_for(users(:two), "JEE_MAIN")[:rank]
    assert_nil Leaderboard.comparison_for(users(:two), "UPSC_PRELIMS")[:rank]
  end

  test "rank defaults to the chosen exam, else the most practised exam" do
    users(:one).user_exams.delete_all
    jee_q = Question.create!(topic: "Physics", content: "JEE question", exam_type: "JEE_MAIN", correct_answer: "A", option_a: "x")
    answer(users(:one), jee_q, "A")
    answer(users(:one), jee_q, "B")
    answer(users(:one), questions(:one), "A")
    assert_equal "JEE_MAIN", users(:one).ranking_exam_code

    users(:one).update!(target_exam: "NEET")
    assert_equal "NEET", users(:one).ranking_exam_code
  end

  test "a teacher test uses its exam's marking" do
    test = test_sessions(:one) # questions one (answer A) and two (answer B)
    test.update!(exam_type: "JEE_MAIN")
    attempt = users(:one).test_attempts.create!(test_session: test, started_at: 1.hour.ago)
    answer_in(attempt, questions(:one), "A")
    answer_in(attempt, questions(:two), "C")
    attempt.update!(finished_at: 10.minutes.ago)

    result = test.rankings.first
    assert_equal 3.0, result.marks   # +4 - 1
    assert_equal 8.0, result.max_marks
  end

  def answer_in(attempt, question, choice)
    attempt.user.user_responses.create!(question: question, chosen_option: choice,
                                        is_correct: choice == question.correct_answer, test_session_token: attempt.token)
  end
end
