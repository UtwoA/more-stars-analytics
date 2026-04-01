Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.log_level = :debug
  config.active_record.migration_error = :page_load
end

