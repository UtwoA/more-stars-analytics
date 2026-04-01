module Ops
  class BackfillController < ApplicationController
    def create
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      mode = params[:mode].to_s
      async = ActiveModel::Type::Boolean.new.cast(params[:async].presence || true)

      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      if mode == "full_suite"
        enqueue_full_suite(from, to, async)
      else
        enqueue_daily(from, to, async)
      end

      render json: {
        status: "queued",
        mode: mode.presence || "daily",
        from: from,
        to: to,
        async: async
      }
    end

    private

    def enqueue_daily(from, to, async)
      if async
        DailyMetricsBackfillJob.perform_later(from_date: from, to_date: to)
      else
        DailyMetricsBackfillJob.perform_now(from_date: from, to_date: to)
      end
    end

    def enqueue_full_suite(from, to, async)
      if async
        DailyMetricsBackfillJob.perform_later(from_date: from, to_date: to)
        CohortMetricsBackfillJob.perform_later(from_date: from, to_date: to)
        DataQualityCheckJob.perform_later(from_date: from, to_date: to)
      else
        DailyMetricsBackfillJob.perform_now(from_date: from, to_date: to)
        CohortMetricsBackfillJob.perform_now(from_date: from, to_date: to)
        DataQualityCheckJob.perform_now(from_date: from, to_date: to)
      end
    end
  end
end
