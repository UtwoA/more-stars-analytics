module Metrics
  class FunnelController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])

      sql = <<~SQL
        WITH dates AS (
          SELECT generate_series(#{conn.quote(from)}::date, #{conn.quote(to)}::date, interval '1 day')::date AS date
        ),
        orders_daily AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS order_created_count,
            COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS order_paid_count,
            COUNT(DISTINCT o.user_id) AS app_open_count_proxy,
            COUNT(*) AS product_view_count_proxy,
            COUNT(*) FILTER (
              WHERE EXISTS (
                SELECT 1
                FROM payment_transactions pt
                WHERE pt.order_id = o.order_id
              )
            ) AS checkout_start_count_proxy
          FROM orders o
          WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          GROUP BY 1
        )
        SELECT
          d.date,
          COALESCE(od.app_open_count_proxy, 0) AS app_open_count,
          COALESCE(od.product_view_count_proxy, 0) AS product_view_count,
          COALESCE(od.checkout_start_count_proxy, 0) AS checkout_start_count,
          COALESCE(od.order_created_count, 0) AS order_created_count,
          COALESCE(od.order_paid_count, 0) AS order_paid_count
        FROM dates d
        LEFT JOIN orders_daily od ON od.date = d.date
        ORDER BY d.date
      SQL

      items = conn.exec_query(sql).to_a.map do |row|
        checkout_count = row["checkout_start_count"].to_i
        created_count = row["order_created_count"].to_i
        paid_count = row["order_paid_count"].to_i

        row.merge(
          "open_to_checkout_rate" => created_count.positive? ? (checkout_count.to_f / created_count).round(4) : 0.0,
          "checkout_to_created_rate" => created_count.positive? ? (checkout_count.to_f / created_count).round(4) : 0.0,
          "created_to_paid_rate" => created_count.positive? ? (paid_count.to_f / created_count).round(4) : 0.0
        )
      end

      render json: {
        from: from,
        to: to,
        is_proxy_funnel: true,
        notes: "MVP uses proxy funnel from orders/payment_transactions. App-open and product-view are approximated.",
        items: items
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
