#!/usr/bin/env bash
# Exports ONLY an existing, verified v15 backup set from the live staging NFS.
# Does not write to, freeze, alter, or dump the running database/site.
set -euo pipefail
umask 077

if (( EUID != 0 )); then
  echo "Run on frappe-stg-app as root (read-only against NFS)." >&2
  exit 2
fi
SITE="frappe-suite-prod.benuel.dedyn.io"
STEM="20261103_113434-frappe-suite-prod_benuel_dedyn_io"
NFS_ROOT="/mnt/frappe-sites/frappe-site-data"
BACKUPS="$NFS_ROOT/$SITE/private/backups"
OUT="/root/frappe-v16-rehearsal-backup-20261103"
ARCHIVE="$OUT.tar.gz"

fstype="$(findmnt -n -o FSTYPE -T "$BACKUPS" 2>/dev/null || true)"
case "$fstype" in
  nfs|nfs4) ;;
  *) echo "Refusing: the source is not verified as the staging NFS mount." >&2; exit 1 ;;
esac
if [[ -e "$OUT" || -e "$ARCHIVE" ]]; then
  echo "Refusing to overwrite a prior export: $OUT or $ARCHIVE" >&2
  exit 1
fi

for suffix in database.sql.gz files.tar private-files.tar site_config_backup.json; do
  source_file="$BACKUPS/$STEM-$suffix"
  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    echo "Missing or symlinked backup: $suffix" >&2
    exit 1
  fi
done
gzip -t "$BACKUPS/$STEM-database.sql.gz"
tar -tf "$BACKUPS/$STEM-files.tar" >/dev/null
tar -tf "$BACKUPS/$STEM-private-files.tar" >/dev/null
python3 -m json.tool "$BACKUPS/$STEM-site_config_backup.json" >/dev/null

install -d -m 0700 "$OUT"
for suffix in database.sql.gz files.tar private-files.tar site_config_backup.json; do
  cp -- "$BACKUPS/$STEM-$suffix" "$OUT/$STEM-$suffix"
  chmod 0600 "$OUT/$STEM-$suffix"
done
(
  cd "$OUT"
  sha256sum "$STEM"-* > SHA256SUMS
)
chmod 0600 "$OUT/SHA256SUMS"
tar -C "$(dirname "$OUT")" -czf "$ARCHIVE" "$(basename "$OUT")"
chmod 0600 "$ARCHIVE"
(
  cd "$OUT"
  sha256sum --check SHA256SUMS
)
echo "Source: pre-existing staging backup $STEM"
echo "Created restricted local export: $ARCHIVE"
echo "Archive is sensitive: includes business data and the encryption key."
echo "Transfer only over SSH to an isolated test VM; never commit to GitHub."
echo "No Docker containers, MariaDB volumes, or NFS source files were modified."
