require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"

Bundler.require(*Rails.groups)

module MoreStarsAnalytics
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    secure_cookie = ENV.fetch("SESSION_COOKIE_SECURE", "false") == "true" && Rails.env.production?
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_more_stars_analytics_session",
      same_site: :lax,
      httponly: true,
      secure: secure_cookie
    config.time_zone = ENV.fetch("APP_TIME_ZONE", "Europe/Moscow")
    config.active_job.queue_adapter = :sidekiq
    config.eager_load_paths << Rails.root.join("app/services")
  end
end
