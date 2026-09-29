module DashboardsHelper
  # [label, css classes] for the small status badge on a test card. Scheduled tests get an amber ⏰ chip.
  def window_badge_for(test)
    case test.window_status
    when :upcoming
      ["⏰ Opens #{l(test.starts_at, format: :short)}", "bg-amber-50 text-amber-800 ring-1 ring-inset ring-amber-200 dark:bg-amber-950/40 dark:text-amber-300 dark:ring-amber-900/60"]
    when :closed
      ["Closed", "bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400"]
    else
      if test.ends_at
        ["⏰ Live until #{l(test.ends_at, format: :short)}", "bg-amber-50 text-amber-800 ring-1 ring-inset ring-amber-200 dark:bg-amber-950/40 dark:text-amber-300 dark:ring-amber-900/60"]
      else
        ["Available any time", "bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300"]
      end
    end
  end

  # Formats one leaderboard metric for display ("—" when there is no data)
  def metric_value(key, value)
    return "—" if value.nil?
    case key
    when :accuracy    then "#{value.round(1)}%"
    when :avg_seconds then "#{value.round}s"
    when :avg_tries   then value.round(2).to_s.sub(/\.?0+\z/, "")
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

  # 754 -> "12m 34s"
  def duration_text(seconds)
    return "—" if seconds.nil?
    m, sec = seconds.to_i.divmod(60)
    h, m = m.divmod(60)
    h.positive? ? "#{h}h #{m}m" : (m.positive? ? "#{m}m #{sec}s" : "#{sec}s")
  end

  def marks_text(marks)
    marks.to_f.round(2).to_s.sub(/\.0\z/, "")
  end
end
