#!/usr/bin/env bash
# One-time Insights initialization; run in the independent Insights backend.
set -euo pipefail
SITE="${SITE:?Set SITE to Insights hostname}"
if [ -f "sites/$SITE/site_config.json" ]; then
  echo "Insights site already exists; refusing to reinitialize" >&2
  exit 1
fi
bench new-site "$SITE" --db-type mariadb --db-host insights-db --db-port 3306 --db-root-username root --mariadb-user-host-login-scope='%'
bench --site "$SITE" install-app insights
bench --site "$SITE" migrate
bench --site "$SITE" enable-scheduler
bench --site "$SITE" list-apps
