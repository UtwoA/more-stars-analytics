# more-stars-analytics: структура проекта и назначение каждого файла

Этот документ объясняет, что делает каждый файл в текущем MVP-каркасе.

## Как читать структуру
- `app/` — бизнес-логика приложения (контроллеры, модели, джобы, сервисы).
- `config/` — конфигурация Rails, роутов, БД, Sidekiq и окружений.
- `db/migrate/` — миграции структуры базы.
- `lib/tasks/` — кастомные rake-команды.
- `scripts/` — shell-утилиты для операционных задач (дамп/restore).
- `spec/` — тесты.
- root-файлы — запуск, сборка, зависимости, документация.

## Файлы в корне

### `.env`
- Локальные переменные окружения (секреты/URL).
- Не коммитится.
- Обычно содержит `DATABASE_URL`, `REDIS_URL`, `RAILS_ENV`.

### `.env.example`
- Пример переменных окружения без секретов.
- Используется как шаблон для создания `.env`.

### `.gitignore`
- Определяет, какие файлы не добавлять в git.
- Сейчас исключает временные файлы Rails, `.env`, дампы `dumps/*.dump`.

### `.rspec`
- Настройки запуска RSpec (формат вывода, подключение `spec_helper`).

### `Gemfile`
- Список Ruby-гемов (зависимостей проекта).
- Важные для MVP: `rails`, `pg`, `sidekiq`, `sidekiq-cron`, `redis`, `rspec-rails`.

### `Dockerfile`
- Образ приложения (`app` и `sidekiq`) на `ruby:3.3.1`.
- Устанавливает зависимости через `bundle install`.
- Стартует web через Puma.

### `docker-compose.yml`
- Локальный стек разработки:
- `db` (Postgres), `redis`, `app`, `sidekiq`.
- Используется для локального автономного запуска.

### `docker-compose.server.yml`
- Серверный режим запуска analytics рядом с уже существующим `more-stars`.
- Использует внешнюю сеть `more-stars-shared`.
- Не поднимает свой Postgres, подключается к уже существующему через `DATABASE_URL`.

### `Rakefile`
- Входная точка rake-задач Rails.
- Подгружает окружение приложения.

### `config.ru`
- Rack entrypoint для web-приложения Rails.

### `README.md`
- Основная инструкция по запуску и эксплуатации.
- Включает шаги локального старта, server-режим и инструкции по дампам.

### `more-stars-analytics-mvp.md`
- Бизнес-ТЗ на MVP (что именно строим).
- Это продуктовый контракт и scope, а не исполняемый код.

## `bin/`

### `bin/rails`
- Запуск Rails-команд (`rails db:migrate`, `rails routes`, и т.д.).

### `bin/rake`
- Запуск rake-задач (`rake analytics:backfill_daily ...`).

## `config/`

### `config/boot.rb`
- Базовая загрузка Bundler + Bootsnap.

### `config/application.rb`
- Главная конфигурация Rails-приложения.
- `api_only = true` (без серверного HTML).
- `active_job.queue_adapter = :sidekiq`.
- Таймзона по умолчанию `Europe/Moscow`.

### `config/environment.rb`
- Инициализирует Rails-приложение.

### `config/database.yml`
- Конфиг подключения к PostgreSQL через `DATABASE_URL`.
- Отдельный блок для `test`.

### `config/routes.rb`
- Маршруты API:
- `GET /health`
- `GET /dashboard`
- `GET /dashboard/revenue`
- `GET /dashboard/users`
- `GET /dashboard/ops`
- `GET /metrics/daily`
- `GET /metrics/summary`
- `GET /metrics/providers`
- `GET /metrics/products`
- `GET /metrics/referrals`
- `GET /metrics/promos`
- `GET /metrics/cohorts`
- `GET /ops/jobs`
- `GET /ops/data-quality`
- `POST /ops/backfill`
- `POST /ops/data-quality/run`
- `GET /exports/metrics`

### `config/puma.rb`
- Конфигурация Puma (web-сервер Rails).

### `config/sidekiq.yml`
- Конфигурация Sidekiq:
- очереди (`default`, `metrics`);
- cron-расписание для `IncrementalRefreshJob`.

### `config/schedule.yml`
- Человекочитаемое описание cron-плана джобов (документирующий файл).

### `config/order_statuses.yml`
- Конфиг маппинга статусов заказа:
- `paid`, `failed`, `created`, `cancelled`.
- Нужен, чтобы не хардкодить статусную семантику по коду.

## `config/environments/`

