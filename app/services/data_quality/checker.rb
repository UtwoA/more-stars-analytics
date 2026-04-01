module DataQuality
  class Checker
    def run!(from_date:, to_date:)
      now = Time.current
      issues = []

      issues.concat(find_missing_days(from_date, to_date, now))
      issues.concat(find_negative_revenue(now))
      issues.concat(find_paid_mismatch(from_date, to_date, now))

      issues.each { |attrs| AnalyticsDataQualityIssue.create!(attrs) }
      issues.size
    end

    private

    def find_missing_days(from_date, to_date, now)
      sql = <<~SQL
        WITH expected AS (
          SELECT generate_series($1::date, $2::date, interval '1 day')::date AS date
        )
        SELECT e.date
        FROM expected e
        LEFT JOIN analytics_daily_metrics adm ON adm.date = e.date
        WHERE adm.date IS NULL
        ORDER BY e.date;
      SQL

      rows = ApplicationRecord.connection.exec_query(sql, "missing_days", [
        ActiveRecord::Relation::QueryAttribute.new("from_date", from_date, ActiveRecord::Type::Date.new),
        ActiveRecord::Relation::QueryAttribute.new("to_date", to_date, ActiveRecord::Type::Date.new)
      ])

      rows.map do |r|
        date = r["date"]
        {
          issue_code: "missing_daily_row",
          severity: "warning",
          message: "No analytics_daily_metrics row for date #{date}",
          meta: { date: date },
          detected_at: now
        }
      end
    end

    def find_negative_revenue(now)
      bad_rows = AnalyticsDailyMetric.where("revenue_rub < 0 OR profit_rub < -1000000").limit(100)
      bad_rows.map do |row|
        {
          issue_code: "negative_revenue_or_profit",
          severity: "critical",
          message: "Suspicious values on #{row.date}: revenue=#{row.revenue_rub}, profit=#{row.profit_rub}",
          meta: { date: row.date, revenue_rub: row.revenue_rub, profit_rub: row.profit_rub },
          detected_at: now
        }
      end
    end

    def find_paid_mismatch(from_date, to_date, now)
      conn = ApplicationRecord.connection
      from_q = conn.quote(from_date)
      to_q = conn.quote(to_date)

      raw_paid = conn.select_value(<<~SQL).to_i
        SELECT COUNT(*)::bigint
        FROM orders o
        WHERE o.status = 'paid'
          AND (o.timestamp AT TIME ZONE 'Europe/Moscow')::date BETWEEN #{from_q}::date AND #{to_q}::date
      SQL

      agg_paid = AnalyticsDailyMetric.where(date: from_date..to_date).sum(:orders_paid_count).to_i
      return [] if raw_paid == agg_paid

      [
        {
          issue_code: "paid_count_mismatch",
          severity: "critical",
          message: "Raw paid orders (#{raw_paid}) != analytics_daily_metrics paid (#{agg_paid})",
          meta: { from: from_date, to: to_date, raw_paid: raw_paid, agg_paid: agg_paid, diff: raw_paid - agg_paid },
          detected_at: now
        }
      ]
    end
  end
end
