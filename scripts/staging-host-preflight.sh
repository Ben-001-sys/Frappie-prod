#!/usr/bin/env bash
# Read-only host inventory for isolated Frappe staging machines.
# Usage: bash scripts/staging-host-preflight.sh application|worker|database|insights
set -euo pipefail

ROLE="${1:-}"
case "$ROLE" in
  application|worker|database|insights) ;;
  *) echo "Usage: $0 application|worker|database|insights" >&2; exit 2 ;;
esac

printf '\n=== FRAPPE STAGING PREFLIGHT: %s ===\n' "$ROLE"
printf 'Hostname: %s\n' "$(hostname)"
printf 'UTC: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
fi
printf 'Architecture: %s\n' "$(uname -m)"
printf 'vCPU: %s\n' "$(nproc)"
if command -v free >/dev/null 2>&1; then
  free -h | sed -n '1,3p'
fi
printf '\nFilesystem capacity:\n'
df -hP / | tail -n +1
if [ -d /var/lib/docker ]; then df -hP /var/lib/docker | tail -n 1; fi

printf '\nIPv4 interfaces (contains network addresses; redact public addresses before sharing):\n'
if command -v ip >/dev/null 2>&1; then ip -4 -brief address; else echo 'iproute2 missing'; fi

printf '\nDocker status:\n'
if command -v docker >/dev/null 2>&1; then
  docker --version
  if docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
    printf 'Docker daemon accessible: yes\n'
  else
    printf 'Docker daemon accessible: no (permissions or service)\n'
  fi
  if docker compose version >/dev/null 2>&1; then
    docker compose version
  else
    echo 'Compose plugin missing'
  fi
else
  echo 'Docker not installed'
fi

if [ "$ROLE" = application ] || [ "$ROLE" = worker ]; then
  printf '\nNFS operational site storage:\n'
  if mountpoint -q /mnt/frappe-sites; then
    findmnt -T /mnt/frappe-sites -o TARGET,SOURCE,FSTYPE,OPTIONS
    fstype="$(findmnt -n -o FSTYPE -T /mnt/frappe-sites)"
    case "$fstype" in
      nfs|nfs4) echo 'NFS mount present' ;;
      *) echo 'WARNING: mount exists but is not NFS' ;;
    esac
  else
    echo 'NOT READY: /mnt/frappe-sites is not yet an active mount'
  fi
fi
printf '\nNo configuration, Docker containers or files were changed.\n'
