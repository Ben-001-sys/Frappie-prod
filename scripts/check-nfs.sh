#!/usr/bin/env bash
set -euo pipefail
MOUNT_PATH="${1:-/mnt/frappe-sites}"
if ! mountpoint -q "$MOUNT_PATH"; then
  printf 'ERROR: %s is not a mount point. Refusing to use local disk.\n' "$MOUNT_PATH" >&2
  exit 1
fi
fstype="$(findmnt -n -o FSTYPE --target "$MOUNT_PATH")"
case "$fstype" in
  nfs|nfs4) printf 'NFS active at %s (filesystem: %s)\n' "$MOUNT_PATH" "$fstype" ;;
  *) printf 'ERROR: expected NFS at %s, found: %s\n' "$MOUNT_PATH" "$fstype" >&2; exit 1 ;;
esac
if ! timeout 10s test -r "$MOUNT_PATH"; then
  echo 'ERROR: NFS path not readable' >&2
  exit 1
fi
