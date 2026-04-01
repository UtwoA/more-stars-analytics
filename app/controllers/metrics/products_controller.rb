module Metrics
  class ProductsController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current

      if to < from
        return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity
      end

      items = AnalyticsProductDailyMetric
        .where(date: from..to)
        .order(:date, :product_type)

      render json: { from: from, to: to, items: items.as_json }
    end
  end
end
