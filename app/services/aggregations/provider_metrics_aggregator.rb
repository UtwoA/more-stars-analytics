module Aggregations
  class ProviderMetricsAggregator
    def call(from_date:, to_date:)
      raise ArgumentError, "invalid range" if to_date < from_date
      effective_cost_sql = OrderMetricsSql.effective_cost_sql("o")
      effective_profit_sql = OrderMetricsSql.effective_profit_sql("o")

      sql = <<~SQL
        WITH daily_provider_raw AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            COALESCE(NULLIF(o.payment_provider, ''), 'unknown') AS payment_provider,
            COUNT(*) AS orders_created_count,
            COUNT(*) FILTER (WHERE o.status = 'paid') AS orders_paid_count,
            COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS revenue_rub,
            COALESCE(SUM(#{effective_cost_sql}) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS cost_rub,
            COALESCE(SUM(#{effective_profit_sql}) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS profit_rub,
            COALESCE(AVG(o.amount_rub) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS avg_check_rub
          FROM orders o
          WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1, 2
        )
        INSERT INTO analytics_provider_daily_metrics (
          date,
          payment_provider,
          orders_created_count,
          orders_paid_count,
          revenue_rub,
          cost_rub,
          profit_rub,
          avg_check_rub,
          paid_conversion_rate,
          created_at,
          updated_at
        )
        SELECT
          r.date,
          r.payment_provider,
          r.orders_created_count,
          r.orders_paid_count,
          r.revenue_rub,
          r.cost_rub,
          r.profit_rub,
          r.avg_check_rub,
          CASE
            WHEN r.orders_created_count = 0 THEN 0
            ELSE ROUND((r.orders_paid_count::numeric / r.orders_created_count::numeric), 4)
          END AS paid_conversion_rate,
          NOW(),
          NOW()
        FROM daily_provider_raw r
        ON CONFLICT (date, payment_provider) DO UPDATE
        SET
          orders_created_count = EXCLUDED.orders_created_count,
          orders_paid_count = EXCLUDED.orders_paid_count,
          revenue_rub = EXCLUDED.revenue_rub,
          cost_rub = EXCLUDED.cost_rub,
          profit_rub = EXCLUDED.profit_rub,
          avg_check_rub = EXCLUDED.avg_check_rub,
          paid_conversion_rate = EXCLUDED.paid_conversion_rate,
          updated_at = NOW();
      SQL

      ApplicationRecord.connection.exec_query(sql, "provider_metrics_upsert", [
        ActiveRecord::Relation::QueryAttribute.new("from_date", from_date, ActiveRecord::Type::Date.new),
        ActiveRecord::Relation::QueryAttribute.new("to_date", to_date, ActiveRecord::Type::Date.new)
      ])

      true
    end
  end
end
