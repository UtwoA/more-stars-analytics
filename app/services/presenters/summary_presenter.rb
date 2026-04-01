module Presenters
  class SummaryPresenter
    def initialize(from:, to:, total_created:, total_paid:, revenue:, profit:, unique_buyers:, repeat_buyers:, top_provider_row:, top_product_row:)
      @from = from
      @to = to
      @total_created = total_created
      @total_paid = total_paid
      @revenue = revenue
      @profit = profit
      @unique_buyers = unique_buyers
      @repeat_buyers = repeat_buyers
      @top_provider_row = top_provider_row
      @top_product_row = top_product_row
    end

    def as_json
      {
        from: @from,
        to: @to,
        orders_created_count: @total_created,
        orders_paid_count: @total_paid,
        paid_conversion_rate: @total_created.positive? ? (@total_paid.to_f / @total_created).round(4) : 0.0,
        revenue_total_rub: @revenue.round(2),
        profit_total_rub: @profit.round(2),
        avg_check_rub: @total_paid.positive? ? (@revenue / @total_paid).round(2) : 0.0,
        unique_buyers_count: @unique_buyers,
        repeat_buyers_count: @repeat_buyers,
        repeat_purchase_rate: @unique_buyers.positive? ? (@repeat_buyers.to_f / @unique_buyers).round(4) : 0.0,
        top_provider: @top_provider_row&.payment_provider,
        top_provider_revenue_rub: @top_provider_row&.total_revenue&.to_f&.round(2),
        top_product: @top_product_row&.product_type,
        top_product_revenue_rub: @top_product_row&.total_revenue&.to_f&.round(2)
      }
    end
  end
end

