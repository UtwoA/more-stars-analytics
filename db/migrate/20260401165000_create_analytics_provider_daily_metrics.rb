class CreateAnalyticsProviderDailyMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_provider_daily_metrics do |t|
      t.date :date, null: false
      t.string :payment_provider, null: false
      t.bigint :orders_created_count, null: false, default: 0
      t.bigint :orders_paid_count, null: false, default: 0
      t.decimal :revenue_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :cost_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :profit_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :avg_check_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :paid_conversion_rate, precision: 8, scale: 4, null: false, default: 0
      t.timestamps null: false
    end

    add_index :analytics_provider_daily_metrics, [:date, :payment_provider], unique: true, name: "idx_analytics_provider_date_provider"
    add_index :analytics_provider_daily_metrics, :payment_provider
  end
end

