#!/usr/bin/env bash
# Ephemeral GitHub Actions integration test; never connects to live infrastructure.
set -euo pipefail
: "${FLAVOR:?suite or insights required}"
: "${TEST_IMAGE:?Immutable image digest required}"
: "${TEST_DB_PASSWORD:?Disposable MariaDB test password required}"
: "${TEST_ADMIN_PASSWORD:?Disposable Frappe admin password required}"
: "${SMOKE_SITE:?Test site name required}"

network="frappe-smoke-${FLAVOR}"
db="smoke-db-${FLAVOR}"
redis="smoke-redis-${FLAVOR}"
volume="frappe-sites-smoke-${FLAVOR}"

docker network create "$network"
docker volume create "$volume"
docker run -d --name "$db" --network "$network" \
  -e MARIADB_ROOT_PASSWORD="$TEST_DB_PASSWORD" \
  -e MARIADB_ROOT_HOST='%' \
  mariadb:10.11 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --skip-character-set-client-handshake
docker run -d --name "$redis" --network "$network" \
  redis:7.4-alpine redis-server --appendonly no

echo "Waiting for disposable MariaDB and Redis to become healthy..."
ready=0
for attempt in $(seq 1 90); do
  if docker exec "$db" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 \
    && docker exec "$redis" redis-cli ping | grep -q PONG; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo "ERROR: Disposable database or Redis never became healthy" >&2
  exit 1
fi

echo "Pulling pinned image: $TEST_IMAGE"
docker pull "$TEST_IMAGE"

echo "Writing shared site configuration..."
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

echo "Creating throwaway site and installing all expected apps..."
docker run --rm --network "$network" \
  -v "$volume:/home/frappe/frappe-bench/sites" \
  -e FLAVOR -e SMOKE_SITE -e TEST_DB_PASSWORD -e TEST_ADMIN_PASSWORD \
  --entrypoint bash "$TEST_IMAGE" -ec '
    set -euo pipefail
    bench new-site "$SMOKE_SITE" \
      --db-type mariadb \
      --db-root-username root \
      --db-root-password "$TEST_DB_PASSWORD" \
      --admin-password "$TEST_ADMIN_PASSWORD" \
      --mariadb-user-host-login-scope="%"
    if [ "$FLAVOR" = "suite" ]; then
      apps=(erpnext hrms crm helpdesk lms raven)
    else
      apps=(insights)
    fi
    for app in "${apps[@]}"; do
      echo "SMOKE INSTALL: $app"
      bench --site "$SMOKE_SITE" install-app "$app"
    done
    bench --site "$SMOKE_SITE" migrate
    bench --site "$SMOKE_SITE" list-apps
    bench --site "$SMOKE_SITE" doctor
    echo "SMOKE SITE SUCCESS: $FLAVOR"
  '

echo "Installed Frappe apps successfully for flavor: $FLAVOR"
