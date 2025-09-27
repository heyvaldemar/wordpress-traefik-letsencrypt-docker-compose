#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[ERR] Line $LINENO"; exit 1' ERR

# --- Configuration ---
PROJECT=${PROJECT:-wordpress}     # Docker Compose project name
SVC_DB=${SVC_DB:-mariadb}        # DB service name in docker-compose
SVC_WP=${SVC_WP:-wordpress}      # WordPress service name
SVC_BKP=${SVC_BKP:-backups}      # Backups service name

DB_BACKUP_DIR=${DB_BACKUP_DIR:-/srv/wordpress-mariadb/backups}

# --- Get container IDs (with fallbacks) ---
CID_DB=$(docker compose -p "$PROJECT" ps -q "$SVC_DB" || true)
CID_WP=$(docker compose -p "$PROJECT" ps -q "$SVC_WP" || true)
CID_BKP=$(docker compose -p "$PROJECT" ps -q "$SVC_BKP" || true)

[ -n "$CID_DB" ]  || CID_DB=$(docker ps -qf "name=${PROJECT}-${SVC_DB}")
[ -n "$CID_WP" ]  || CID_WP=$(docker ps -qf "name=${PROJECT}-${SVC_WP}")
[ -n "$CID_BKP" ] || CID_BKP=$(docker ps -qf "name=${PROJECT}-${SVC_BKP}")

[ -n "$CID_DB" ]  || { echo "[ERR] DB container not found"; exit 1; }
[ -n "$CID_WP" ]  || { echo "[ERR] WP container not found"; exit 1; }
[ -n "$CID_BKP" ] || { echo "[ERR] Backups container not found"; exit 1; }

# --- Get DB credentials from the backup container env ---
DB_NAME=$(docker exec "$CID_BKP" printenv WORDPRESS_DB_NAME)
DB_USER=$(docker exec "$CID_BKP" printenv WORDPRESS_DB_USER)
DB_PASS=$(docker exec "$CID_BKP" printenv WORDPRESS_DB_PASSWORD)

# --- Show available backups ---
echo "--> Available DB backups:"
docker exec "$CID_BKP" sh -lc "ls -1 ${DB_BACKUP_DIR}/*.gz 2>/dev/null || true"

# --- Ask user which backup to restore ---
read -r -p "--> Enter backup filename (e.g. wordpress-mariadb-backup-YYYY-MM-DD_hh-mm.gz): " SELECTED
[ -n "$SELECTED" ] || { echo "[ERR] empty filename"; exit 1; }

# --- Check file exists ---
docker exec "$CID_BKP" sh -lc "test -f '${DB_BACKUP_DIR}/${SELECTED}'" || { echo "[ERR] file not found"; exit 1; }

# --- Put site into maintenance mode (best effort) ---
docker exec "$CID_WP" sh -lc "command -v wp >/dev/null && wp maintenance-mode activate || true" || true

# --- Stop WP service before restore ---
docker compose -p "$PROJECT" stop "$SVC_WP"

# --- Restore database (session-level FK off; no SUPER required) ---
docker exec -e MYSQL_PWD="$DB_PASS" "$CID_BKP" sh -lc "
  mariadb -h $SVC_DB -u $DB_USER -e \"DROP DATABASE IF EXISTS \\\`$DB_NAME\\\`; CREATE DATABASE \\\`$DB_NAME\\\`;\"
  ( echo 'SET FOREIGN_KEY_CHECKS=0;'
    gunzip -c '${DB_BACKUP_DIR}/${SELECTED}'
    echo 'SET FOREIGN_KEY_CHECKS=1;' ) \
  | mariadb -h $SVC_DB -u $DB_USER $DB_NAME --force --max-allowed-packet=256M
"

# --- Start WP again ---
docker compose -p "$PROJECT" start "$SVC_WP"

# --- Disable maintenance mode ---
docker exec "$CID_WP" sh -lc "command -v wp >/dev/null && wp maintenance-mode deactivate || true" || true

echo "--> DB restore completed successfully."
