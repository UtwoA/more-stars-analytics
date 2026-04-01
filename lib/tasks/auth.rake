require "rotp"

namespace :auth do
  desc "Generate Google Authenticator secret for DASHBOARD_2FA_SECRET"
  task generate_2fa_secret: :environment do
    secret = ROTP::Base32.random
    issuer = ENV.fetch("TOTP_ISSUER", "more-stars-analytics")
    account = ENV.fetch("TOTP_ACCOUNT_NAME", "admin")
    totp = ROTP::TOTP.new(secret, issuer: issuer)

    puts "DASHBOARD_2FA_SECRET=#{secret}"
    puts "Provisioning URI:"
    puts totp.provisioning_uri(account)
  end
end
