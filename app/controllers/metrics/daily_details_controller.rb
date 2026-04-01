module Metrics
  class DailyDetailsController < ApplicationController
    def show
      date = parse_date(params[:date]) || Date.current
      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])
      effective_cost_sql = OrderMetricsSql.effective_cost_sql("o")

      summary = conn.exec_query(<<~SQL).first || {}
        SELECT
          #{conn.quote(date)}::date AS date,
          COUNT(*) AS orders_created_count,
          COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS orders_paid_count,
          COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS revenue_rub,
          COALESCE(SUM(#{effective_cost_sql}) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS cost_rub
        FROM orders o
        WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date = #{conn.quote(date)}::date
      SQL

      promo_discount = conn.exec_query(<<~SQL).first&.fetch("discount_total_rub", 0).to_f
        SELECT COALESCE(SUM(apdm.discount_total_rub), 0)::float AS discount_total_rub
        FROM analytics_promo_daily_metrics apdm
        WHERE apdm.date = #{conn.quote(date)}::date
      SQL
      referral_bonus = conn.exec_query(<<~SQL).first&.fetch("referral_bonus_cost_rub", 0).to_f
        SELECT COALESCE(arm.referral_bonus_cost_rub, 0)::float AS referral_bonus_cost_rub
        FROM analytics_referral_daily_metrics arm
        WHERE arm.date = #{conn.quote(date)}::date
      SQL

      revenue = summary["revenue_rub"].to_f
      cost = summary["cost_rub"].to_f
      gross_profit = revenue - cost
      net_profit_estimate = gross_profit - promo_discount - referral_bonus

      buyers = conn.exec_query(<<~SQL).to_a
        SELECT
          o.user_id,
          COALESCE(NULLIF(u.username, ''), '-') AS username,
          COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS paid_orders_count,
          COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS revenue_rub,
          COALESCE(SUM(#{effective_cost_sql}) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS cost_rub,
          COALESCE(SUM(COALESCE(o.amount_rub, 0) - (#{effective_cost_sql})) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS gross_profit_rub
        FROM orders o
        LEFT JOIN users u ON u.user_id = o.user_id
        WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date = #{conn.quote(date)}::date
        GROUP BY o.user_id, u.username
        HAVING COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) > 0
        ORDER BY revenue_rub DESC
      SQL

      orders = conn.exec_query(<<~SQL).to_a
        SELECT
          o.order_id,
          o.user_id,
          COALESCE(NULLIF(u.username, ''), '-') AS username,
          o.status,
          o.product_type,
          COALESCE(NULLIF(o.payment_provider, ''), 'unknown') AS payment_provider,
          COALESCE(o.amount_rub, 0)::float AS amount_rub,
          (#{effective_cost_sql})::float AS cost_rub,
          COALESCE(o.promo_code, '-') AS promo_code,
          (o.timestamp AT TIME ZONE 'Europe/Moscow') AS timestamp_msk
        FROM orders o
        LEFT JOIN users u ON u.user_id = o.user_id
        WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date = #{conn.quote(date)}::date
        ORDER BY o.timestamp DESC
        LIMIT 300
      SQL

      render json: {
        date: date,
        breakdown: {
          orders_created_count: summary["orders_created_count"].to_i,
          orders_paid_count: summary["orders_paid_count"].to_i,
          revenue_rub: revenue.round(2),
          cost_rub: cost.round(2),
          gross_profit_rub: gross_profit.round(2),
          promo_discount_rub: promo_discount.round(2),
          referral_bonus_rub: referral_bonus.round(2),
          net_profit_estimate_rub: net_profit_estimate.round(2),
          turnover_rub: revenue.round(2),
          formula: "net_profit_estimate = revenue - cost - promo_discount - referral_bonus"
        },
        buyers: buyers,
        orders: orders
      }
    end

    private

    def quoted_statuses(list, fallback:)
      statuses = Array(list).compact.map(&:to_s).reject(&:blank?)
      statuses = fallback if statuses.empty?
      statuses.map { |status| ActiveRecord::Base.connection.quote(status) }.join(", ")
    end
  end
end
