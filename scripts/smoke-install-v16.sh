#!/usr/bin/env bash
# Isolated, disposable Frappe v16 fresh-install smoke test.
# Never mounts the real staging NFS share or connects to staging MariaDB/Redis.
set -euo pipefail

: "${TEST_IMAGE:?Set the published v16 candidate image}"
: "${TEST_DB_PASSWORD:?Set a disposable MariaDB root password}"
: "${TEST_ADMIN_PASSWORD:?Set a disposable site Administrator password}"

SMOKE_SITE="${SMOKE_SITE:-smoke-v16.local}"
suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$(date +%s)-$$"
prefix="frappe-v16-smoke-${suffix}"
network="${prefix}-network"
db="${prefix}-db"
redis="${prefix}-redis"
volume="${prefix}-sites"
made_network=0
made_volume=0
made_db=0
made_redis=0

cleanup() {
  status=$?
  trap - EXIT
  set +e
  if (( status != 0 )); then
    echo '=== Disposable MariaDB logs (failure only) ===' >&2
    if (( made_db )); then docker logs --tail 100 "$db" >&2; fi
    echo '=== Disposable Redis logs (failure only) ===' >&2
    if (( made_redis )); then docker logs --tail 50 "$redis" >&2; fi
  fi
  if (( made_db )); then docker rm -f "$db" >/dev/null 2>&1; fi
  if (( made_redis )); then docker rm -f "$redis" >/dev/null 2>&1; fi
  if (( made_network )); then docker network rm "$network" >/dev/null 2>&1; fi
  if (( made_volume )); then docker volume rm "$volume" >/dev/null 2>&1; fi
  exit "$status"
}
trap cleanup EXIT

# Refuse reuse of previously existing resources, even on a shared test runner.
if docker network inspect "$network" >/dev/null 2>&1 ||
   docker volume inspect "$volume" >/dev/null 2>&1 ||
   docker container inspect "$db" >/dev/null 2>&1 ||
   docker container inspect "$redis" >/dev/null 2>&1; then
  echo "ERROR: Disposable resource-name collision. Refusing to use existing data." >&2
  exit 1
fi

docker network create "$network" >/dev/null
made_network=1
docker volume create "$volume" >/dev/null
made_volume=1

docker run -d --name "$db" --network "$network" \
  -e MARIADB_ROOT_PASSWORD="$TEST_DB_PASSWORD" \
  -e MARIADB_ROOT_HOST='%' \
  mariadb:11.8 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --skip-character-set-client-handshake >/dev/null
made_db=1

docker run -d --name "$redis" --network "$network" \
  redis:7.4-alpine redis-server --appendonly no >/dev/null
made_redis=1

ready=0
for attempt in $(seq 1 120); do
  if docker exec "$db" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 &&
     docker exec "$redis" redis-cli ping | grep -qx PONG; then
    ready=1
    break
  fi
  sleep 2
done
if (( ready != 1 )); then
  echo 'ERROR: Disposable MariaDB 11.8 or Redis did not become healthy' >&2
  exit 1
fi

docker exec "$db" mariadbd --version
docker pull "$TEST_IMAGE"

echo '=== Verify v16 candidate Python and Node runtimes ==='
docker run --rm --entrypoint bash "$TEST_IMAGE" -ec '
  set -euo pipefail
  python --version
  node --version
  python -c "import sys; assert sys.version_info >= (3, 14), sys.version"
  node -e "if (Number(process.versions.node.split(\".\")[0]) !== 24) process.exit(1)"
'

echo '=== Configure disposable Frappe sites volume ==='
docker run --rm --network "$network" \
  -v "$volume:/home/frappe/frappe-bench/sites" \
  --entrypoint bash "$TEST_IMAGE" -ec '
    set -euo pipefail
    printf "%s\n" frappe erpnext hrms crm telephony helpdesk payments lms raven offsite_backups > sites/apps.txt
    bench set-config -g db_host "$1"
    bench set-config -gp db_port 3306
    bench set-config -g redis_cache "redis://$2:6379"
    bench set-config -g redis_queue "redis://$2:6379"
    bench set-config -g redis_socketio "redis://$2:6379"
    bench set-config -gp socketio_port 9000
  ' _ "$db" "$redis"

echo '=== Create isolated v16 site and install nine candidate applications ==='
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
    bench version --format plain
    echo "SMOKE SUCCESS: Nine v16 candidate apps installed and migrated with MariaDB 11.8"
  '
