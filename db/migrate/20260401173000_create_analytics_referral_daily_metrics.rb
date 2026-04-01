class CreateAnalyticsReferralDailyMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_referral_daily_metrics do |t|
      t.date :date, null: false
      t.bigint :new_referred_users_count, null: false, default: 0
      t.bigint :referred_buyers_count, null: false, default: 0
      t.bigint :referred_orders_paid_count, null: false, default: 0
      t.decimal :referred_revenue_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :referral_bonus_cost_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :referral_profit_rub, precision: 14, scale: 2, null: false, default: 0
      t.timestamps null: false
    end

    add_index :analytics_referral_daily_metrics, :date, unique: true
  end
end

