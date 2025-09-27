#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[ERR] Line $LINENO"; exit 1' ERR

# --- Configuration (override via env if needed) ---
PROJECT=${PROJECT:-wordpress}          # Docker Compose project name
SVC_WP=${SVC_WP:-wordpress}            # WordPress service name in docker-compose
SVC_BKP=${SVC_BKP:-backups}            # Backups service name

APP_BACKUP_DIR=${APP_BACKUP_DIR:-/srv/wordpress-application-data/backups}

# We restore the entire /bitnami/wordpress directory
RESTORE_PATH=${RESTORE_PATH:-/bitnami/wordpress/}

# Bitnami expects wp-config.php to be available in /opt/bitnami/wordpress
WP_CONFIG_SRC=${WP_CONFIG_SRC:-/bitnami/wordpress/wp-config.php}
WP_CONFIG_DST=${WP_CONFIG_DST:-/opt/bitnami/wordpress/wp-config.php}

# --- Helper: find container by docker-compose labels ---
find_by_labels () {
  local project="$1" service="$2"
  docker ps -aq \
    --filter "label=com.docker.compose.project=${project}" \
    --filter "label=com.docker.compose.service=${service}"
}

# --- Resolve container IDs ---
CID_WP=$(find_by_labels "$PROJECT" "$SVC_WP" || true)
CID_BKP=$(find_by_labels "$PROJECT" "$SVC_BKP" || true)

[ -n "$CID_WP" ]  || CID_WP=$(docker compose -p "$PROJECT" ps -q --all "$SVC_WP" || true)
[ -n "$CID_BKP" ] || CID_BKP=$(docker compose -p "$PROJECT" ps -q --all "$SVC_BKP" || true)

[ -n "$CID_WP" ]  || CID_WP=$(docker ps -aqf "name=${PROJECT}-${SVC_WP}")
[ -n "$CID_BKP" ] || CID_BKP=$(docker ps -aqf "name=${PROJECT}-${SVC_BKP}")

echo "[DBG] PROJECT=${PROJECT} SVC_WP=${SVC_WP} SVC_BKP=${SVC_BKP}"
echo "[DBG] CID_WP=${CID_WP:-<empty>} CID_BKP=${CID_BKP:-<empty>}"

# --- Guards ---
[ -n "$CID_WP" ]  || { echo "[ERR] WP container not found"; exit 1; }
[ -n "$CID_BKP" ] || { echo "[ERR] Backups container not found"; exit 1; }

# --- Check restore path exists inside backups container ---
docker exec "$CID_BKP" sh -lc "test -d '${RESTORE_PATH}'" \
  || { echo "[ERR] RESTORE_PATH does not exist inside backups container: ${RESTORE_PATH}"; exit 1; }

# --- List available backups ---
echo "--> Available application-data backups (full /bitnami/wordpress):"
docker exec "$CID_BKP" sh -lc "ls -1 ${APP_BACKUP_DIR}/*.tar.gz 2>/dev/null || true"

# --- Prompt user for archive filename ---
read -r -p "--> Enter backup filename (e.g. wordpress-application-data-backup-YYYY-MM-DD_hh-mm.tar.gz): " SELECTED
[ -n "$SELECTED" ] || { echo "[ERR] empty filename"; exit 1; }

# --- Verify backup file exists ---
docker exec "$CID_BKP" sh -lc "test -f '${APP_BACKUP_DIR}/${SELECTED}'" \
  || { echo "[ERR] file not found: ${APP_BACKUP_DIR}/${SELECTED}"; exit 1; }

# --- Ensure RESTORE_PATH is correct ---
case "$RESTORE_PATH" in
  */bitnami/wordpress/ ) : ;;
  * ) echo "[ERR] RESTORE_PATH must be /bitnami/wordpress/: ${RESTORE_PATH}"; exit 1;;
esac

# --- Best-effort maintenance mode (requires wp-cli inside WP container) ---
docker exec "$CID_WP" sh -lc "command -v wp >/dev/null && wp maintenance-mode activate || true" || true

# --- Stop WP container before restore ---
docker compose -p "$PROJECT" stop "$SVC_WP" || true

# --- Perform restore inside backups container ---
docker exec "$CID_BKP" sh -lc "
  set -euo noglob
  # Safety checks
  test -d '${RESTORE_PATH}' && [ '${RESTORE_PATH}' != '/' ] && [ -n '${RESTORE_PATH}' ]
  rm -rf '${RESTORE_PATH%/}'/*

  # Archive contains bitnami/wordpress/... -> extract to /
  tar -zxpf '${APP_BACKUP_DIR}/${SELECTED}' -C /

  # Ensure no stray wp-config.php inside wp-content (defense-in-depth)
  rm -f '${RESTORE_PATH}/wp-content/wp-config.php' 2>/dev/null || true
"

# --- Fix permissions (match Bitnami expectations) ---
# wp-content should be owned by daemon:daemon, but wp-config.php must be root:root 440
docker exec "$CID_BKP" sh -lc "
  if [ -d '${RESTORE_PATH%/}/wp-content' ]; then
    chown -R daemon:daemon '${RESTORE_PATH%/}/wp-content'
  fi
  if [ -f '${WP_CONFIG_SRC}' ]; then
    chown root:root '${WP_CONFIG_SRC}'
    chmod 440 '${WP_CONFIG_SRC}'
  fi
"

# --- Start WP container again ---
docker compose -p "$PROJECT" start "$SVC_WP" || true

# --- Ensure wp-config.php symlink is in place ---
echo "--> Ensuring wp-config symlink inside WP container..."
ATTEMPTS=30
SLEEP_SECS=2
for i in $(seq 1 $ATTEMPTS); do
  if docker exec "$CID_WP" sh -lc "[ -f '${WP_CONFIG_SRC}' ] && ln -sf '${WP_CONFIG_SRC}' '${WP_CONFIG_DST}' && ls -l '${WP_CONFIG_DST}'" >/dev/null 2>&1; then
    echo "--> Symlink OK: ${WP_CONFIG_DST} -> ${WP_CONFIG_SRC}"
    break
  fi
  echo "[DBG] WP not ready yet, retry ${i}/${ATTEMPTS}..."
  sleep "$SLEEP_SECS"
  docker compose -p "$PROJECT" start "$SVC_WP" >/dev/null 2>&1 || true
done

# --- Disable maintenance mode (best effort) ---
docker exec "$CID_WP" sh -lc "command -v wp >/dev/null && wp maintenance-mode deactivate || true" || true

# --- Final checks ---
docker exec "$CID_WP" sh -lc "
  echo '--> Post-checks:'
  ls -ld /bitnami/wordpress /bitnami/wordpress/wp-content || true
  [ -e '${WP_CONFIG_SRC}' ] && stat -c 'OK: %U:%G %a ${WP_CONFIG_SRC}' '${WP_CONFIG_SRC}' || echo 'WARN: wp-config.php missing at ${WP_CONFIG_SRC}'
  [ -e '${WP_CONFIG_DST}' ] && echo 'OK: wp-config.php link exists at ${WP_CONFIG_DST}' || echo 'WARN: wp-config.php link missing at ${WP_CONFIG_DST}'
" || true

echo "--> Application data restore (full /bitnami/wordpress) completed successfully."
