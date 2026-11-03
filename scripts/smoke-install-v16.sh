#!/usr/bin/env bash
# Disposable v16 Suite install smoke test. Never touches operational sites or databases.
set -euo pipefail

: "${TEST_IMAGE:?Published candidate image required}"
: "${TEST_DB_PASSWORD:?Disposable MariaDB password required}"
: "${TEST_ADMIN_PASSWORD:?Disposable site administrator password required}"

SMOKE_SITE="${SMOKE_SITE:-smoke-v16.local}"
network="frappe-v16-smoke"
db="frappe-v16-smoke-db"
redis="frappe-v16-smoke-redis"
volume="frappe-v16-smoke-sites"

cleanup() {
  docker rm -f "$db" "$redis" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network"
docker volume create "$volume"

docker run -d --name "$db" --network "$network" \
  -e MARIADB_ROOT_PASSWORD="$TEST_DB_PASSWORD" \
  -e MARIADB_ROOT_HOST='%' \
  mariadb:11.8 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --skip-character-set-client-handshake

docker run -d --name "$redis" --network "$network" \
  redis:7.4-alpine redis-server --appendonly no

ready=0
for attempt in $(seq 1 120); do
  if docker exec "$db" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 \
    && docker exec "$redis" redis-cli ping | grep -q PONG; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "ERROR: Disposable MariaDB 11.8 / Redis did not become healthy" >&2
  exit 1
fi

docker pull "$TEST_IMAGE"

echo 'Configure disposable shared site state'
docker run --rm --network "$network" \
  -v "$volume:/home/frappe/frappe-bench/sites" \
  --entrypoint bash "$TEST_IMAGE" -ec '
    set -euo pipefail
    ls -1 apps > sites/apps.txt
    bench set-config -g db_host "$1"
    bench set-config -gp db_port 3306
    bench set-config -g redis_cache "redis://$2:6379"
    bench set-config -g redis_queue "redis://$2:6379"
    bench set-config -g redis_socketio "redis://$2:6379"
    bench set-config -gp socketio_port 9000
  ' _ "$db" "$redis"

echo 'Create disposable Frappe v16 site; install all nine apps and migrate'
docker run --rm --network "$network" \
  -v "$volume:/home/frappe/frappe-bench/sites" \
  -e SMOKE_SITE -e TEST_DB_PASSWORD -e TEST_ADMIN_PASSWORD \
  --entrypoint bash "$TEST_IMAGE" -ec '
    set -euo pipefail
    bench new-site "$SMOKE_SITE" \
      --db-type mariadb \
      --db-root-username root \
      --db-root-password "$TEST_DB_PASSWORD" \
      --admin-password "$TEST_ADMIN_PASSWORD" \
      --mariadb-user-host-login-scope="%"
    for app in erpnext hrms crm telephony helpdesk payments lms raven offsite_backups; do
      echo "SMOKE INSTALL: $app"
      bench --site "$SMOKE_SITE" install-app "$app"
    done
    bench --site "$SMOKE_SITE" migrate
    bench --site "$SMOKE_SITE" list-apps
    bench --site "$SMOKE_SITE" execute frappe.db.sql \
      --args "[\"SELECT DATABASE(), VERSION()\"]"
    echo "SMOKE SUCCESS: Frappe v16 with nine Suite apps and MariaDB 11.8"
  '
