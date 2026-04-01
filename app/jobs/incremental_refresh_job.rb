class IncrementalRefreshJob < ApplicationJob
  queue_as :metrics

  def perform(mode: "today")
    today = Date.current

    from_date, to_date = case mode.to_s
                         when "last_3_days"
                           [today - 2, today]
                         when "last_30_days"
                           [today - 29, today]
                         else
                           [today, today]
                         end

    DailyMetricsBackfillJob.perform_now(from_date: from_date, to_date: to_date)
    CohortMetricsBackfillJob.perform_now(from_date: (today - 84), to_date: today) if mode.to_s == "last_30_days"
  end
end
