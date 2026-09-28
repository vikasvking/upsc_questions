require "test_helper"

class StudentProgressTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @q1 = questions(:one) # Physics, answer A
    @q2 = questions(:two) # Physics, answer B
  end

  def answer(question, choice)
    @user.user_responses.create!(question: question, chosen_option: choice,
                                 is_correct: choice == question.correct_answer,
                                 test_session_token: SecureRandom.hex(4))
  end

  test "topic is completed only when every question has been answered correctly" do
    answer(@q1, "A")
    answer(@q2, "C") # wrong
    stat = StudentProgress.new(@user).topic_stat("Physics")
    assert_equal 1, stat.solved
    assert_not stat.completed?
    assert_equal 50, stat.progress_pct

    answer(@q2, "B") # now right
    stat = StudentProgress.new(@user).topic_stat("Physics")
    assert stat.completed?
    assert_equal 3, stat.attempts
    assert_equal 1, StudentProgress.new(@user).topics_completed_count
  end

  test "counts how many times each question was attempted, ignoring skips" do
    answer(@q1, "C")
    answer(@q1, "A")
    answer(@q1, "SKIPPED")
    stats = StudentProgress.new(@user).question_stats([@q1, @q2])

    assert_equal 2, stats[@q1.id].attempts
    assert_equal 1, stats[@q1.id].correct_attempts
    assert_equal "A", stats[@q1.id].last_response.chosen_option
    assert_not stats[@q2.id].attempted?
  end
end
