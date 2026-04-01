module Aggregations
  class CohortMetricsAggregator
    def call(from_date:, to_date:)
      raise ArgumentError, "invalid range" if to_date < from_date

      sql = <<~SQL
        WITH paid_orders AS (
          SELECT
            o.user_id,
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS paid_date,
            date_trunc('week', (o.timestamp AT TIME ZONE 'Europe/Moscow'))::date AS paid_week,
            COALESCE(o.amount_rub, 0)::numeric(14,2) AS revenue_rub
          FROM orders o
          WHERE o.status = 'paid'
        ),
        first_paid AS (
          SELECT
            po.user_id,
            MIN(po.paid_week) AS cohort_week
          FROM paid_orders po
          GROUP BY po.user_id
        ),
        cohort_size AS (
          SELECT
            fp.cohort_week,
            COUNT(*) AS users_count
          FROM first_paid fp
          WHERE fp.cohort_week BETWEEN date_trunc('week', $1::date)::date AND date_trunc('week', $2::date)::date
          GROUP BY fp.cohort_week
        ),
        cohort_activity AS (
          SELECT
            fp.cohort_week,
            ((po.paid_week - fp.cohort_week) / 7)::int AS age_week,
            COUNT(DISTINCT po.user_id) AS repeat_buyers_count,
            COALESCE(SUM(po.revenue_rub), 0)::numeric(14,2) AS period_revenue_rub
          FROM paid_orders po
          JOIN first_paid fp ON fp.user_id = po.user_id
          WHERE fp.cohort_week BETWEEN date_trunc('week', $1::date)::date AND date_trunc('week', $2::date)::date
            AND po.paid_week >= fp.cohort_week
            AND ((po.paid_week - fp.cohort_week) / 7)::int BETWEEN 0 AND 12
          GROUP BY 1, 2
        ),
        merged AS (
          SELECT
            ca.cohort_week,
            ca.age_week,
            cs.users_count,
            ca.repeat_buyers_count,
            CASE
              WHEN cs.users_count = 0 THEN 0
              ELSE ROUND((ca.repeat_buyers_count::numeric / cs.users_count::numeric), 4)
            END AS retention_rate,
            ca.period_revenue_rub,
            SUM(ca.period_revenue_rub) OVER (
              PARTITION BY ca.cohort_week
              ORDER BY ca.age_week
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )::numeric(14,2) AS cumulative_revenue_rub
          FROM cohort_activity ca
          JOIN cohort_size cs ON cs.cohort_week = ca.cohort_week
        )
        INSERT INTO analytics_cohort_weekly_metrics (
          cohort_week,
          age_week,
          users_count,
          repeat_buyers_count,
          retention_rate,
          period_revenue_rub,
          cumulative_revenue_rub,
          created_at,
          updated_at
        )
        SELECT
          m.cohort_week,
          m.age_week,
          m.users_count,
          m.repeat_buyers_count,
          m.retention_rate,
          m.period_revenue_rub,
          m.cumulative_revenue_rub,
          NOW(),
          NOW()
        FROM merged m
        ON CONFLICT (cohort_week, age_week) DO UPDATE
        SET
          users_count = EXCLUDED.users_count,
          repeat_buyers_count = EXCLUDED.repeat_buyers_count,
          retention_rate = EXCLUDED.retention_rate,
          period_revenue_rub = EXCLUDED.period_revenue_rub,
          cumulative_revenue_rub = EXCLUDED.cumulative_revenue_rub,
          updated_at = NOW();
      SQL

      ApplicationRecord.connection.exec_query(sql, "cohort_metrics_upsert", [
        ActiveRecord::Relation::QueryAttribute.new("from_date", from_date, ActiveRecord::Type::Date.new),
        ActiveRecord::Relation::QueryAttribute.new("to_date", to_date, ActiveRecord::Type::Date.new)
      ])

      true
    end
  end
end

