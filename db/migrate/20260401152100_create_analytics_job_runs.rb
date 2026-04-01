class CreateAnalyticsJobRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :analytics_job_runs do |t|
      t.string :job_name, null: false
      t.date :range_start
      t.date :range_end
      t.string :status, null: false
      t.integer :rows_written
      t.text :error_text
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps null: false
    end

    add_index :analytics_job_runs, :job_name
    add_index :analytics_job_runs, :status
    add_index :analytics_job_runs, [:job_name, :finished_at]
  end
end

