class DailyMetricsBackfillJob < ApplicationJob
  queue_as :metrics

  def perform(from_date:, to_date:)
    run = AnalyticsJobRun.create!(
      job_name: self.class.name,
      range_start: from_date,
      range_end: to_date,
      status: "running",
      started_at: Time.current
    )

    rows_written = Aggregations::DailyMetricsAggregator.new.call(
      from_date: Date.iso8601(from_date.to_s),
      to_date: Date.iso8601(to_date.to_s)
    )
    Aggregations::ProviderMetricsAggregator.new.call(
      from_date: Date.iso8601(from_date.to_s),
      to_date: Date.iso8601(to_date.to_s)
    )
    Aggregations::ProductMetricsAggregator.new.call(
      from_date: Date.iso8601(from_date.to_s),
      to_date: Date.iso8601(to_date.to_s)
    )
    Aggregations::ReferralMetricsAggregator.new.call(
      from_date: Date.iso8601(from_date.to_s),
      to_date: Date.iso8601(to_date.to_s)
    )
    Aggregations::PromoMetricsAggregator.new.call(
      from_date: Date.iso8601(from_date.to_s),
      to_date: Date.iso8601(to_date.to_s)
    )

    run.update!(
      status: "success",
      rows_written: rows_written,
      finished_at: Time.current
    )
  rescue StandardError => e
    run&.update!(
      status: "failed",
      error_text: e.message.to_s.first(2000),
      finished_at: Time.current
    )
    raise
  end
end
