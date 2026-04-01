# more-stars-analytics: MVP-ТЗ (v1.0)

## 1. Цель MVP
Сделать отдельный read-only сервис аналитики на Ruby поверх существующего `more-stars`, где:
- FastAPI остаётся `source of truth` по заказам/оплатам/бизнес-логике;
- analytics-сервис читает исходные данные из PostgreSQL;
- считает агрегаты и сохраняет их в `analytics_*` таблицы;
- отдаёт готовые метрики по внутреннему API для admin/analytics панели.

MVP отвечает на 4 бизнес-вопроса:
1. Сколько заказов/оплат было.
2. Какая выручка/себестоимость/маржа.
3. Как работают провайдеры и продукты.
4. Как работают возвраты, рефералки и промокоды.

## 2. Контекст и ограничения
### Формат проекта (обязательно)
- `more-stars-analytics` — отдельный проект и отдельный Git-репозиторий.
- Он не является подпапкой `more-stars` и не деплоится как часть FastAPI-сервиса.
- Связь между репозиториями только через:
  - общую PostgreSQL (read-only доступ analytics к core-таблицам);
  - внутренний API analytics для admin/панели;
  - общие договорённости по статусам/семантике данных.

### Уже есть в `more-stars`
- FastAPI backend (`backend/app`).
- PostgreSQL с доменными таблицами.
- API-группы: `orders`, `webhooks`, `admin`.
- Таблицы: `orders`, `payment_transactions`, `users`, `promo_codes`, `promo_redemptions`, `referral_earnings`, `bonus_grants`, `bonus_claim*`.
- Админ-аналитика и daily report в Python (`admin.py`, `admin_reports.py`).

### Не делаем в MVP
- Не меняем checkout-flow и подтверждение оплат.
- Не переносим webhook-логику в Ruby.
- Не пишем в core-таблицы (`orders/users/...`).
- Не строим realtime/event bus/BI-конструктор.

## 3. Архитектура MVP
### Схема
`FastAPI -> PostgreSQL (core tables) <- Ruby analytics service -> analytics_* tables -> read-only API`

### Рекомендуемый стек
- Ruby 3.3+
- Rails API
- ActiveRecord + `pg`
- Sidekiq + Redis
- RSpec

## 4. Источники данных (фактические)
Минимальный набор из текущей схемы:
- `orders` (основной источник по lifecycle/суммам/продукту/провайдеру).
- `payment_transactions` (доп. детализация платежей при необходимости).
- `users` (first seen/referrer/retention).
- `promo_redemptions`, `promo_codes` (промо-аналитика).
- `referral_earnings`, `bonus_grants` (реферальные/бонусные затраты).
- `app_events` (опционально для полной воронки; если нет данных, считаем payment funnel).

## 5. Status mapping (контракт)
Источник истины статусов: `orders.status`.

MVP-правила:
- `paid`: `status = 'paid'`
- `failed`: `status = 'failed'`
- `created`: `status = 'created'`
- `cancelled`: отдельной стабильной категории в текущем коде нет; в MVP считается `0`, пока не введён явный статус.

Важно: mapping хранится в конфиге Ruby-сервиса (`config/order_statuses.yml`) для расширения без изменения SQL.

## 6. Набор агрегатов MVP
### `analytics_daily_metrics`
- `date` (PK)
- `orders_created_count`
- `orders_paid_count`
- `orders_failed_count`
- `orders_cancelled_count`
- `revenue_rub`
- `cost_rub`
- `profit_rub`
- `avg_check_rub`
- `pay_conversion_rate`
- `unique_buyers_count`
- `repeat_buyers_count`
- `created_at`, `updated_at`

### `analytics_provider_daily_metrics`
- `date`, `payment_provider` (unique)
- `orders_created_count`, `orders_paid_count`
- `revenue_rub`, `cost_rub`, `profit_rub`, `avg_check_rub`
- `paid_conversion_rate`
- `created_at`, `updated_at`

### `analytics_product_daily_metrics`
- `date`, `product_type` (unique; `stars|gift`)
- `orders_paid_count`
- `revenue_rub`, `cost_rub`, `profit_rub`, `avg_check_rub`
- `created_at`, `updated_at`