### `development.rb`
- Поведение в dev-режиме (больше логов, без eager load).

### `test.rb`
- Поведение в test-режиме.

### `production.rb`
- Прод-режим (кэш классов, eager loading, более строгий runtime).

## `config/initializers/`

### `cors.rb`
- Настраивает CORS для API.
- Источники берутся из `CORS_ORIGINS`.

### `order_statuses.rb`
- Загружает `config/order_statuses.yml` в константу `ORDER_STATUSES`.

### `sidekiq.rb`
- Настройка Redis для Sidekiq client/server.
- На сервере подгружает cron-задачи из `config/sidekiq.yml`.

## `app/controllers/`

### `application_controller.rb`
- Базовый контроллер для остальных API-контроллеров.
- Содержит базовую авторизацию по `INTERNAL_API_TOKEN` и helper `parse_date`.

### `health_controller.rb`
- `GET /health`.
- Проверяет доступность Postgres и Redis.
- Возвращает timestamp последнего успешного `DailyMetricsBackfillJob`.

### `metrics/daily_controller.rb`
- `GET /metrics/daily?from=...&to=...`.
- Читает готовые строки из `analytics_daily_metrics`.

### `metrics/summary_controller.rb`
- `GET /metrics/summary?from=...&to=...`.
- Возвращает агрегированный overview по daily-таблице.
- Дополнительно возвращает top provider/product по выручке.

### `metrics/providers_controller.rb`
- `GET /metrics/providers?from=...&to=...`.
- Читает агрегаты из `analytics_provider_daily_metrics`.

### `metrics/products_controller.rb`
- `GET /metrics/products?from=...&to=...`.
- Читает агрегаты из `analytics_product_daily_metrics`.

### `public/panel/index.html`
- Главная русскоязычная страница панели (overview).

### `public/panel/revenue.html`
- Страница выручки/маржи/рефералок/промо.

### `public/panel/users.html`
- Страница пользователей и когорт.

### `public/panel/ops.html`
- Страница Ops и Data Quality.

### `public/panel/js/app.js`
- Общая клиентская логика всех страниц панели:
  - fetch JSON API
  - рендер инфографики
  - запуск operational действий
  - поддержка `X-Internal-Token`

### `public/panel/css/panel.css`
- Общая дизайн-система и layout панели.

### `metrics/referrals_controller.rb`
- Дневные метрики рефералов.

### `metrics/promos_controller.rb`
- Дневные метрики промокодов.

### `metrics/cohorts_controller.rb`
- Недельные cohort-метрики по age-week.

### `ops/jobs_controller.rb`
- Операционный журнал фоновых задач.

### `ops/data_quality_controller.rb`
- Просмотр проблем качества данных + ручной запуск проверки.

### `ops/backfill_controller.rb`
- Ручной запуск backfill (`daily` или `full_suite`).

### `exports/metrics_controller.rb`
- CSV-экспорт агрегатов (`daily/providers/products/referrals/promos/cohorts`).

## `app/models/`

### `application_record.rb`
- Базовый класс ActiveRecord для всех моделей.

### `analytics_daily_metric.rb`
- Модель таблицы `analytics_daily_metrics`.

### `analytics_job_run.rb`
- Модель таблицы `analytics_job_runs`.

### `analytics_provider_daily_metric.rb`
- Модель таблицы `analytics_provider_daily_metrics`.

### `analytics_product_daily_metric.rb`
- Модель таблицы `analytics_product_daily_metrics`.

### `analytics_referral_daily_metric.rb`
- Модель таблицы `analytics_referral_daily_metrics`.

### `analytics_promo_daily_metric.rb`
- Модель таблицы `analytics_promo_daily_metrics`.

### `analytics_cohort_weekly_metric.rb`
- Модель таблицы `analytics_cohort_weekly_metrics`.

### `analytics_data_quality_issue.rb`
- Модель таблицы `analytics_data_quality_issues`.

## `app/jobs/`

### `application_job.rb`
- Базовый класс для всех фоновых jobs.

### `daily_metrics_backfill_job.rb`
- Запускает пересчет daily-метрик на диапазоне дат.
- Логирует старт/финиш/ошибки в `analytics_job_runs`.
- Сейчас обновляет сразу 3 слоя:
  - daily
  - provider daily
  - product daily
- referral daily
- promo daily

### `incremental_refresh_job.rb`
- Обертка для rolling refresh:
- `today`
- `last_3_days`
- `last_30_days`
- Вызывает `DailyMetricsBackfillJob`.
- На `last_30_days` дополнительно запускает `CohortMetricsBackfillJob`.

