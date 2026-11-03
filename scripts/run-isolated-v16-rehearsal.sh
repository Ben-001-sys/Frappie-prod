#!/usr/bin/env bash
# One-way disposable v15 backup -> Frappe v16 rehearsal.
# REQUIREMENT: A dedicated, otherwise unused x86_64 Docker VM (not staging).
# No inbound published ports, no live NFS mounts and no outbound Docker network.
# On error, preserved isolated containers/volumes allow diagnosis.
set -euo pipefail
umask 077

if (( EUID != 0 )); then
  echo "Run as root on a dedicated disposable test VM." >&2
  exit 2
fi
if (( $# != 1 )); then
  echo "Usage: $0 /root/frappe-v16-rehearsal-backup-20261103" >&2
  exit 2
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Expected x86_64 test host; no emulation is configured." >&2
  exit 1
fi
HOSTNAME="$(hostname)"
case "$HOSTNAME" in
  frappe-stg-app|frappe-stg-worker|d2-4-2026-11-02-12-06)
    echo "REFUSING: this is a known staging host." >&2; exit 1 ;;
esac
if mountpoint -q /mnt/frappe-sites || findmnt -rn -t nfs,nfs4 | grep -Eq 'frappe-site-data|frappe-sites'; then
  echo "REFUSING: a Frappe NFS mount exists on this host." >&2
  exit 1
fi
if docker ps --format '{{.Names}}' | grep -Eq 'frappesuiteproductiontest|frappe.*-backend|frappe.*-mariadb'; then
  echo "REFUSING: operational Frappe containers found on this host." >&2
  exit 1
fi
command -v docker >/dev/null
command -v openssl >/dev/null
command -v sha256sum >/dev/null
command -v python3 >/dev/null

BACKUP_DIR="$(realpath -e "$1")"
STEM="20261103_113434-frappe-suite-prod_benuel_dedyn_io"
(
  cd "$BACKUP_DIR"
  sha256sum --check SHA256SUMS
  gzip -t "$STEM-database.sql.gz"
  tar -tf "$STEM-files.tar" >/dev/null
  tar -tf "$STEM-private-files.tar" >/dev/null
  python3 -m json.tool "$STEM-site_config_backup.json" >/dev/null
)
# This is a one-use name. To try again, use a fresh isolated VM.
PREFIX="frappe-v16-realdata-rehearsal"
NETWORK="$PREFIX-net"
SITES_VOLUME="$PREFIX-sites"
DB_VOLUME="$PREFIX-dbdata"
DB_NAME="$PREFIX-db"
REDIS_NAME="$PREFIX-redis"
IMAGE="ghcr.io/ben-001-sys/frappie-suite-v16-candidate@sha256:49a29105cfe6d99101e37ec92009d7510cddc31ef60ff4bf2daca9cde59d5383"
SITE="rehearsal-v16.local"
for name in "$DB_NAME" "$REDIS_NAME"; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    echo "Refusing to reuse an existing test container: $name" >&2; exit 1
  fi
done
if docker network inspect "$NETWORK" >/dev/null 2>&1 ||
   docker volume inspect "$SITES_VOLUME" >/dev/null 2>&1 ||
   docker volume inspect "$DB_VOLUME" >/dev/null 2>&1; then
  echo "Refusing to reuse existing rehearsal network or volumes." >&2
  exit 1
fi

# Pull before creating the outbound-blocked network.
docker pull "$IMAGE"
docker pull mariadb:11.8
docker pull redis:7.4-alpine

DB_ROOT_PASSWORD="$(openssl rand -hex 24)"
ADMIN_PASSWORD="$(openssl rand -hex 24)"
export DB_ROOT_PASSWORD ADMIN_PASSWORD STEM SITE
docker network create --internal --driver bridge "$NETWORK" >/dev/null
docker volume create "$SITES_VOLUME" >/dev/null
docker volume create "$DB_VOLUME" >/dev/null

docker run -d \
  --name "$DB_NAME" --network "$NETWORK" --network-alias db \
  -v "$DB_VOLUME:/var/lib/mysql" \
  -e MARIADB_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
  -e MARIADB_ROOT_HOST='%' \
  mariadb:11.8 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --skip-character-set-client-handshake >/dev/null

docker run -d \
  --name "$REDIS_NAME" --network "$NETWORK" --network-alias redis \
  redis:7.4-alpine redis-server --appendonly no >/dev/null

ready=0
for attempt in $(seq 1 120); do
  if docker exec "$DB_NAME" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 &&
     [[ "$(docker exec "$REDIS_NAME" redis-cli ping)" == "PONG" ]]; then
    ready=1
    break
  fi
  sleep 2
done
if (( ready != 1 )); then
  echo "Isolated DB or Redis is not ready. No live infrastructure was touched." >&2
  exit 1
fi

echo "=== ISOLATED RESTORE AND MAJOR-VERSION MIGRATION ==="
echo "No host ports published. No mounted production NFS. Internal-only container network."
docker run --rm --network "$NETWORK" \
  --name "$PREFIX-bench" \
  --volume "$SITES_VOLUME:/home/frappe/frappe-bench/sites" \
  --volume "$BACKUP_DIR:/rehearsal-backup:ro" \
  --env DB_ROOT_PASSWORD --env ADMIN_PASSWORD --env STEM --env SITE \
  --entrypoint bash "$IMAGE" -ec '
    set -euo pipefail
    umask 077
    cd /home/frappe/frappe-bench
    printf "%s\n" frappe erpnext hrms crm telephony helpdesk payments lms raven offsite_backups > sites/apps.txt
    printf "{}\n" > sites/common_site_config.json
    bench set-config -g db_host db
    bench set-config -gp db_port 3306
    bench set-config -g redis_cache redis://redis:6379
    bench set-config -g redis_queue redis://redis:6379
    bench set-config -g redis_socketio redis://redis:6379
    bench set-config -gp socketio_port 9000

    bench new-site "$SITE" \
      --db-type mariadb \
      --db-root-username root \
      --db-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --mariadb-user-host-login-scope="%"

    # Preserve ONLY the encryption key, not the original DB hostname/password.
    python - "$SITE" "$STEM" <<PY
import json
import os
import sys
from pathlib import Path
site, stem = sys.argv[1:]
source = Path("/rehearsal-backup") / (stem + "-site_config_backup.json")
target = Path("sites") / site / "site_config.json"
old = json.loads(source.read_text(encoding="utf-8"))
config = json.loads(target.read_text(encoding="utf-8"))
key = old.get("encryption_key")
if not key:
    raise RuntimeError("Missing v15 encryption key; abort")
config["encryption_key"] = key
config["maintenance_mode"] = 1
config["pause_scheduler"] = 1
config["host_name"] = "http://rehearsal-v16.local"
with target.open("w", encoding="utf-8") as fp:
    os.chmod(target, 0o600)
    json.dump(config, fp, indent=2)
    fp.write("\n")
print("Copied encryption key into isolated site; secrets not displayed")
PY

    echo "=== RESTORE VERIFIED v15 SQL + PUBLIC + PRIVATE FILES ==="
    # --force is restricted to the freshly created disposable rehearsal site.
    bench --site "$SITE" restore \
      "/rehearsal-backup/$STEM-database.sql.gz" \
      --with-public-files "/rehearsal-backup/$STEM-files.tar" \
      --with-private-files "/rehearsal-backup/$STEM-private-files.tar" \
      --db-root-username root \
      --db-root-password "$DB_ROOT_PASSWORD" \
      --force

    echo "=== MIGRATE RESTORED v15 DATABASE TO v16 ==="
    bench --site "$SITE" migrate

    echo "=== INSTALL THE ADDITIONAL v16 OFFSITE BACKUPS APP ==="
    bench --site "$SITE" install-app offsite_backups

    echo "=== VERIFY FINAL SCHEMA AND APP REGISTRY ==="
    bench --site "$SITE" migrate
    bench --site "$SITE" list-apps
    bench --site "$SITE" execute frappe.db.sql \
      --args "[\"SELECT COUNT(*) FROM tabUser\"]"
    bench --site "$SITE" execute frappe.db.sql \
      --args "[\"SELECT DATABASE(), VERSION()\"]"
    echo "REHEARSAL COMMAND SEQUENCE COMPLETED"
  '

echo "=== Rehearsal completed; test resources intentionally retained ==="
echo "Network: $NETWORK (internal only)"
echo "Database container: $DB_NAME"
echo "Redis container: $REDIS_NAME"
echo "Database volume: $DB_VOLUME"
echo "Sites volume: $SITES_VOLUME"
echo "No services were exposed to the internet."
echo "Review logs and business data before deleting these disposable resources."
