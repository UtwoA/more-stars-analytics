# more-stars-analytics

Отдельный Ruby/Rails сервис аналитики для `more-stars`.

Сервис:
- читает доменные данные из PostgreSQL (`orders/users/...`);
- считает аналитические агрегаты в `analytics_*` таблицы;
- отдает метрики по API;
- имеет встроенную внутреннюю dashboard-панель.

## Стек
- Ruby 3.3.1
- Rails 7.1 (API + static panel)
- PostgreSQL
- Sidekiq + Redis
- Docker / Docker Compose

## Что уже есть
- Дневные метрики: выручка, себестоимость, прибыль, конверсии.
- Разрезы по провайдерам и продуктам.
- Реферальные и промо-метрики.
- Когорты и базовые insights.
- Data quality checks.
- UI-панель:
  - `/dashboard`
  - `/dashboard/revenue`
  - `/dashboard/users`
  - `/dashboard/payments`
  - `/dashboard/ops`

## Авторизация (пароль + Google Authenticator 2FA)
- `GET /login` — страница входа.
- `POST /auth/login` — вход с `{ password, otp_code }`.
- `POST /auth/logout` — выход.
- Все `/dashboard*` и JSON API защищены сессией.
- Опционально можно использовать `INTERNAL_API_TOKEN` для machine-to-machine запросов.

## Быстрый старт (локально)
1. Создать `.env`:
```bash
cp .env.example .env
```

2. Заполнить минимум:
- `DASHBOARD_PASSWORD`
- `DASHBOARD_2FA_SECRET` (после генерации)

3. Поднять контейнеры:
```bash
docker compose up -d --build
```

4. Миграции:
```bash
docker compose run --rm app bundle exec rails db:migrate
```

5. Сгенерировать 2FA secret:
```bash
docker compose run --rm app bundle exec rake auth:generate_2fa_secret
```

6. Добавить secret в `.env` и перезапустить:
```bash
docker compose up -d --build
```

7. Проверить:
- `http://localhost:3001/health`
- `http://localhost:3001/login`

Важно:
- для локальной разработки должен быть `SESSION_COOKIE_SECURE=false`;
- для production под HTTPS — `SESSION_COOKIE_SECURE=true`.

## Восстановление дампа core-БД
Если нужен реальный датасет:
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

После этого пересчитать агрегаты:
```bash
docker compose run --rm app bundle exec rake analytics:backfill_full FROM=2026-01-01 TO=2026-03-31
```

## Основные rake-задачи
- `analytics:backfill_daily FROM=YYYY-MM-DD TO=YYYY-MM-DD`
- `analytics:backfill_full FROM=YYYY-MM-DD TO=YYYY-MM-DD`
- `auth:generate_2fa_secret`

## Важные env-переменные
Смотри полный список в `.env.example`.

Ключевые:
- `DATABASE_URL`
- `REDIS_URL`
- `DASHBOARD_PASSWORD`
- `DASHBOARD_2FA_SECRET`
- `TOTP_ISSUER`
- `SESSION_TTL_HOURS`
- `SESSION_COOKIE_SECURE`
- `GIFT_DEFAULT_COST_RUB` (fallback себестоимость для `gift`, по умолчанию `60`)
- `INTERNAL_API_TOKEN` (опционально)

## GitHub Actions
В репозитории добавлены:
- `CI`: `.github/workflows/ci.yml`
  - bundle install
  - `bundle exec rspec`
- `Deploy`: `.github/workflows/deploy.yml`
  - деплой по SSH на сервер
  - `git pull`, `docker compose -f docker-compose.server.yml up -d --build`
  - `rails db:migrate`

### Secrets для Deploy workflow
Нужно добавить в GitHub Repository Secrets:
- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_SSH_KEY`
- `DEPLOY_PATH` (например `/opt/more-stars/more-stars-analytics`)

## Рекомендованный процесс публикации на GitHub
1. Проверить локально:
```bash
docker compose up -d --build
docker compose run --rm app bundle exec rails db:migrate
docker compose run --rm app bundle exec rspec
```

2. Инициализировать/проверить git-репозиторий и сделать первый коммит.
3. Запушить в GitHub.
4. Включить Actions.
5. Добавить deploy secrets.
6. Запустить `Deploy` вручную через `workflow_dispatch`.
