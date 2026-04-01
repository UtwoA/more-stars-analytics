class ApplicationController < ActionController::API
  include ActionController::Cookies

  before_action :authenticate_internal!

  private

  def authenticate_internal!
    return if authenticated_session?

    token = ENV["INTERNAL_API_TOKEN"].to_s
    if token.present?
      provided = request.headers["X-Internal-Token"].to_s
      valid = begin
        ActiveSupport::SecurityUtils.secure_compare(token, provided)
      rescue StandardError
        false
      end
      return if valid
    end

    if request.format.html? || request.path.start_with?("/dashboard")
      redirect_to "/login", allow_other_host: false
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def authenticated_session?
    authenticated_at = session[:admin_authenticated_at].to_i
    return false if authenticated_at.zero?

    ttl_hours = ENV.fetch("SESSION_TTL_HOURS", "12").to_i
    ttl_hours = 12 if ttl_hours <= 0
    ttl_seconds = ttl_hours * 3600
    Time.current.to_i - authenticated_at <= ttl_seconds
  end

  def set_authenticated_session!
    session[:admin_authenticated_at] = Time.current.to_i
  end

  def clear_authenticated_session!
    reset_session
  end

  def parse_date(value)
    return nil if value.blank?

    Date.iso8601(value)
  rescue ArgumentError
    nil
  end
end
