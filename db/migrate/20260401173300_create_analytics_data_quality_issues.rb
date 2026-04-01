class CreateAnalyticsDataQualityIssues < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_data_quality_issues do |t|
      t.string :issue_code, null: false
      t.string :severity, null: false, default: "warning"
      t.text :message, null: false
      t.jsonb :meta, null: false, default: {}
      t.datetime :detected_at, null: false
      t.boolean :resolved, null: false, default: false
      t.timestamps null: false
    end

    add_index :analytics_data_quality_issues, :issue_code
    add_index :analytics_data_quality_issues, :detected_at
    add_index :analytics_data_quality_issues, :resolved
  end
end

