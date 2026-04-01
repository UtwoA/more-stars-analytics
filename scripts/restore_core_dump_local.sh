#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-dump-file>"
  exit 1
fi

DUMP_FILE="$1"
PG_CONTAINER="${PG_CONTAINER:-more-stars-analytics-db-1}"
POSTGRES_USER="${POSTGRES_USER:-analytics}"
POSTGRES_DB="${POSTGRES_DB:-more_stars}"

if [[ ! -f "${DUMP_FILE}" ]]; then
  echo "[restore] dump file not found: ${DUMP_FILE}"
  exit 1
fi

echo "[restore] target container=${PG_CONTAINER} db=${POSTGRES_DB} user=${POSTGRES_USER}"

cat "${DUMP_FILE}" | docker exec -i "${PG_CONTAINER}" pg_restore \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges

echo "[restore] done"

