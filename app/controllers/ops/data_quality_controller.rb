module Ops
  class DataQualityController < ApplicationController
    def index
      scope = AnalyticsDataQualityIssue.order(detected_at: :desc)
      scope = scope.where(resolved: ActiveModel::Type::Boolean.new.cast(params[:resolved])) if params.key?(:resolved)
      scope = scope.limit((params[:limit] || 200).to_i.clamp(1, 1000))

      render json: {
        items: scope.as_json,
        summary: {
          open_issues: AnalyticsDataQualityIssue.where(resolved: false).count,
          critical_open_issues: AnalyticsDataQualityIssue.where(resolved: false, severity: "critical").count
        }
      }
    end

    def run
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      async = ActiveModel::Type::Boolean.new.cast(params[:async].presence || true)
      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      if async
        DataQualityCheckJob.perform_later(from_date: from, to_date: to)
      else
        DataQualityCheckJob.perform_now(from_date: from, to_date: to)
      end

      render json: { status: "queued", from: from, to: to, async: async }
    end
  end
end

