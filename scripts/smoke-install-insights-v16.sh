#!/usr/bin/env bash
# Disposable Frappe 16 + Insights v3 test. Does not access staging data.
set -euo pipefail

: "${TEST_IMAGE:?Missing tested-image reference}"
: "${TEST_DB_PASSWORD:?Missing disposable database password}"
: "${TEST_ADMIN_PASSWORD:?Missing disposable Administrator password}"

SITE="${SMOKE_SITE:-insights-v16-smoke.local}"
export SITE  # docker run -e SITE requires an exported variable
PREFIX="insights-v16-smoke-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$$"
NETWORK="${PREFIX}-net"
DB="${PREFIX}-db"
REDIS="${PREFIX}-redis"
VOLUME="${PREFIX}-sites"

cleanup() {
  result=$?
  trap - EXIT
  set +e
  if (( result != 0 )); then
    docker logs --tail 80 "$DB" >&2
  fi
  docker rm -f "$DB" "$REDIS" >/dev/null 2>&1
  docker network rm "$NETWORK" >/dev/null 2>&1
  docker volume rm "$VOLUME" >/dev/null 2>&1
  exit "$result"
}

for name in "$DB" "$REDIS"; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    echo "ERROR: Existing test container $name; refusing to reuse" >&2
    exit 1
  fi
done
if docker network inspect "$NETWORK" >/dev/null 2>&1 ||
   docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  echo "ERROR: Existing test network or volume; refusing to reuse" >&2
  exit 1
fi

docker network create "$NETWORK" >/dev/null
docker volume create "$VOLUME" >/dev/null
trap cleanup EXIT

docker run -d --name "$DB" --network "$NETWORK" \
  -e MARIADB_ROOT_PASSWORD="$TEST_DB_PASSWORD" \
  -e MARIADB_ROOT_HOST='%' \
  mariadb:11.8 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --skip-character-set-client-handshake >/dev/null

docker run -d --name "$REDIS" --network "$NETWORK" \
  redis:7.4-alpine redis-server --appendonly no >/dev/null

READY=0
for attempt in $(seq 1 120); do
  if docker exec "$DB" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 &&
     docker exec "$REDIS" redis-cli ping | grep -qx PONG; then
    READY=1
    break
  fi
  sleep 2
done
if (( READY != 1 )); then
  echo "ERROR: Disposable MariaDB or Redis not ready" >&2
  exit 1
fi

docker pull "$TEST_IMAGE"

echo '=== Verify Frappe v16 image runtimes and packages ==='
docker run --rm --entrypoint bash "$TEST_IMAGE" -ec '
  set -euo pipefail
  python --version
  node --version
  python -c "import sys; assert sys.version_info >= (3, 14), sys.version"
  node -e "if (Number(process.versions.node.split(\".\")[0]) !== 24) process.exit(1)"
  cd /home/frappe/frappe-bench
  test -d apps/frappe
  test -d apps/insights
  bench version --format plain
'

echo '=== Configure separate, disposable Insights sites volume ==='
docker run --rm --network "$NETWORK" \
  -v "$VOLUME:/home/frappe/frappe-bench/sites" \
  --entrypoint bash "$TEST_IMAGE" -ec '
    set -euo pipefail
    cd /home/frappe/frappe-bench
    printf "%s\n" frappe insights > sites/apps.txt
    if [ ! -e sites/common_site_config.json ]; then
      printf "{}\n" > sites/common_site_config.json
    fi
    bench set-config -g db_host "$1"
    bench set-config -gp db_port 3306
    bench set-config -g redis_cache "redis://$2:6379"
    bench set-config -g redis_queue "redis://$2:6379"
    bench set-config -g redis_socketio "redis://$2:6379"
    bench set-config -gp socketio_port 9000
  ' _ "$DB" "$REDIS"

echo '=== Install stable Insights into a new disposable v16 site ==='
docker run --rm --network "$NETWORK" \
  -v "$VOLUME:/home/frappe/frappe-bench/sites" \
  -e SITE -e TEST_DB_PASSWORD -e TEST_ADMIN_PASSWORD \
  --entrypoint bash "$TEST_IMAGE" -ec '
    set -euo pipefail
    cd /home/frappe/frappe-bench
    bench new-site "$SITE" \
      --db-type mariadb \
      --db-root-username root \
      --db-root-password "$TEST_DB_PASSWORD" \
      --admin-password "$TEST_ADMIN_PASSWORD" \
      --mariadb-user-host-login-scope="%"
    bench --site "$SITE" install-app insights
    bench --site "$SITE" migrate
    bench --site "$SITE" list-apps
    bench --site "$SITE" execute frappe.db.sql \
      --args "[\"SELECT VERSION()\"]"
    echo "SUCCESS: Insights on Frappe v16 and MariaDB 11.8"
  '
