module Metrics
  class CohortsController < ApplicationController
    def index
      from = parse_date(params[:from_cohort_week]) || (Date.current - 84).beginning_of_week
      to = parse_date(params[:to_cohort_week]) || Date.current.beginning_of_week
      return render json: { error: "`to_cohort_week` must be greater than or equal to `from_cohort_week`" }, status: :unprocessable_entity if to < from

      scope = AnalyticsCohortWeeklyMetric.where(cohort_week: from..to)
      scope = scope.where(age_week: params[:age_week].to_i) if params[:age_week].present?
      items = scope.order(:cohort_week, :age_week)

      render json: { from_cohort_week: from, to_cohort_week: to, items: items.as_json }
    end
  end
end

