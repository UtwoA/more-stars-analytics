require "rotp"

class AuthController < ApplicationController
  skip_before_action :authenticate_internal!, only: [:login_page, :login, :session_status]

  def login_page
    send_file Rails.root.join("public", "auth", "login.html"), type: "text/html", disposition: "inline"
  end

  def session_status
    render json: {
      authenticated: authenticated_session?,
      requires_2fa: totp_required?
    }
  end

  def login
    password = params[:password].to_s
    otp_code = params[:otp_code].to_s.gsub(/\s+/, "")
    if ENV.fetch("DASHBOARD_PASSWORD", "").to_s.blank?
      return render json: { error: "Не задан DASHBOARD_PASSWORD в .env" }, status: :unprocessable_entity
    end

    unless valid_password?(password)
      return render json: { error: "Неверный пароль" }, status: :unauthorized
    end

    if totp_required? && !valid_totp?(otp_code)
      return render json: { error: "Неверный код 2FA" }, status: :unauthorized
    end

    set_authenticated_session!
    render json: { ok: true }
  end

  def logout
    clear_authenticated_session!
    render json: { ok: true }
  end

  private

  def valid_password?(provided_password)
    expected = ENV.fetch("DASHBOARD_PASSWORD", "").to_s
    return false if expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(expected, provided_password)
  rescue StandardError
    false
  end

  def totp_required?
    ENV.fetch("DASHBOARD_2FA_SECRET", "").to_s.present?
  end

  def valid_totp?(otp_code)
    return false if otp_code.blank?

    secret = ENV.fetch("DASHBOARD_2FA_SECRET", "").to_s
    return false if secret.blank?

    totp = ROTP::TOTP.new(secret, issuer: ENV.fetch("TOTP_ISSUER", "more-stars-analytics"))
    !!totp.verify(otp_code, drift_behind: 30, drift_ahead: 30)
  rescue StandardError
    false
  end
end
