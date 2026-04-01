module Metrics
  class SummaryController < ApplicationController
    def show
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current

      scope = AnalyticsDailyMetric.where(date: from..to)
      total_created = scope.sum(:orders_created_count)
      total_paid = scope.sum(:orders_paid_count)
      revenue = scope.sum(:revenue_rub).to_f
      profit = scope.sum(:profit_rub).to_f
      unique_buyers = scope.sum(:unique_buyers_count).to_i
      repeat_buyers = scope.sum(:repeat_buyers_count).to_i

      top_entities = Queries::TopEntitiesQuery.new(from: from, to: to)
      top_provider_row = top_entities.top_provider
      top_product_row = top_entities.top_product

      render json: Presenters::SummaryPresenter.new(
        from: from,
        to: to,
        total_created: total_created,
        total_paid: total_paid,
        revenue: revenue,
        profit: profit,
        unique_buyers: unique_buyers,
        repeat_buyers: repeat_buyers,
        top_provider_row: top_provider_row,
        top_product_row: top_product_row
      ).as_json
    end
  end
end
