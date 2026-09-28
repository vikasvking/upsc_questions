module DashboardsHelper
  # [label, css classes] for the small status badge on a test card
  def test_window_badge(test)
    case test.window_status
    when :upcoming
      ["Opens #{l(test.starts_at, format: :short)}", "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-400"]
    when :closed
      ["Closed", "bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400"]
    else
      label = test.ends_at ? "Live · closes #{l(test.ends_at, format: :short)}" : "Live"
      [label, "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-400"]
    end
  end

  # Formats one leaderboard metric for display ("—" when there is no data)
  def metric_value(key, value)
    return "—" if value.nil?
    case key
    when :accuracy    then "#{value.round(1)}%"
    when :avg_seconds then "#{value.round}s"
    when :active_days then pluralize(value.round(1).to_s.delete_suffix(".0"), "day")
    else value.round(1).to_s.delete_suffix(".0")
    end
  end

  # Is "mine" better than "other" for this metric? nil when either is missing
  def metric_better?(key, mine, other)
    return nil if mine.nil? || other.nil? || mine == other
    lower_is_better = Leaderboard::METRICS.find { |k, _, _| k == key }&.last == :lower
    lower_is_better ? mine < other : mine > other
  end
end
