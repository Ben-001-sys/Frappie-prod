# Dokploy staging first-run checklist

**Scope:** a new, isolated OVHcloud staging environment. Never reuse or modify the existing live ERPNext site, its database, its NFS files, or its Dokploy Compose resource.

## Preconditions

1. Both image digests are approved for **staging only** in [release/verified-staging.json](../release/verified-staging.json). The images have passed build, pull, Bench installation and migration checks.
2. Establish the actual OVH region, Public Cloud quota, server billing and managed NFS availability **before** creating paid services. The existing Dokploy manager may remain separate from the workload region.
3. Create four independent staging hosts: Application, Worker/Redis, MariaDB and Insights. Use private networking, restrictive firewalls and SSH access from trusted administrators and Dokploy.
4. Create the managed NFS share, allow private App and Worker client addresses, and mount the **same export** to `/mnt/frappe-sites` on both hosts. Verify with `scripts/check-nfs.sh` and a cross-host test file.

## Deployment sequence

**MariaDB VM:** Deploy `compose/database/compose.yml` through a new Dokploy resource with private-only TCP 3306, persistent block storage, and secrets outside Git. Inside its database container, temporarily create a remote provisioning SQL user for the Application VM (the `frappe_setup` user expected by `scripts/init-suite.sh`). It will require sufficient temporary administrative privileges to create the Frappe site DB and its DB account; restrict its SQL host scope and remove it once the site is created.

**Worker VM:** Deploy `compose/workers/compose.yml` initially **without** the `site-ready` profile: start only Redis cache and queue. Protect Redis with separate ACLs, private IP port bindings and secrets stored outside Git. Check connectivity on both hosts:

```bash
DB_HOST=ACTUAL_DB_PRIVATE_IP REDIS_HOST=ACTUAL_REDIS_PRIVATE_IP \
  bash scripts/check-staging-connectivity.sh application

DB_HOST=ACTUAL_DB_PRIVATE_IP \
  bash scripts/check-staging-connectivity.sh worker
```

**Application VM:** Deploy `compose/application/compose.yml` using the exact Suite release digest from `release/verified-staging.json`. Verify its configurator successfully writes `sites/apps.txt` and `common_site_config.json` on NFS. From an **interactive** backend shell, create one *new staging* Frappe site and install apps once in the tested order:

```bash
bench new-site staging-erp.example.com --db-type mariadb \
  --db-host ACTUAL_DB_PRIVATE_IP --db-port 3306 \
  --db-root-username frappe_setup \
  --mariadb-user-host-login-scope='%'

bench --site staging-erp.example.com install-app erpnext
bench --site staging-erp.example.com install-app hrms
bench --site staging-erp.example.com install-app crm
bench --site staging-erp.example.com install-app telephony
bench --site staging-erp.example.com install-app helpdesk
bench --site staging-erp.example.com install-app payments
bench --site staging-erp.example.com install-app lms
bench --site staging-erp.example.com install-app raven
bench --site staging-erp.example.com migrate
bench --site staging-erp.example.com enable-scheduler
bench --site staging-erp.example.com list-apps
```

Bench will prompt for passwords; never commit them. Confirm the site is functional and remove the temporary `frappe_setup` SQL account. MariaDB must remain private-only. The `%` site-user host scope is broad, so apply strict private network restrictions and revisit account scoping if NAT/routing permits narrower settings.

**Worker VM:** Only **after** site installation, enable `COMPOSE_PROFILES=site-ready` and start queue workers and a single scheduler. Ensure Worker and Application use the exact same Suite digest and NFS export.

**Insights VM:** Independently deploy `compose/insights/compose.yml` with the approved Insights image. Create a separate Frappe site, install `insights`, run migration, and start its own workers. Do not share the operational NFS. Use approved **read-only** SQL credentials to connect only the required datasets.

## Acceptance checks

Confirm login, all eight operational packages, background jobs running on the worker host, scheduler, WebSocket, public/private file upload, cross-host NFS read/write, restart persistence, backups, isolated restore, and denial of DB/Redis public access.

Route HTTPS only to frontends on container port 8080. Do not copy a live production site into staging without an explicit sanitized restoration plan.

See also [OVH staging provisioning](OVH_STAGING_PROVISIONING.md) and [deployment preflight](DEPLOYMENT_PREFLIGHT.md). No resources are provisioned merely by committing this document.