### `analytics_referral_daily_metrics`
- `date` (unique)
- `new_referred_users_count`
- `referred_buyers_count`
- `referred_orders_paid_count`
- `referred_revenue_rub`
- `referral_bonus_cost_rub`
- `referral_profit_rub`
- `created_at`, `updated_at`

### `analytics_cohort_weekly_metrics`
- `cohort_week`, `age_week` (unique)
- `users_count`
- `repeat_buyers_count`
- `retention_rate`
- `period_revenue_rub`
- `cumulative_revenue_rub`
- `created_at`, `updated_at`

### `analytics_job_runs`
- `job_name`
- `range_start`, `range_end`
- `status`
- `rows_written`
- `error_text`
- `started_at`, `finished_at`

## 7. Формулы и допущения
- `revenue_rub = SUM(orders.amount_rub)` по paid-заказам.
- `cost_rub = SUM(COALESCE(orders.cost_rub, 0))`.
- `profit_rub = SUM(COALESCE(orders.profit_rub, amount_rub - cost_rub))` на первом шаге допускается `amount_rub - COALESCE(cost_rub,0)`.
- `avg_check_rub = revenue_rub / orders_paid_count`.
- `pay_conversion_rate = orders_paid_count / orders_created_count`.
- `repeat_buyers_count`: users с `paid_orders_count >= 2` в окне.

Если `cost_rub/profit_rub` неполны в historical данных, фиксируем в README метрику как `gross_profit_estimate`.

## 8. Jobs и расписание
### Jobs
- `DailyMetricsBackfillJob(from_date, to_date)`
- `ReferralMetricsBackfillJob(from_date, to_date)`
- `CohortMetricsBackfillJob(from_week, to_week)`
- `IncrementalRefreshJob`
- `DataQualityCheckJob`

### Rolling recomputation
- каждые 15 минут: сегодня;
- каждый час: последние 3 дня;
- ежедневно: последние 30 дней;
- manual full backfill: rake task.

Все джобы идемпотентны: `UPSERT` по unique-ключам.

## 9. API (read-only, internal)
- `GET /health`
- `GET /metrics/summary?from=...&to=...`
- `GET /metrics/daily?from=...&to=...`
- `GET /metrics/providers?from=...&to=...`
- `GET /metrics/products?from=...&to=...`
- `GET /metrics/referrals?from=...&to=...`
- `GET /metrics/cohorts?from_cohort_week=...&to_cohort_week=...`

## 10. Нефункциональные требования
- Сервис закрыт во внутренней сети + internal token.
- Подключение к core-таблицам только read-only.
- Write-доступ только к `analytics_*`.
- Пересчёт 30 дней: до 2 минут на dev/staging-объёмах.
- Structured logs + `analytics_job_runs`.

## 11. Этапы внедрения
### Этап 1 (Foundation)
- Rails API app, Sidekiq, Redis, Postgres.
- Миграции `analytics_daily_metrics` + `analytics_job_runs`.
- `GET /health`.
- 1 backfill task (daily revenue/orders).

### Этап 2 (Core Analytics)
- daily/provider/product агрегаты.
- `/metrics/summary|daily|providers|products`.

### Этап 3 (Advanced MVP)
- referral + cohorts.
- data quality checks.
- `/metrics/referrals|cohorts`.

## 12. Критерии приёмки MVP
- Поднимается через Docker локально.
- Backfill 30 дней выполняется без ошибок.
- API отдаёт данные по daily/provider/product/referral/cohort.
- Повторный backfill не создаёт дублей.
- Есть README со схемой и запуском.
- Есть тесты на ключевые агрегаторы и upsert-идемпотентность.

## 13. Что нужно от данных для старта
Для реальной валидации метрик нужен локальный дамп БД (или anonymized subset):
- `orders`
- `payment_transactions`
- `users`
- `promo_codes`, `promo_redemptions`
- `referral_earnings`
- `bonus_grants`
- (опционально) `app_events`

Без этого можно начать каркас сервиса и SQL-агрегаторы, но числовую сверку и quality-check полноценно не закрыть.
