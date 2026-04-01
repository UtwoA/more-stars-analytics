module Aggregations
  class PromoMetricsAggregator
    def call(from_date:, to_date:)
      raise ArgumentError, "invalid range" if to_date < from_date
      effective_profit_sql = OrderMetricsSql.effective_profit_sql("o")

      sql = <<~SQL
        WITH promo_daily AS (
          SELECT
            (pr.created_at AT TIME ZONE 'Europe/Moscow')::date AS date,
            pr.code AS promo_code,
            COUNT(*) AS redemptions_count
          FROM promo_redemptions pr
          WHERE (pr.created_at AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1, 2
        ),
        paid_orders AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            o.promo_code AS promo_code,
            COUNT(*) AS paid_orders_count,
            COALESCE(SUM(COALESCE(o.amount_rub_original, o.amount_rub) - COALESCE(o.amount_rub, 0)), 0)::numeric(14,2) AS discount_total_rub,
            COALESCE(SUM(o.amount_rub), 0)::numeric(14,2) AS revenue_after_discount_rub,
            COALESCE(SUM(#{effective_profit_sql}), 0)::numeric(14,2) AS profit_after_discount_rub
          FROM orders o
          WHERE o.status = 'paid'
            AND o.promo_code IS NOT NULL
            AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1, 2
        ),
        merged AS (
          SELECT
            COALESCE(pd.date, po.date) AS date,
            COALESCE(pd.promo_code, po.promo_code) AS promo_code,
            COALESCE(pd.redemptions_count, 0) AS redemptions_count,
            COALESCE(po.paid_orders_count, 0) AS paid_orders_count,
            COALESCE(po.discount_total_rub, 0)::numeric(14,2) AS discount_total_rub,
            COALESCE(po.revenue_after_discount_rub, 0)::numeric(14,2) AS revenue_after_discount_rub,
            COALESCE(po.profit_after_discount_rub, 0)::numeric(14,2) AS profit_after_discount_rub
          FROM promo_daily pd
          FULL OUTER JOIN paid_orders po
            ON po.date = pd.date
           AND po.promo_code = pd.promo_code
        )
        INSERT INTO analytics_promo_daily_metrics (
          date,
          promo_code,
          redemptions_count,
          paid_orders_count,
          discount_total_rub,
          revenue_after_discount_rub,
          profit_after_discount_rub,
          created_at,
          updated_at
        )
        SELECT
          m.date,
          m.promo_code,
          m.redemptions_count,
          m.paid_orders_count,
          m.discount_total_rub,
          m.revenue_after_discount_rub,
          m.profit_after_discount_rub,
          NOW(),
          NOW()
        FROM merged m
        WHERE m.date IS NOT NULL
          AND m.promo_code IS NOT NULL
        ON CONFLICT (date, promo_code) DO UPDATE
        SET
          redemptions_count = EXCLUDED.redemptions_count,
          paid_orders_count = EXCLUDED.paid_orders_count,
          discount_total_rub = EXCLUDED.discount_total_rub,
          revenue_after_discount_rub = EXCLUDED.revenue_after_discount_rub,
          profit_after_discount_rub = EXCLUDED.profit_after_discount_rub,
          updated_at = NOW();
      SQL

      ApplicationRecord.connection.exec_query(sql, "promo_metrics_upsert", [
        ActiveRecord::Relation::QueryAttribute.new("from_date", from_date, ActiveRecord::Type::Date.new),
        ActiveRecord::Relation::QueryAttribute.new("to_date", to_date, ActiveRecord::Type::Date.new)
      ])

      true
    end
  end
end
