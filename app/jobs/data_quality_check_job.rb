class DataQualityCheckJob < ApplicationJob
  queue_as :metrics

  def perform(from_date: Date.current - 30, to_date: Date.current)
    from_date = Date.iso8601(from_date.to_s)
    to_date = Date.iso8601(to_date.to_s)

    run = AnalyticsJobRun.create!(
      job_name: self.class.name,
      range_start: from_date,
      range_end: to_date,
      status: "running",
      started_at: Time.current
    )

    issues_count = DataQuality::Checker.new.run!(from_date: from_date, to_date: to_date)

    run.update!(
      status: "success",
      rows_written: issues_count,
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

