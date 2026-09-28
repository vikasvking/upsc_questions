require "test_helper"

class LeaderboardTest < ActiveSupport::TestCase
  def answer(user, question, choice, seconds: 30)
    user.user_responses.create!(question: question, chosen_option: choice,
                                is_correct: choice == question.correct_answer,
                                duration_seconds: seconds, test_session_token: SecureRandom.hex(4))
  end

  test "ranks students by questions solved and ignores teachers" do
    answer(users(:one), questions(:one), "A")
    answer(users(:one), questions(:two), "B")
    answer(users(:two), questions(:one), "A")
    answer(users(:teacher), questions(:one), "A")

    rows = Leaderboard.build_rows
    assert_equal [users(:one).id, users(:two).id], rows.map(&:user_id)
    assert_equal 2, rows.first.solved
    assert_equal 1, rows.first.topics_completed # both Physics questions solved
  end

  test "comparison gives rank, top average and platform average" do
    answer(users(:one), questions(:one), "A", seconds: 20)
    answer(users(:two), questions(:one), "C", seconds: 40)

    cmp = Leaderboard.comparison_for(users(:two))
    assert_equal 2, cmp[:rank]
    assert_equal 2, cmp[:students]
    assert_equal 0.0, cmp[:me].accuracy
    assert_equal 50.0, cmp[:platform][:accuracy] # (100 + 0) / 2
    assert_equal 30.0, cmp[:platform][:avg_seconds]
  end
end
