class CreateAnalyticsProductDailyMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_product_daily_metrics do |t|
      t.date :date, null: false
      t.string :product_type, null: false
      t.bigint :orders_paid_count, null: false, default: 0
      t.decimal :revenue_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :cost_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :profit_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :avg_check_rub, precision: 14, scale: 2, null: false, default: 0
      t.timestamps null: false
    end

    add_index :analytics_product_daily_metrics, [:date, :product_type], unique: true, name: "idx_analytics_product_date_type"
    add_index :analytics_product_daily_metrics, :product_type
  end
end

