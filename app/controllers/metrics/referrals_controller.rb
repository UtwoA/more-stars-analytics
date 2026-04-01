module Metrics
  class ReferralsController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])
      failed_statuses = quoted_statuses(ORDER_STATUSES["failed"], fallback: ["failed"])

      sql = <<~SQL
        WITH dates AS (
          SELECT generate_series(#{conn.quote(from)}::date, #{conn.quote(to)}::date, interval '1 day')::date AS date
        ),
        referred_users_by_day AS (
          SELECT
            (u.created_at AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS new_referred_users_count
          FROM users u
          WHERE u.referrer_id IS NOT NULL
            AND (u.created_at AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          GROUP BY 1
        ),
        referred_orders_daily AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS referred_orders_created_count,
            COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS referred_orders_paid_count,
            COUNT(*) FILTER (WHERE o.status IN (#{failed_statuses})) AS referred_orders_failed_count,
            COUNT(DISTINCT o.user_id) FILTER (WHERE o.status IN (#{paid_statuses})) AS referred_unique_buyers_count,
            COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::numeric(14,2) AS referred_revenue_rub
          FROM orders o
          JOIN users u ON u.user_id = o.user_id
          WHERE u.referrer_id IS NOT NULL
            AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          GROUP BY 1
        ),
        referred_tx_daily AS (
          SELECT
            (COALESCE(pt.created_at, o.timestamp) AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS referred_payment_attempts_count,
            COUNT(DISTINCT pt.order_id) AS referred_payment_orders_count
          FROM payment_transactions pt
          JOIN orders o ON o.order_id = pt.order_id
          JOIN users u ON u.user_id = o.user_id
          WHERE u.referrer_id IS NOT NULL
            AND (COALESCE(pt.created_at, o.timestamp) AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          GROUP BY 1
        )
        SELECT
          d.date,
          COALESCE(ru.new_referred_users_count, 0) AS new_referred_users_count,
          COALESCE(ro.referred_orders_created_count, 0) AS referred_orders_created_count,
          COALESCE(ro.referred_orders_paid_count, 0) AS referred_orders_paid_count,
          COALESCE(ro.referred_orders_failed_count, 0) AS referred_orders_failed_count,
          COALESCE(rt.referred_payment_attempts_count, 0) AS referred_payment_attempts_count,
          COALESCE(rt.referred_payment_orders_count, 0) AS referred_payment_orders_count,
          COALESCE(ro.referred_unique_buyers_count, 0) AS referred_unique_buyers_count,
          COALESCE(ro.referred_revenue_rub, 0)::float AS referred_revenue_rub,
          COALESCE(arm.referral_bonus_cost_rub, 0)::float AS referral_bonus_cost_rub,
          COALESCE(arm.referral_profit_rub, 0)::float AS referral_profit_rub
        FROM dates d
        LEFT JOIN referred_users_by_day ru ON ru.date = d.date
        LEFT JOIN referred_orders_daily ro ON ro.date = d.date
        LEFT JOIN referred_tx_daily rt ON rt.date = d.date
        LEFT JOIN analytics_referral_daily_metrics arm ON arm.date = d.date
        ORDER BY d.date
      SQL

      items = conn.exec_query(sql).to_a.map do |row|
        created = row["referred_orders_created_count"].to_i
        paid = row["referred_orders_paid_count"].to_i
        attempts = row["referred_payment_attempts_count"].to_i
        revenue = row["referred_revenue_rub"].to_f
        bonus = row["referral_bonus_cost_rub"].to_f
        profit = row["referral_profit_rub"].to_f

        row.merge(
          "referred_created_to_paid_rate" => created.positive? ? (paid.to_f / created).round(4) : 0.0,
          "referred_attempt_to_paid_rate" => attempts.positive? ? (paid.to_f / attempts).round(4) : 0.0,
          "referred_avg_check_rub" => paid.positive? ? (revenue / paid).round(2) : 0.0,
          "referral_net_after_bonus_rub" => (revenue - bonus).round(2),
          "referral_profit_margin_rate" => revenue.positive? ? (profit / revenue).round(4) : 0.0
        )
      end

      totals = {
        new_referred_users_count: items.sum { |r| r["new_referred_users_count"].to_i },
        referred_orders_created_count: items.sum { |r| r["referred_orders_created_count"].to_i },
        referred_orders_paid_count: items.sum { |r| r["referred_orders_paid_count"].to_i },
        referred_orders_failed_count: items.sum { |r| r["referred_orders_failed_count"].to_i },
        referred_payment_attempts_count: items.sum { |r| r["referred_payment_attempts_count"].to_i },
        referred_payment_orders_count: items.sum { |r| r["referred_payment_orders_count"].to_i },
        referred_unique_buyers_count: items.sum { |r| r["referred_unique_buyers_count"].to_i },
        referred_revenue_rub: items.sum { |r| r["referred_revenue_rub"].to_f }.round(2),
        referral_bonus_cost_rub: items.sum { |r| r["referral_bonus_cost_rub"].to_f }.round(2),
        referral_profit_rub: items.sum { |r| r["referral_profit_rub"].to_f }.round(2)
      }
      totals[:referred_created_to_paid_rate] = totals[:referred_orders_created_count].positive? ? (totals[:referred_orders_paid_count].to_f / totals[:referred_orders_created_count]).round(4) : 0.0
      totals[:referred_attempt_to_paid_rate] = totals[:referred_payment_attempts_count].positive? ? (totals[:referred_orders_paid_count].to_f / totals[:referred_payment_attempts_count]).round(4) : 0.0

      render json: { from: from, to: to, totals: totals, items: items }
    end

    private

    def quoted_statuses(list, fallback:)
      statuses = Array(list).compact.map(&:to_s).reject(&:blank?)
      statuses = fallback if statuses.empty?
      statuses.map { |status| ActiveRecord::Base.connection.quote(status) }.join(", ")
    end
  end
end
