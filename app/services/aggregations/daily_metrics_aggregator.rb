module Aggregations
  class DailyMetricsAggregator
    def call(from_date:, to_date:)
      raise ArgumentError, "invalid range" if to_date < from_date
      effective_cost_sql = OrderMetricsSql.effective_cost_sql("o")
      effective_profit_sql = OrderMetricsSql.effective_profit_sql("o")

      sql = <<~SQL
        WITH generated_days AS (
          SELECT generate_series($1::date, $2::date, interval '1 day')::date AS date
        ),
        daily_raw AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS orders_created_count,
            COUNT(*) FILTER (WHERE o.status = 'paid') AS orders_paid_count,
            COUNT(*) FILTER (WHERE o.status = 'failed') AS orders_failed_count,
            0::bigint AS orders_cancelled_count,
            COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS revenue_rub,
            COALESCE(SUM(#{effective_cost_sql}) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS cost_rub,
            COALESCE(SUM(#{effective_profit_sql}) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS profit_rub,
            COALESCE(AVG(o.amount_rub) FILTER (WHERE o.status = 'paid'), 0)::numeric(14,2) AS avg_check_rub,
            COUNT(DISTINCT o.user_id) FILTER (WHERE o.status = 'paid') AS unique_buyers_count
          FROM orders o
          WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1
        ),
        repeat_buyers AS (
          SELECT date, COUNT(*) AS repeat_buyers_count
          FROM (
            SELECT
              (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
              o.user_id
            FROM orders o
            WHERE o.status = 'paid'
              AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
            GROUP BY 1, 2
            HAVING COUNT(*) >= 2
          ) t
          GROUP BY date
        ),
        merged AS (
          SELECT
            d.date,
            COALESCE(r.orders_created_count, 0) AS orders_created_count,
            COALESCE(r.orders_paid_count, 0) AS orders_paid_count,
            COALESCE(r.orders_failed_count, 0) AS orders_failed_count,
            COALESCE(r.orders_cancelled_count, 0) AS orders_cancelled_count,
            COALESCE(r.revenue_rub, 0) AS revenue_rub,
            COALESCE(r.cost_rub, 0) AS cost_rub,
            COALESCE(r.profit_rub, 0) AS profit_rub,
            COALESCE(r.avg_check_rub, 0) AS avg_check_rub,
            CASE
              WHEN COALESCE(r.orders_created_count, 0) = 0 THEN 0
              ELSE ROUND((COALESCE(r.orders_paid_count, 0)::numeric / r.orders_created_count::numeric), 4)
            END AS pay_conversion_rate,
            COALESCE(r.unique_buyers_count, 0) AS unique_buyers_count,
            COALESCE(rb.repeat_buyers_count, 0) AS repeat_buyers_count
          FROM generated_days d
          LEFT JOIN daily_raw r ON r.date = d.date
          LEFT JOIN repeat_buyers rb ON rb.date = d.date
        )
        INSERT INTO analytics_daily_metrics (
          date,
          orders_created_count,
          orders_paid_count,
          orders_failed_count,
          orders_cancelled_count,
          revenue_rub,
          cost_rub,
          profit_rub,
          avg_check_rub,
          pay_conversion_rate,
          unique_buyers_count,
          repeat_buyers_count,
          created_at,
          updated_at
        )
        SELECT
          m.date,
          m.orders_created_count,
          m.orders_paid_count,
          m.orders_failed_count,
          m.orders_cancelled_count,
          m.revenue_rub,
          m.cost_rub,
          m.profit_rub,
          m.avg_check_rub,
          m.pay_conversion_rate,
          m.unique_buyers_count,
          m.repeat_buyers_count,
          NOW(),
          NOW()
        FROM merged m
        ON CONFLICT (date) DO UPDATE
        SET
          orders_created_count = EXCLUDED.orders_created_count,
          orders_paid_count = EXCLUDED.orders_paid_count,
          orders_failed_count = EXCLUDED.orders_failed_count,
          orders_cancelled_count = EXCLUDED.orders_cancelled_count,
          revenue_rub = EXCLUDED.revenue_rub,
          cost_rub = EXCLUDED.cost_rub,
          profit_rub = EXCLUDED.profit_rub,
          avg_check_rub = EXCLUDED.avg_check_rub,
          pay_conversion_rate = EXCLUDED.pay_conversion_rate,
          unique_buyers_count = EXCLUDED.unique_buyers_count,
          repeat_buyers_count = EXCLUDED.repeat_buyers_count,
          updated_at = NOW();
      SQL

      ApplicationRecord.connection.exec_query(sql, "daily_metrics_upsert", [
        ActiveRecord::Relation::QueryAttribute.new("from_date", from_date, ActiveRecord::Type::Date.new),
        ActiveRecord::Relation::QueryAttribute.new("to_date", to_date, ActiveRecord::Type::Date.new)
      ])

      (to_date - from_date).to_i + 1
    end
  end
end
