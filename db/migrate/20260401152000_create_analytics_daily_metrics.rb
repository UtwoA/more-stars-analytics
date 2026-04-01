class CreateAnalyticsDailyMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_daily_metrics, id: false do |t|
      t.date :date, null: false
      t.bigint :orders_created_count, null: false, default: 0
      t.bigint :orders_paid_count, null: false, default: 0
      t.bigint :orders_failed_count, null: false, default: 0
      t.bigint :orders_cancelled_count, null: false, default: 0
      t.decimal :revenue_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :cost_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :profit_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :avg_check_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :pay_conversion_rate, precision: 8, scale: 4, null: false, default: 0
      t.bigint :unique_buyers_count, null: false, default: 0
      t.bigint :repeat_buyers_count, null: false, default: 0
      t.timestamps null: false
    end

    add_index :analytics_daily_metrics, :date, unique: true
  end
end

