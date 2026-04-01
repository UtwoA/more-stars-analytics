module Queries
  class TopEntitiesQuery
    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def top_provider
      AnalyticsProviderDailyMetric
        .where(date: @from..@to)
        .group(:payment_provider)
        .select("payment_provider, SUM(revenue_rub) AS total_revenue")
        .order("total_revenue DESC")
        .first
    end

    def top_product
      AnalyticsProductDailyMetric
        .where(date: @from..@to)
        .group(:product_type)
        .select("product_type, SUM(revenue_rub) AS total_revenue")
        .order("total_revenue DESC")
        .first
    end
  end
end

