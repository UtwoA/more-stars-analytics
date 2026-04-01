namespace :analytics do
  desc "Backfill daily metrics: rake analytics:backfill_daily FROM=2026-01-01 TO=2026-01-31"
  task backfill_daily: :environment do
    from = Date.iso8601(ENV.fetch("FROM"))
    to = Date.iso8601(ENV.fetch("TO"))
    DailyMetricsBackfillJob.perform_now(from_date: from, to_date: to)
    puts "Daily metrics backfill done for #{from}..#{to}"
  end

  desc "Backfill full suite metrics: daily + referrals/promos + cohorts + data quality"
  task backfill_full: :environment do
    from = Date.iso8601(ENV.fetch("FROM"))
    to = Date.iso8601(ENV.fetch("TO"))
    DailyMetricsBackfillJob.perform_now(from_date: from, to_date: to)
    CohortMetricsBackfillJob.perform_now(from_date: from, to_date: to)
    DataQualityCheckJob.perform_now(from_date: from, to_date: to)
    puts "Full analytics suite backfill done for #{from}..#{to}"
  end
end
