require "sidekiq"
require "sidekiq/cron/job"
require "yaml"
require "erb"

redis_url = ENV.fetch("REDIS_URL", "redis://redis:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  schedule_path = Rails.root.join("config/sidekiq.yml")
  if File.exist?(schedule_path)
    Sidekiq::Cron::Job.load_from_hash(YAML.safe_load(ERB.new(File.read(schedule_path)).result)[:schedule] || {})
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
