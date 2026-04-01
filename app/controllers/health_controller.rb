class HealthController < ApplicationController
  skip_before_action :authenticate_internal!, only: [:show]

  def show
    db_ok = database_ok?
    redis_ok = redis_ok?
    last_run = AnalyticsJobRun.where(job_name: "DailyMetricsBackfillJob", status: "success").order(finished_at: :desc).first

    render json: {
      status: db_ok && redis_ok ? "ok" : "degraded",
      db_connectivity: db_ok,
      redis_connectivity: redis_ok,
      last_successful_aggregation_at: last_run&.finished_at
    }
  end

  private

  def database_ok?
    ApplicationRecord.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  def redis_ok?
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/0"))
    redis.ping == "PONG"
  rescue StandardError
    false
  end
end
