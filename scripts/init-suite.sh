#!/usr/bin/env bash
# One-time staging initialization; run inside authorized backend container.
set -euo pipefail
SITE="${SITE:?Set SITE to intended Frappe site hostname}"
DB_HOST="${DB_HOST:?Set DB_HOST to private MariaDB address}"
DB_SETUP_USER="${DB_SETUP_USER:-frappe_setup}"
if [ -f "sites/$SITE/site_config.json" ]; then
  echo "Site already exists; refusing to reinitialize: $SITE" >&2
  exit 1
fi
bench new-site "$SITE" --db-type mariadb --db-host "$DB_HOST" --db-port 3306 --db-root-username "$DB_SETUP_USER" --mariadb-user-host-login-scope='%'
for app in erpnext hrms crm telephony helpdesk payments lms raven; do
  echo "Installing app $app into $SITE"
  bench --site "$SITE" install-app "$app"
done
bench --site "$SITE" migrate
bench --site "$SITE" enable-scheduler
bench --site "$SITE" list-apps
