module Metrics
  class InsightsController < ApplicationController
    def index
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      return render json: { error: "`to` must be greater than or equal to `from`" }, status: :unprocessable_entity if to < from

      conn = ActiveRecord::Base.connection
      paid_statuses = quoted_statuses(ORDER_STATUSES["paid"], fallback: ["paid"])

      kpis = build_kpis(conn, from, to, paid_statuses)
      anomalies = build_anomalies(conn, from, to)
      hourly_heatmap = build_hourly_heatmap(conn, from, to, paid_statuses)

      render json: {
        from: from,
        to: to,
        kpis: kpis,
        anomalies: anomalies,
        hourly_heatmap: hourly_heatmap
      }
    end

    private

    def build_kpis(conn, from, to, paid_statuses)
      summary = conn.exec_query(<<~SQL).first || {}
        SELECT
          COALESCE(SUM(adm.revenue_rub), 0)::float AS revenue_rub,
          COALESCE(SUM(adm.profit_rub), 0)::float AS profit_rub,
          COALESCE(SUM(adm.orders_paid_count), 0)::bigint AS paid_orders_count,
          COALESCE(SUM(adm.unique_buyers_count), 0)::bigint AS unique_buyers_count,
          COALESCE(SUM(adm.repeat_buyers_count), 0)::bigint AS repeat_buyers_count
        FROM analytics_daily_metrics adm
        WHERE adm.date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
      SQL

      retention = conn.exec_query(<<~SQL).first || {}
        WITH paid_orders AS (
          SELECT
            o.user_id,
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS paid_date,
            COALESCE(o.amount_rub, 0)::float AS amount_rub
          FROM orders o
          WHERE o.status IN (#{paid_statuses})
            AND o.user_id IS NOT NULL
        ),
        first_paid AS (
          SELECT
            po.user_id,
            MIN(po.paid_date) AS first_paid_date
          FROM paid_orders po
          GROUP BY po.user_id
        ),
        base AS (
          SELECT fp.user_id, fp.first_paid_date
          FROM first_paid fp
          WHERE fp.first_paid_date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ),
        r AS (
          SELECT
            COUNT(*) AS users_in_base,
            COUNT(*) FILTER (
              WHERE EXISTS (
                SELECT 1 FROM paid_orders po
                WHERE po.user_id = b.user_id
                  AND po.paid_date > b.first_paid_date
                  AND po.paid_date <= (b.first_paid_date + 7)
              )
            ) AS retained_d7,
            COUNT(*) FILTER (
              WHERE EXISTS (
                SELECT 1 FROM paid_orders po
                WHERE po.user_id = b.user_id
                  AND po.paid_date > b.first_paid_date
                  AND po.paid_date <= (b.first_paid_date + 30)
              )
            ) AS retained_d30
          FROM base b
        ),
        ltv AS (
          SELECT
            COUNT(*) AS cohort_users,
            COALESCE(SUM(po.amount_rub), 0)::float AS cohort_revenue_30d
          FROM base b
          JOIN paid_orders po
            ON po.user_id = b.user_id
           AND po.paid_date >= b.first_paid_date
           AND po.paid_date <= (b.first_paid_date + 30)
        )
        SELECT
          r.users_in_base,
          r.retained_d7,
          r.retained_d30,
          ltv.cohort_users,
          ltv.cohort_revenue_30d
        FROM r, ltv
      SQL

      cost = conn.exec_query(<<~SQL).first || {}
        SELECT
          (
            COALESCE((SELECT SUM(discount_total_rub) FROM analytics_promo_daily_metrics WHERE date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date), 0)
            +
            COALESCE((SELECT SUM(referral_bonus_cost_rub) FROM analytics_referral_daily_metrics WHERE date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date), 0)
          )::float AS acquisition_cost_rub
      SQL

      repeat_revenue = conn.exec_query(<<~SQL).first || {}
        WITH paid_orders AS (
          SELECT
            o.user_id,
            (o.timestamp AT TIME ZONE 'Europe/Moscow')::date AS paid_date,
            COALESCE(o.amount_rub, 0)::float AS amount_rub
          FROM orders o
          WHERE o.status IN (#{paid_statuses})
            AND o.user_id IS NOT NULL
            AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ),
        first_paid AS (
          SELECT
            o.user_id,
            MIN((o.timestamp AT TIME ZONE 'Europe/Moscow')::date) AS first_paid_date
          FROM orders o
          WHERE o.status IN (#{paid_statuses})
            AND o.user_id IS NOT NULL
          GROUP BY o.user_id
        )
        SELECT
          COALESCE(SUM(po.amount_rub), 0)::float AS total_revenue_rub,
          COALESCE(SUM(po.amount_rub) FILTER (WHERE po.paid_date > fp.first_paid_date), 0)::float AS repeat_revenue_rub
        FROM paid_orders po
        JOIN first_paid fp ON fp.user_id = po.user_id
      SQL

      revenue = summary["revenue_rub"].to_f
      profit = summary["profit_rub"].to_f
      paid_orders_count = summary["paid_orders_count"].to_i
      unique_buyers_count = summary["unique_buyers_count"].to_i
      repeat_buyers_count = summary["repeat_buyers_count"].to_i
      users_in_base = retention["users_in_base"].to_i
      retained_d7 = retention["retained_d7"].to_i
      retained_d30 = retention["retained_d30"].to_i
      cohort_users = retention["cohort_users"].to_i
      cohort_revenue_30d = retention["cohort_revenue_30d"].to_f
      acquisition_cost = cost["acquisition_cost_rub"].to_f
      repeat_revenue_rub = repeat_revenue["repeat_revenue_rub"].to_f
      total_revenue_rub = repeat_revenue["total_revenue_rub"].to_f

      {
        arppu_rub: unique_buyers_count.positive? ? (revenue / unique_buyers_count).round(2) : 0.0,
        gross_margin_rate: revenue.positive? ? (profit / revenue).round(4) : 0.0,
        retention_d7_rate: users_in_base.positive? ? (retained_d7.to_f / users_in_base).round(4) : 0.0,
        retention_d30_rate: users_in_base.positive? ? (retained_d30.to_f / users_in_base).round(4) : 0.0,
        ltv_30d_proxy_rub: cohort_users.positive? ? (cohort_revenue_30d / cohort_users).round(2) : 0.0,
        cac_proxy_rub: users_in_base.positive? ? (acquisition_cost / users_in_base).round(2) : 0.0,
        repeat_revenue_share: total_revenue_rub.positive? ? (repeat_revenue_rub / total_revenue_rub).round(4) : 0.0,
        repeat_buyer_rate: unique_buyers_count.positive? ? (repeat_buyers_count.to_f / unique_buyers_count).round(4) : 0.0,
        paid_orders_count: paid_orders_count,
        users_in_base: users_in_base
      }
    end

    def build_anomalies(conn, from, to)
      metrics = conn.exec_query(<<~SQL).to_a
        SELECT
          adm.date,
          COALESCE(adm.revenue_rub, 0)::float AS revenue_rub,
          COALESCE(adm.orders_paid_count, 0)::bigint AS orders_paid_count
        FROM analytics_daily_metrics adm
        WHERE adm.date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
        ORDER BY adm.date
      SQL
      return [] if metrics.empty?

      revenue_values = metrics.map { |m| m["revenue_rub"].to_f }
      paid_values = metrics.map { |m| m["orders_paid_count"].to_f }
      revenue_mean = mean(revenue_values)
      paid_mean = mean(paid_values)
      revenue_std = stddev(revenue_values, revenue_mean)
      paid_std = stddev(paid_values, paid_mean)

      out = []
      metrics.each do |m|
        rev_z = zscore(m["revenue_rub"].to_f, revenue_mean, revenue_std)
        paid_z = zscore(m["orders_paid_count"].to_f, paid_mean, paid_std)
        if rev_z.abs >= 2.0
          out << {
            date: m["date"],
            metric: "revenue_rub",
            value: m["revenue_rub"].to_f.round(2),
            z_score: rev_z.round(2)
          }
        end
        if paid_z.abs >= 2.0
          out << {
            date: m["date"],
            metric: "orders_paid_count",
            value: m["orders_paid_count"].to_i,
            z_score: paid_z.round(2)
          }
        end
      end

      out.sort_by { |row| -row[:z_score].abs }.first(30)
    end

    def build_hourly_heatmap(conn, from, to, paid_statuses)
      conn.exec_query(<<~SQL).to_a
        SELECT
          EXTRACT(ISODOW FROM (o.timestamp AT TIME ZONE 'Europe/Moscow'))::int AS iso_dow,
          EXTRACT(HOUR FROM (o.timestamp AT TIME ZONE 'Europe/Moscow'))::int AS hour,
          COUNT(*) AS paid_orders_count,
          COALESCE(SUM(o.amount_rub), 0)::float AS revenue_rub
        FROM orders o
        WHERE (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{conn.quote(from)}::date AND #{conn.quote(to)}::date
          AND o.status IN (#{paid_statuses})
        GROUP BY 1, 2
        ORDER BY 1, 2
      SQL
    end

    def quoted_statuses(list, fallback:)
      statuses = Array(list).compact.map(&:to_s).reject(&:blank?)
      statuses = fallback if statuses.empty?
      statuses.map { |status| ActiveRecord::Base.connection.quote(status) }.join(", ")
    end

    def mean(values)
      return 0.0 if values.empty?
      values.sum.to_f / values.size
    end

    def stddev(values, m)
      return 0.0 if values.empty?
      variance = values.sum { |v| (v - m)**2 } / values.size
      Math.sqrt(variance)
    end

    def zscore(value, m, s)
      return 0.0 if s <= 0.000001
      (value - m) / s
    end
  end
end
