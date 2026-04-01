# more-stars-analytics

Analytics service for `more-stars` built with Ruby on Rails.

The project is a standalone back-office analytics layer:
- reads raw business data from PostgreSQL (`orders`, `users`, `promos`, payments, referrals),
- computes pre-aggregated analytics tables,
- serves read-only API endpoints,
- provides an internal dashboard UI.

## Why This Project

`more-stars` core backend (FastAPI) remains source of truth for business flows and payments.  
`more-stars-analytics` focuses on reporting, insights, and operational visibility without touching checkout logic.

## Features

- Daily business metrics (orders, paid conversion, revenue, cost, profit)
- Product and provider breakdowns
- Referral and promo analytics
- Cohort and retention metrics
- Data quality checks and job history
- Dashboard pages:
  - Overview
  - Revenue
  - Users
  - Payments
  - Operations
- Password login + TOTP 2FA (Google Authenticator)

## Tech Stack

- Ruby `3.3.1`
- Rails `7.1` (API mode + static dashboard pages)
- PostgreSQL
- Sidekiq + Redis
- Docker / Docker Compose
- RSpec

## Architecture (MVP)

1. FastAPI backend writes domain data to PostgreSQL.
2. Analytics service reads core tables in read-only mode.
3. Background jobs compute aggregates into `analytics_*` tables.
4. API + dashboard read only aggregated data.

Core aggregate tables:
- `analytics_daily_metrics`
- `analytics_provider_daily_metrics`
- `analytics_product_daily_metrics`
- `analytics_referral_daily_metrics`
- `analytics_promo_daily_metrics`
- `analytics_cohort_weekly_metrics`
- `analytics_data_quality_issues`
- `analytics_job_runs`

## Security Model

- Internal dashboard authentication via:
  - password (`DASHBOARD_PASSWORD`)
  - TOTP 2FA (`DASHBOARD_2FA_SECRET`)
- Session-based auth for dashboard and JSON API.
- Optional machine token auth (`INTERNAL_API_TOKEN`) for service-to-service access.

## Local Development

1. Prepare env:
```bash
cp .env.example .env
```

2. Start containers:
```bash
docker compose up -d --build
```

3. Run migrations:
```bash
docker compose run --rm app bundle exec rails db:migrate
```

4. Generate 2FA secret:
```bash
docker compose run --rm app bundle exec rake auth:generate_2fa_secret
```

5. Put generated `DASHBOARD_2FA_SECRET` into `.env`, then restart:
```bash
docker compose up -d --build
```

6. Open:
- `http://localhost:3001/login`
- `http://localhost:3001/dashboard`

Important:
- local HTTP: `SESSION_COOKIE_SECURE=false`
- production HTTPS: `SESSION_COOKIE_SECURE=true`

## Restoring Real Data (Optional)

If you have a core database dump:

```bash
docker cp ./dumps/more_stars_core.dump more-stars-analytics-db-1:/tmp/more_stars_core.dump
docker exec -i more-stars-analytics-db-1 pg_restore \
  -U analytics \
  -d more_stars \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  /tmp/more_stars_core.dump
```

Then run backfill:
```bash
docker compose run --rm app bundle exec rake analytics:backfill_full FROM=2026-01-01 TO=2026-03-31
```

## Production Deployment

Server compose file:
- `docker-compose.server.yml`

Expected setup:
- shared Docker network with core DB container (`more-stars-db`)
- proper `DATABASE_URL` in `.env`
- reverse proxy (Nginx) + HTTPS

Typical commands:
```bash
docker compose -f docker-compose.server.yml up -d --build
docker compose -f docker-compose.server.yml run --rm app bundle exec rails db:migrate
docker compose -f docker-compose.server.yml run --rm app bundle exec rake analytics:backfill_full FROM=2026-01-01 TO=2026-03-31
```

## Configuration

See `.env.example` for full list.

Key variables:
- `DATABASE_URL`
- `REDIS_URL`
- `SECRET_KEY_BASE`
- `DASHBOARD_PASSWORD`
- `DASHBOARD_2FA_SECRET`
- `TOTP_ISSUER`
- `SESSION_TTL_HOURS`
- `SESSION_COOKIE_SECURE`
- `GIFT_DEFAULT_COST_RUB`
- `INTERNAL_API_TOKEN`

## API Overview

- `GET /health`
- `GET /metrics/daily`
- `GET /metrics/summary`
- `GET /metrics/providers`
- `GET /metrics/products`
- `GET /metrics/referrals`
- `GET /metrics/promos`
- `GET /metrics/cohorts`
- `GET /metrics/funnel`
- `GET /metrics/payments`
- `GET /metrics/insights`
- `GET /metrics/users`
- `GET /metrics/users/details`
- `GET /metrics/daily/details`
- `GET /ops/jobs`
- `GET /ops/data-quality`
- `POST /ops/backfill`
- `POST /ops/data-quality/run`
- `GET /exports/metrics`

## Dashboard Screenshots

Add screenshots into:
- `docs/assets/screenshots/overview.png`
- `docs/assets/screenshots/revenue.png`
- `docs/assets/screenshots/users.png`
- `docs/assets/screenshots/payments.png`

Then they will render here:

![Overview](docs/assets/screenshots/overview.png)
![Revenue](docs/assets/screenshots/revenue.png)
![Users](docs/assets/screenshots/users.png)
![Payments](docs/assets/screenshots/payments.png)

## CI/CD

GitHub Actions workflows:
- `CI` → `.github/workflows/ci.yml`
  - installs dependencies
  - migrates test DB
  - runs RSpec
- `Deploy` → `.github/workflows/deploy.yml`
  - manual (`workflow_dispatch`)
  - deploys via SSH
  - runs migrations on server

Required repository secrets for Deploy:
- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_SSH_KEY`
- `DEPLOY_PATH`

## Roadmap

- richer anomaly detection
- alerting (Telegram/email)
- role-based access and audit trail
- scheduled report delivery
- advanced funnel/event analytics

## License

Choose and add a license file (`MIT` recommended for pet-projects).
