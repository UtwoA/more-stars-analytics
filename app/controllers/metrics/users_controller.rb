module Metrics
  class UsersController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      limit = (params[:limit] || 200).to_i.clamp(1, 1000)
      query = params[:q].to_s.strip

      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])
      effective_cost_sql = OrderMetricsSql.effective_cost_sql("o")
      query_sql = query.present? ? "AND (u.user_id ILIKE #{conn.quote("%#{query}%")} OR u.username ILIKE #{conn.quote("%#{query}%")})" : ""

      items = conn.exec_query(<<~SQL).to_a
        SELECT
          u.user_id,
          COALESCE(NULLIF(u.username, ''), '-') AS username,
          COALESCE(NULLIF(u.referrer_id, ''), '-') AS referrer_id,
          (u.created_at AT TIME ZONE 'Europe/Moscow')::date AS user_created_date,
          COUNT(o.order_id) FILTER (WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date) AS orders_created_count,
          COUNT(o.order_id) FILTER (WHERE o.status IN (#{paid_statuses}) AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date) AS orders_paid_count,
          COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses}) AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date), 0)::float AS revenue_rub,
          COALESCE(SUM(COALESCE(o.amount_rub, 0) - (#{effective_cost_sql})) FILTER (WHERE o.status IN (#{paid_statuses}) AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date), 0)::float AS gross_profit_rub,
          MIN((o.timestamp AT TIME ZONE 'Europe/Moscow')::date) FILTER (WHERE o.status IN (#{paid_statuses})) AS first_paid_date,
          MAX((o.timestamp AT TIME ZONE 'Europe/Moscow')::date) FILTER (WHERE o.status IN (#{paid_statuses})) AS last_paid_date
        FROM users u
        LEFT JOIN orders o ON o.user_id = u.user_id
        WHERE 1=1
          #{query_sql}
        GROUP BY u.user_id, u.username, u.referrer_id, u.created_at
        ORDER BY revenue_rub DESC, orders_paid_count DESC
        LIMIT #{limit}
      SQL

      render json: { from: from, to: to, items: items }
    end

    def show
      user_id = params[:user_id].to_s
      return render json: { error: "user_id is required" }, status: :unprocessable_entity if user_id.blank?

      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])
      effective_cost_sql = OrderMetricsSql.effective_cost_sql("o")

      profile = conn.exec_query(<<~SQL).first
        SELECT
          u.user_id,
          COALESCE(NULLIF(u.username, ''), '-') AS username,
          COALESCE(NULLIF(u.referrer_id, ''), '-') AS referrer_id,
          (u.created_at AT TIME ZONE 'Europe/Moscow')::date AS user_created_date
        FROM users u
        WHERE u.user_id = #{conn.quote(user_id)}
      SQL
      return render json: { error: "User not found" }, status: :not_found unless profile

      summary = conn.exec_query(<<~SQL).first || {}
        SELECT
          COUNT(*) AS orders_created_count,
          COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS orders_paid_count,
          COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS revenue_rub,
          COALESCE(SUM(COALESCE(o.amount_rub, 0) - (#{effective_cost_sql})) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::float AS gross_profit_rub
        FROM orders o
        WHERE o.user_id = #{conn.quote(user_id)}
          AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
      SQL

      orders = conn.exec_query(<<~SQL).to_a
        SELECT
          o.order_id,
          o.status,
          o.product_type,
          COALESCE(NULLIF(o.payment_provider, ''), 'unknown') AS payment_provider,
          COALESCE(o.amount_rub, 0)::float AS amount_rub,
          (#{effective_cost_sql})::float AS cost_rub,
          COALESCE(o.promo_code, '-') AS promo_code,
          (o.timestamp AT TIME ZONE 'Europe/Moscow') AS timestamp_msk
        FROM orders o
        WHERE o.user_id = #{conn.quote(user_id)}
          AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ORDER BY o.timestamp DESC
        LIMIT 300
      SQL

      render json: { from: from, to: to, profile: profile, summary: summary, orders: orders }
    end

    private

    def quoted_statuses(list, fallback:)
      statuses = Array(list).compact.map(&:to_s).reject(&:blank?)
      statuses = fallback if statuses.empty?
      statuses.map { |status| ActiveRecord::Base.connection.quote(status) }.join(", ")
    end
  end
end
