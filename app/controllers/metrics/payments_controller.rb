module Metrics
  class PaymentsController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])
      failed_statuses = quoted_statuses(ORDER_STATUSES["failed"], fallback: ["failed"])
      tx_success_statuses = quoted_statuses(
        Array(ORDER_STATUSES["paid"]) + %w[success succeeded confirmed SUCCESS SUCCEEDED CONFIRMED],
        fallback: ["paid", "success", "succeeded", "confirmed", "CONFIRMED"]
      )

      daily_sql = <<~SQL
        WITH dates AS (
          SELECT generate_series(#{conn.quote(from)}::date, #{conn.quote(to)}::date, interval '1 day')::date AS date
        ),
        o AS (
          SELECT
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS date,
            COUNT(*) AS orders_created_count,
            COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS orders_paid_count,
            COUNT(*) FILTER (WHERE o.status IN (#{failed_statuses})) AS orders_failed_count,
            COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::numeric(14,2) AS revenue_rub
          FROM orders o
          WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          GROUP BY 1
        ),
        tx_raw AS (
          SELECT
            (COALESCE(pt.created_at, o.timestamp) AT TIME ZONE 'Europe/Moscow')::date AS date,
            CASE
              WHEN COALESCE(NULLIF(pt.provider, ''), 'unknown') = 'platega_status' THEN 'platega'
              ELSE COALESCE(NULLIF(pt.provider, ''), 'unknown')
            END AS provider,
            CASE
              WHEN NULLIF(pt.provider_txn_id, '') IS NOT NULL THEN CONCAT(
                CASE
                  WHEN COALESCE(NULLIF(pt.provider, ''), 'unknown') = 'platega_status' THEN 'platega'
                  ELSE COALESCE(NULLIF(pt.provider, ''), 'unknown')
                END,
                ':',
                pt.provider_txn_id
              )
              WHEN pt.order_id IS NOT NULL THEN CONCAT('order:', pt.order_id)
              ELSE CONCAT('row:', pt.id::text)
            END AS tx_key,
            CASE WHEN pt.status IN (#{tx_success_statuses}) THEN 1 ELSE 0 END AS is_success
          FROM payment_transactions pt
          LEFT JOIN orders o ON o.order_id = pt.order_id
          WHERE (COALESCE(pt.created_at, o.timestamp) AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ),
        tx_group AS (
          SELECT
            tr.date,
            tr.tx_key,
            MAX(tr.is_success) AS has_success
          FROM tx_raw tr
          GROUP BY 1, 2
        ),
        t AS (
          SELECT
            tg.date,
            COUNT(*) AS payment_attempts_count,
            COUNT(*) FILTER (WHERE tg.has_success = 1) AS payment_success_count,
            COUNT(*) FILTER (WHERE tg.has_success = 0) AS payment_failed_count
          FROM tx_group tg
          GROUP BY 1
        ),
        raw_events AS (
          SELECT tr.date, COUNT(*) AS payment_events_count
          FROM tx_raw tr
          GROUP BY 1
        )
        SELECT
          d.date,
          COALESCE(o.orders_created_count, 0) AS orders_created_count,
          COALESCE(o.orders_paid_count, 0) AS orders_paid_count,
          COALESCE(o.orders_failed_count, 0) AS orders_failed_count,
          COALESCE(o.revenue_rub, 0)::float AS revenue_rub,
          COALESCE(t.payment_attempts_count, 0) AS payment_attempts_count,
          COALESCE(t.payment_success_count, 0) AS payment_success_count,
          COALESCE(t.payment_failed_count, 0) AS payment_failed_count,
          COALESCE(re.payment_events_count, 0) AS payment_events_count
        FROM dates d
        LEFT JOIN o ON o.date = d.date
        LEFT JOIN t ON t.date = d.date
        LEFT JOIN raw_events re ON re.date = d.date
        ORDER BY d.date
      SQL

      providers_sql = <<~SQL
        WITH o AS (
          SELECT
            COALESCE(NULLIF(o.payment_provider, ''), 'unknown') AS provider,
            COUNT(*) AS orders_created_count,
            COUNT(*) FILTER (WHERE o.status IN (#{paid_statuses})) AS orders_paid_count,
            COALESCE(SUM(o.amount_rub) FILTER (WHERE o.status IN (#{paid_statuses})), 0)::numeric(14,2) AS revenue_rub
          FROM orders o
          WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          GROUP BY 1
        ),
        tx_raw AS (
          SELECT
            CASE
              WHEN COALESCE(NULLIF(pt.provider, ''), 'unknown') = 'platega_status' THEN 'platega'
              ELSE COALESCE(NULLIF(pt.provider, ''), 'unknown')
            END AS provider,
            CASE
              WHEN NULLIF(pt.provider_txn_id, '') IS NOT NULL THEN CONCAT(
                CASE
                  WHEN COALESCE(NULLIF(pt.provider, ''), 'unknown') = 'platega_status' THEN 'platega'
                  ELSE COALESCE(NULLIF(pt.provider, ''), 'unknown')
                END,
                ':',
                pt.provider_txn_id
              )
              WHEN pt.order_id IS NOT NULL THEN CONCAT('order:', pt.order_id)
              ELSE CONCAT('row:', pt.id::text)
            END AS tx_key,
            CASE WHEN pt.status IN (#{tx_success_statuses}) THEN 1 ELSE 0 END AS is_success
          FROM payment_transactions pt
          LEFT JOIN orders o ON o.order_id = pt.order_id
          WHERE (COALESCE(pt.created_at, o.timestamp) AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ),
        tx_group AS (
          SELECT
            tr.provider,
            tr.tx_key,
            MAX(tr.is_success) AS has_success
          FROM tx_raw tr
          GROUP BY 1, 2
        ),
        t AS (
          SELECT
            tg.provider,
            COUNT(*) AS payment_attempts_count,
            COUNT(*) FILTER (WHERE tg.has_success = 1) AS payment_success_count,
            COUNT(*) FILTER (WHERE tg.has_success = 0) AS payment_failed_count
          FROM tx_group tg
          GROUP BY 1
        ),
        raw_events AS (
          SELECT tr.provider, COUNT(*) AS payment_events_count
          FROM tx_raw tr
          GROUP BY 1
        )
        SELECT
          COALESCE(o.provider, t.provider) AS provider,
          COALESCE(o.orders_created_count, 0) AS orders_created_count,
          COALESCE(o.orders_paid_count, 0) AS orders_paid_count,
          COALESCE(o.revenue_rub, 0)::float AS revenue_rub,
          COALESCE(t.payment_attempts_count, 0) AS payment_attempts_count,
          COALESCE(t.payment_success_count, 0) AS payment_success_count,
          COALESCE(t.payment_failed_count, 0) AS payment_failed_count,
          COALESCE(re.payment_events_count, 0) AS payment_events_count
        FROM o
        FULL OUTER JOIN t ON t.provider = o.provider
        LEFT JOIN raw_events re ON re.provider = COALESCE(o.provider, t.provider)
        ORDER BY revenue_rub DESC, payment_attempts_count DESC
      SQL

      failure_reasons_sql = <<~SQL
        WITH tx_raw AS (
          SELECT
            CASE
              WHEN COALESCE(NULLIF(pt.provider, ''), 'unknown') = 'platega_status' THEN 'platega'
              ELSE COALESCE(NULLIF(pt.provider, ''), 'unknown')
            END AS provider,
            COALESCE(NULLIF(pt.status, ''), 'unknown') AS status,
            CASE
              WHEN NULLIF(pt.provider_txn_id, '') IS NOT NULL THEN CONCAT(
                CASE
                  WHEN COALESCE(NULLIF(pt.provider, ''), 'unknown') = 'platega_status' THEN 'platega'
                  ELSE COALESCE(NULLIF(pt.provider, ''), 'unknown')
                END,
                ':',
                pt.provider_txn_id
              )
              WHEN pt.order_id IS NOT NULL THEN CONCAT('order:', pt.order_id)
              ELSE CONCAT('row:', pt.id::text)
            END AS tx_key,
            CASE WHEN pt.status IN (#{tx_success_statuses}) THEN 1 ELSE 0 END AS is_success
          FROM payment_transactions pt
          LEFT JOIN orders o ON o.order_id = pt.order_id
          WHERE (COALESCE(pt.created_at, o.timestamp) AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ),
        tx_unsuccessful AS (
          SELECT tr.provider, tr.tx_key
          FROM tx_raw tr
          GROUP BY tr.provider, tr.tx_key
          HAVING MAX(tr.is_success) = 0
        )
        SELECT
          tr.provider,
          tr.status,
          COUNT(DISTINCT tr.tx_key) AS failures_count
        FROM tx_raw tr
        JOIN tx_unsuccessful tu ON tu.provider = tr.provider AND tu.tx_key = tr.tx_key
        WHERE tr.is_success = 0
        GROUP BY tr.provider, tr.status
        ORDER BY failures_count DESC
        LIMIT 50
      SQL

      daily = conn.exec_query(daily_sql).to_a
      providers = conn.exec_query(providers_sql).to_a
      failure_reasons = conn.exec_query(failure_reasons_sql).to_a

      summary = {
        orders_created_count: daily.sum { |r| r["orders_created_count"].to_i },
        orders_paid_count: daily.sum { |r| r["orders_paid_count"].to_i },
        orders_failed_count: daily.sum { |r| r["orders_failed_count"].to_i },
        payment_attempts_count: daily.sum { |r| r["payment_attempts_count"].to_i },
        payment_success_count: daily.sum { |r| r["payment_success_count"].to_i },
        payment_failed_count: daily.sum { |r| r["payment_failed_count"].to_i },
        payment_events_count: daily.sum { |r| r["payment_events_count"].to_i },
        revenue_rub: daily.sum { |r| r["revenue_rub"].to_f }.round(2)
      }
      summary[:payment_success_rate] = summary[:payment_attempts_count].positive? ? (summary[:payment_success_count].to_f / summary[:payment_attempts_count]).round(4) : 0.0
      summary[:paid_order_rate] = summary[:orders_created_count].positive? ? (summary[:orders_paid_count].to_f / summary[:orders_created_count]).round(4) : 0.0

      render json: {
        from: from,
        to: to,
        summary: summary,
        daily: daily,
        providers: providers,
        failure_reasons: failure_reasons
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
