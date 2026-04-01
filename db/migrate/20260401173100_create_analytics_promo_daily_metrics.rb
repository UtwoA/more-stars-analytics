class CreateAnalyticsPromoDailyMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_promo_daily_metrics do |t|
      t.date :date, null: false
      t.string :promo_code, null: false
      t.bigint :redemptions_count, null: false, default: 0
      t.bigint :paid_orders_count, null: false, default: 0
      t.decimal :discount_total_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :revenue_after_discount_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :profit_after_discount_rub, precision: 14, scale: 2, null: false, default: 0
      t.timestamps null: false
    end

    add_index :analytics_promo_daily_metrics, [:date, :promo_code], unique: true, name: "idx_analytics_promo_date_code"
    add_index :analytics_promo_daily_metrics, :promo_code
  end
end

