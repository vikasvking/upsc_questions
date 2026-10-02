require "csv"

# The results of one teacher test as a CSV file that opens in Excel: one row per ranked student,
# then blocked students (not ranked) at the end.
class TestResultsCsv
  HEADERS = ["Rank", "Student", "Email", "Correct", "Wrong", "Skipped", "Not attempted", "Marks", "Max marks",
             "Correct %", "Result", "Time taken", "Submitted at", "Status"].freeze

  def initialize(test_session, results = test_session.rankings)
    @test_session = test_session
    @results = results
  end

  def filename
    "#{@test_session.title.parameterize.presence || "test"}-results-#{Date.current.iso8601}.csv"
  end

  # With a byte order mark so Excel reads names in Hindi, Odia and other scripts correctly
  def to_s
    body = CSV.generate do |csv|
      csv << HEADERS
      @results.each do |r|
        csv << safe([r.rank, r.user.display_name, r.user.email_address, r.correct, r.wrong, r.skipped, r.unattempted,
                     r.marks, r.max_marks, r.percentage, (r.passed ? "Passed" : "Failed"), clock(r.time_taken),
                     time(r.attempt.finished_at), r.attempt.ended_early? ? "Ranked, ended early: #{r.attempt.ended_reason}" : "Ranked"])
      end
      @test_session.test_attempts.first_tries.blocked.includes(:user).order(:blocked_at).each do |a|
        csv << safe([nil, a.user.display_name, a.user.email_address, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                     "Blocked at #{time(a.blocked_at)}: #{a.block_reason}"])
      end
    end
    "\uFEFF#{body}"
  end

  private

  # A cell starting with = + - or @ would run as a formula in Excel, so such text gets a leading apostrophe
  def safe(row)
    row.map { |v| v.is_a?(String) && v.match?(/\A[=+\-@\t\r]/) ? "'#{v}" : v }
  end

  def clock(seconds)
    return nil if seconds.nil?
    h, rest = seconds.to_i.divmod(3600)
    format("%d:%02d:%02d", h, *rest.divmod(60))
  end

  def time(value) = value&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
end