### `referral_metrics_backfill_job.rb`
- Отдельный job для пересчета referral/promo агрегатов.

### `cohort_metrics_backfill_job.rb`
- Отдельный job для пересчета cohort weekly метрик.

### `data_quality_check_job.rb`
- Запускает проверку качества данных и пишет результаты в `analytics_data_quality_issues`.

## `app/services/aggregations/`

### `daily_metrics_aggregator.rb`
- Главный SQL-агрегатор MVP v0:
- читает `orders`;
- считает daily-метрики;
- делает idempotent upsert в `analytics_daily_metrics`.
- Включает расчет:
- created/paid/failed counts;
- revenue/cost/profit/avg_check;
- conversion;
- unique/repeat buyers.
- Важно: `orders_created_count` считается как количество созданных заказов в день (по `orders.timestamp`), а не по финальному статусу `created`.

### `provider_metrics_aggregator.rb`
- SQL-агрегация по платежным провайдерам.
- Пишет в `analytics_provider_daily_metrics` через upsert по `(date, payment_provider)`.

### `product_metrics_aggregator.rb`
- SQL-агрегация по типу продукта (`stars/gift/...`).
- Пишет в `analytics_product_daily_metrics` через upsert по `(date, product_type)`.

### `referral_metrics_aggregator.rb`
- SQL-агрегация дневных реферальных метрик.

### `promo_metrics_aggregator.rb`
- SQL-агрегация дневной эффективности промокодов.

### `cohort_metrics_aggregator.rb`
- SQL-агрегация cohort retention/revenue по age-week.

### `data_quality/checker.rb`
- Набор проверок корректности агрегатов:
  - пропуски дат;
  - подозрительные negative значения;
  - рассинхрон paid raw vs aggregate.

### `queries/top_entities_query.rb`
- Query object для top provider/product за период.

### `presenters/summary_presenter.rb`
- Presenter для формирования `summary` JSON.

## `db/migrate/`

### `20260401152000_create_analytics_daily_metrics.rb`
- Создает таблицу `analytics_daily_metrics` + unique index по `date`.

### `20260401152100_create_analytics_job_runs.rb`
- Создает таблицу `analytics_job_runs` для наблюдаемости ETL/jobs.

### `20260401165000_create_analytics_provider_daily_metrics.rb`
- Создает таблицу `analytics_provider_daily_metrics`.
- Unique ключ: `(date, payment_provider)`.

### `20260401165100_create_analytics_product_daily_metrics.rb`
- Создает таблицу `analytics_product_daily_metrics`.
- Unique ключ: `(date, product_type)`.

### `20260401173000_create_analytics_referral_daily_metrics.rb`
- Таблица дневных referral-метрик.

### `20260401173100_create_analytics_promo_daily_metrics.rb`
- Таблица дневных promo-метрик.

### `20260401173200_create_analytics_cohort_weekly_metrics.rb`
- Таблица cohort weekly метрик.

### `20260401173300_create_analytics_data_quality_issues.rb`
- Таблица проблем качества данных.

## `lib/tasks/`

### `backfill.rake`
- Команда:
  - `rake analytics:backfill_daily FROM=YYYY-MM-DD TO=YYYY-MM-DD`
- Нужна для ручного backfill.
- Дополнительно:
  - `rake analytics:backfill_full FROM=YYYY-MM-DD TO=YYYY-MM-DD`

## `scripts/`

### `make_core_dump.sh`
- Снимает dump из контейнера `more-stars-db`.
- Включает только нужные для analytics таблицы.
- `app_events` добавляет только если таблица существует.

### `restore_core_dump_local.sh`
- Восстанавливает dump в локальный Postgres контейнер analytics.

## `dumps/`

### `.gitkeep`
- Технический файл, чтобы папка `dumps/` была в git.
- Сами `.dump` файлы в git не попадают.

## `spec/`

### `spec_helper.rb`
- Базовая настройка RSpec.

### `requests/health_spec.rb`
- Заготовка request-теста для health endpoint.
- Пока placeholder, позже расширим настоящими проверками.

## Что важно новичку в Ruby/Rails
- Контроллеры отвечают за HTTP.
- Модели — за таблицы БД.
- Jobs — фоновые задачи (через Sidekiq).
- Services — бизнес-логика/агрегации (чтобы не раздувать контроллеры и jobs).
- Миграции меняют схему БД.

Если хотите, следующим шагом сделаю второй файл: `docs/request-flow.md` с картой “как один запрос проходит через роут -> контроллер -> модель/сервис -> БД”.
