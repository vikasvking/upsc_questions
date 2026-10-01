# One line of a student's "My Tests" list (website and app): how an attempt ended and how it scored.
#
#   rows = AttemptSummary.for(attempts)   # a few queries per page, plus one ranking per teacher test
#   row.status   # :in_progress, :blocked, :waiting (strict test not closed yet) or :done
class AttemptSummary
  attr_reader :attempt, :retake_number

  delegate :token, :title, :test_session, :retake?, :started_at, :finished_at, :exam, to: :attempt

  def self.for(attempts)
    attempts = attempts.to_a
    return [] if attempts.empty?

    # "Retake 1", "Retake 2"... per test, counted over all of the student's retakes, not just this page
    user = attempts.first.user
    test_ids = attempts.filter_map(&:test_session_id).uniq
    numbers = {}
    user.test_attempts.retakes.where(test_session_id: test_ids).order(:id).pluck(:id, :test_session_id)
        .group_by(&:last).each_value { |pairs| pairs.each_with_index { |(id, _), i| numbers[id] = i + 1 } }

    attempts.map { |a| new(a, numbers[a.id]) }
  end

  def initialize(attempt, retake_number = nil)
    @attempt = attempt
    @retake_number = retake_number
  end

  def kind = test_session ? :test : :practice

  def status
    @status ||=
      if attempt.blocked? then :blocked
      elsif !(attempt.finished? || attempt.expired?) then :in_progress
      elsif !attempt.results_released? then :waiting
      else :done
      end
  end

  # When a strict test shows its results (:waiting)
  def release_at = test_session&.ends_at

  # In progress: [answered, total]
  def progress
    @progress ||= begin
      ids = attempt.questions.pluck(:id)
      [attempt.user_responses.where(question_id: ids).distinct.count(:question_id), ids.size]
    end
  end

  # Done: marks, correct, percentage... (TestAttempt#score_summary)
  def summary = @summary ||= attempt.score_summary

  # Done, first attempt at a teacher test: [rank, students ranked]. Retakes and practice are not ranked.
  def rank
    return nil unless status == :done && test_session && !retake?
    @rank ||= begin
      ranking = test_session.rankings(for_attempt: attempt)
      mine = ranking.find { |r| r.attempt.id == attempt.id }
      mine && [mine.rank, ranking.size]
    end
  end

  # The date shown on the line: when it was submitted, or when it was started
  def shown_at = finished_at || started_at
end
