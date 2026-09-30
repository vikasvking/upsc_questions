require "test_helper"

# Rankings and the teachers' live panel are worked out once and shared (see TestSession, "speed" section).
# Sharing is off in other tests; these turn it on.
class SharedResultsTest < ActiveSupport::TestCase
  setup do
    TestSession.clear_shared!
    TestSession.share_results = true
    @test = test_sessions(:one) # questions one (answer A) and two (answer B)
  end

  teardown do
    TestSession.share_results = false
    TestSession.clear_shared!
  end

  def submit(user, answers, finished_ago: 10.minutes)
    attempt = user.test_attempts.create!(test_session: @test, started_at: 1.hour.ago)
    answers.each do |question, choice|
      user.user_responses.create!(question: question, chosen_option: choice, is_correct: choice == question.correct_answer,
                                  test_session_token: attempt.token)
    end
    attempt.update!(finished_at: finished_ago.ago)
    attempt
  end

  test "the ranking is reused while nothing changes" do
    submit(users(:one), { questions(:one) => "A" })
    first = @test.rankings
    assert first.frozen?
    assert_same first, TestSession.find(@test.id).rankings
  end

  test "a student who just submitted always finds their own rank; others may see the ranking up to 15 seconds old" do
    one = submit(users(:one), { questions(:one) => "A" })
    before = @test.rankings(for_attempt: one)
    assert_equal [one], before.map(&:attempt)

    two = submit(users(:two), { questions(:one) => "A", questions(:two) => "B" })
    assert_same before, @test.rankings                  # a teacher or card list: shared copy is still fresh
    mine = @test.rankings(for_attempt: two)             # student two's result page: worked out again
    assert_equal [two, one], mine.map(&:attempt)
    assert_same mine, @test.rankings                    # and that fresh copy is now the shared one
  end

  test "a change after the reuse window is picked up" do
    submit(users(:one), { questions(:one) => "A" })
    assert_equal 1, @test.rankings.size
    submit(users(:two), { questions(:one) => "A" })
    travel 16.seconds do
      assert_equal 2, @test.rankings.size # fingerprint changed and the shared copy is too old
    end
  end

  test "attempts whose time ran out are submitted before ranking" do
    expired = users(:one).test_attempts.create!(test_session: @test, started_at: 2.hours.ago)
    running = users(:two).test_attempts.create!(test_session: @test)
    @test.rankings
    assert expired.reload.finished?
    assert_not running.reload.finished?
  end

  test "strict tests: only silent students are blocked" do
    strict = test_sessions(:two)
    strict.update!(strict_mode: true, ends_at: 2.hours.from_now)
    silent = users(:one).test_attempts.create!(test_session: strict)
    silent.update_column(:last_seen_at, 3.minutes.ago)
    online = users(:two).test_attempts.create!(test_session: strict)
    online.update_column(:last_seen_at, 10.seconds.ago)

    strict.block_silent_students!
    assert silent.reload.blocked?
    assert_not online.reload.blocked?
  end

  test "the live panel is shared between teachers for a few seconds" do
    users(:one).test_attempts.create!(test_session: @test)
    snapshot = @test.live_snapshot
    assert_equal [:opening], snapshot.rows.map(&:status)
    assert_same snapshot, TestSession.find(@test.id).live_snapshot

    travel 6.seconds do
      assert_not_same snapshot, @test.live_snapshot
    end
  end
end
