module Metrics
  class PromosController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      scope = AnalyticsPromoDailyMetric.where(date: from..to)
      scope = scope.where(promo_code: params[:promo_code]) if params[:promo_code].present?
      items = scope.order(:date, :promo_code)

      render json: { from: from, to: to, items: items.as_json }
    end
  end
end

