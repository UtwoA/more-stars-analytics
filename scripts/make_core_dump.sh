#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-more-stars-db}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-orders_db}"
DUMP_DIR="${DUMP_DIR:-./dumps}"
DATE_TAG="$(date +%F_%H%M%S)"
OUT_FILE="${OUT_FILE:-${DUMP_DIR}/more_stars_core_${DATE_TAG}.dump}"

mkdir -p "${DUMP_DIR}"

TABLE_ARGS=(
  -t public.orders
  -t public.payment_transactions
  -t public.users
  -t public.promo_codes
  -t public.promo_redemptions
  -t public.referral_earnings
  -t public.bonus_grants
)

# app_events optional: добавляем только если таблица существует
if docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc "SELECT to_regclass('public.app_events') IS NOT NULL;" | grep -q "t"; then
  TABLE_ARGS+=(-t public.app_events)
fi

echo "[dump] container=${CONTAINER_NAME} db=${POSTGRES_DB} user=${POSTGRES_USER}"
echo "[dump] output=${OUT_FILE}"

docker exec "${CONTAINER_NAME}" pg_dump \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --format=custom \
  --no-owner \
  --no-privileges \
  "${TABLE_ARGS[@]}" > "${OUT_FILE}"

echo "[dump] done: ${OUT_FILE}"

