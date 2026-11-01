#!/usr/bin/env bash
# Read-only staging TCP network check; no authentication or configuration changes.
set -euo pipefail
role="${1:-}"
check() {
  local label="$1" host="$2" port="$3"
  if timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
    printf 'PASS %s: %s:%s\n' "$label" "$host" "$port"
  else
    printf 'FAIL %s: %s:%s\n' "$label" "$host" "$port" >&2
    return 1
  fi
}
case "$role" in
  application)
    : "${DB_HOST:?Set private staging DB host}"
    : "${REDIS_HOST:?Set private staging Redis host}"
    check MariaDB "$DB_HOST" 3306
    check Redis-cache "$REDIS_HOST" 6379
    check Redis-queue "$REDIS_HOST" 6380
    ;;
  worker)
    : "${DB_HOST:?Set private staging DB host}"
    check MariaDB "$DB_HOST" 3306
    ;;
  *) echo 'Usage: check-staging-connectivity.sh application|worker' >&2; exit 2 ;;
esac
echo 'TCP reachability only; credentials, ACLs and full application health remain untested.'
