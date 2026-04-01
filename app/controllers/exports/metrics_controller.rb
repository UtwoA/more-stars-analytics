require "csv"

module Exports
  class MetricsController < ApplicationController
    def index
      kind = params[:kind].to_s.presence || "daily"
      from = parse_date(params[:from]) || Date.current - 29
      to = parse_date(params[:to]) || Date.current
      return render plain: "`to` must be greater than or equal to `from`", status: :unprocessable_entity if to < from

      filename = "metrics_#{kind}_#{from}_#{to}.csv"
      send_data csv_for(kind, from, to), filename: filename, type: "text/csv"
    end

    private

    def csv_for(kind, from, to)
      case kind
      when "providers"
        to_csv(AnalyticsProviderDailyMetric.where(date: from..to).order(:date, :payment_provider))
      when "products"
        to_csv(AnalyticsProductDailyMetric.where(date: from..to).order(:date, :product_type))
      when "referrals"
        to_csv(AnalyticsReferralDailyMetric.where(date: from..to).order(:date))
      when "promos"
        to_csv(AnalyticsPromoDailyMetric.where(date: from..to).order(:date, :promo_code))
      when "cohorts"
        from_week = from.beginning_of_week
        to_week = to.beginning_of_week
        to_csv(AnalyticsCohortWeeklyMetric.where(cohort_week: from_week..to_week).order(:cohort_week, :age_week))
      else
        to_csv(AnalyticsDailyMetric.where(date: from..to).order(:date))
      end
    end

    def to_csv(relation)
      rows = relation.to_a
      return "" if rows.empty?

      headers = rows.first.attributes.keys
      CSV.generate(headers: true) do |csv|
        csv << headers
        rows.each { |row| csv << headers.map { |h| row.attributes[h] } }
      end
    end
  end
end

