class CreateAnalyticsCohortWeeklyMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_cohort_weekly_metrics do |t|
      t.date :cohort_week, null: false
      t.integer :age_week, null: false
      t.bigint :users_count, null: false, default: 0
      t.bigint :repeat_buyers_count, null: false, default: 0
      t.decimal :retention_rate, precision: 8, scale: 4, null: false, default: 0
      t.decimal :period_revenue_rub, precision: 14, scale: 2, null: false, default: 0
      t.decimal :cumulative_revenue_rub, precision: 14, scale: 2, null: false, default: 0
      t.timestamps null: false
    end

    add_index :analytics_cohort_weekly_metrics, [:cohort_week, :age_week], unique: true, name: "idx_analytics_cohort_week_age"
    add_index :analytics_cohort_weekly_metrics, :cohort_week
  end
end

