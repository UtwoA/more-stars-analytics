module Aggregations
  class ReferralMetricsAggregator
    def call(from_date:, to_date:)
      raise ArgumentError, "invalid range" if to_date < from_date
      effective_profit_sql = OrderMetricsSql.effective_profit_sql("o")

      sql = <<~SQL
        WITH days AS (
          SELECT generate_series($1::date, $2::date, interval '1 day')::date AS date
        ),
        new_referred AS (
          SELECT
            (u.created_at AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS new_referred_users_count
          FROM users u
          WHERE u.referrer_id IS NOT NULL
            AND (u.created_at AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1
        ),
        paid_referred AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS referred_orders_paid_count,
            COUNT(DISTINCT o.user_id) AS referred_buyers_count,
            COALESCE(SUM(o.amount_rub), 0)::numeric(14,2) AS referred_revenue_rub,
            COALESCE(SUM(#{effective_profit_sql}), 0)::numeric(14,2) AS referred_orders_profit_rub
          FROM orders o
          JOIN users u ON u.user_id = o.user_id
          WHERE o.status = 'paid'
            AND u.referrer_id IS NOT NULL
            AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1
        ),
        referral_cost AS (
          SELECT
            (re.created_at AT TIME ZONE 'Europe/Moscow')::date AS date,
            COALESCE(SUM(COALESCE(o.cost_per_star, 0) * COALESCE(re.stars, 0)), 0)::numeric(14,2) AS referral_bonus_cost_rub
          FROM referral_earnings re
          LEFT JOIN orders o ON o.order_id = re.order_id
          WHERE (re.created_at AT TIME ZONE 'Europe/Moscow')::date BETWEEN $1::date AND $2::date
          GROUP BY 1
        ),
        merged AS (
          SELECT
            d.date,
            COALESCE(nr.new_referred_users_count, 0) AS new_referred_users_count,
            COALESCE(pr.referred_buyers_count, 0) AS referred_buyers_count,
            COALESCE(pr.referred_orders_paid_count, 0) AS referred_orders_paid_count,
            COALESCE(pr.referred_revenue_rub, 0) AS referred_revenue_rub,
            COALESCE(rc.referral_bonus_cost_rub, 0) AS referral_bonus_cost_rub,
            (COALESCE(pr.referred_orders_profit_rub, 0) - COALESCE(rc.referral_bonus_cost_rub, 0))::numeric(14,2) AS referral_profit_rub
          FROM days d
          LEFT JOIN new_referred nr ON nr.date = d.date
          LEFT JOIN paid_referred pr ON pr.date = d.date
          LEFT JOIN referral_cost rc ON rc.date = d.date
        )
        INSERT INTO analytics_referral_daily_metrics (
          date,
          new_referred_users_count,
          referred_buyers_count,
          referred_orders_paid_count,
          referred_revenue_rub,
          referral_bonus_cost_rub,
          referral_profit_rub,
          created_at,
          updated_at
        )
        SELECT
          m.date,
          m.new_referred_users_count,
          m.referred_buyers_count,
          m.referred_orders_paid_count,
          m.referred_revenue_rub,
          m.referral_bonus_cost_rub,
          m.referral_profit_rub,
          NOW(),
          NOW()
        FROM merged m
        ON CONFLICT (date) DO UPDATE
        SET
          new_referred_users_count = EXCLUDED.new_referred_users_count,
          referred_buyers_count = EXCLUDED.referred_buyers_count,
          referred_orders_paid_count = EXCLUDED.referred_orders_paid_count,
          referred_revenue_rub = EXCLUDED.referred_revenue_rub,
          referral_bonus_cost_rub = EXCLUDED.referral_bonus_cost_rub,
          referral_profit_rub = EXCLUDED.referral_profit_rub,
          updated_at = NOW();
      SQL

      ApplicationRecord.connection.exec_query(sql, "referral_metrics_upsert", [
        ActiveRecord::Relation::QueryAttribute.new("from_date", from_date, ActiveRecord::Type::Date.new),
        ActiveRecord::Relation::QueryAttribute.new("to_date", to_date, ActiveRecord::Type::Date.new)
      ])

      true
    end
  end
end
