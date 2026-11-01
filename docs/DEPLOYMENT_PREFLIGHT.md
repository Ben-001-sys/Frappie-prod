# Staging deployment readiness checklist

The images in [IMAGES.md](IMAGES.md) are **build-and-pull verified**, not yet declared operationally compatible until both Bench smoke installs pass.

## Planned Dokploy remote hosts

| Host | Dokploy Compose resource | Services |
|---|---|---|
| Database | `compose/database/compose.yml` | MariaDB |
| Worker | `compose/workers/compose.yml` | Redis cache/queue and worker profiles |
| Application | `compose/application/compose.yml` | Configurator, backend, websocket, frontend |
| Insights | `compose/insights/compose.yml` | Separate Frappe Insights app and DB |
| Management | Dokploy installation | Controls independent remote hosts over SSH |

There is **no shared Docker bridge network across hosts**. Reserve stable private addresses or private DNS. Only publish Frappe and Insights frontends through HTTPS. Firewall database and Redis to required private hosts only.

## Do not deploy before verifying

1. Confirm the test Frappe version and application revisions passed the Bench installation smoke test.
2. Verify a supported OVHcloud managed NFS service in the actual region; mount *the same* NFS export at `/mnt/frappe-sites` on the application and worker VMs.
3. On BOTH hosts, run `bash scripts/check-nfs.sh /mnt/frappe-sites`. Verify cross-host visibility with a uniquely named test file. NFS must mount before Frappe containers can run. Stop on missing mount; do not write to a local fallback directory.
4. Confirm consistent UID/GID and writable permissions for the container user (normally UID 1000); test file creation, renaming, deleting and locking from both hosts. Protect NFS private access.
5. Verify `docker compose version`, private DNS, firewalls and installed disk capacity on each VM.
6. Create MariaDB and Redis credentials outside Git. MariaDB admin is local-only; configure a time-limited, restricted provisioning account for initial site creation. Place Redis ACL files at the worker host path chosen in Dokploy.
7. Put the **identical pinned suite digest** from [IMAGES.md](IMAGES.md) in both application and worker Compose environments. Use the independent Insights digest for Insights. If the GHCR package is private, configure registry authentication in Dokploy.
8. Start MariaDB and both Redis services, then deploy the application configuration and web services. Only one designated backend site-admin process should run `bench new-site` and `bench install-app`.
9. After site creation and migration, set `COMPOSE_PROFILES=site-ready` for worker Compose. Run background-job, scheduler, email, realtime, file-upload and ERPNext UI checks.
10. Initialize Insights on its independent site, enable its worker profile and connect approved datasets using a restricted read-only DB identity. Do **not** mount the operational `sites` NFS onto Insights.
11. Configure snapshots, independent MariaDB backups, binlog archival, NFS off-site backup, Insights backup and Dokploy control-plane backup. Test restore in isolation.
12. Verify DNS and TLS, server restart behavior, NFS outage failure modes, and rollback using matching image/database recovery points.

## Private network endpoints (examples, replace with actual addresses)

| From | To | Port |
|---|---|---|
| Application and Worker | MariaDB private address | TCP 3306 |
| Application | Worker Redis cache | TCP 6379 |
| Application | Worker Redis queue | TCP 6380 |
| Application and Worker | Managed NFS | TCP 2049 (subject to NFS service requirements) |
| Dokploy management | Remote servers | SSH, restricted to management address |
| Internet | Frappe and Insights proxy | HTTPS 443 only |

The Dokploy server does **not** give application containers a shared cross-host network. The remote servers must be able to reach one another independently over private networking.

## Acceptance gates

- Both Docker images built and pulled using immutable digests.
- Both smoke-install jobs successfully created temporary sites, installed every expected app and migrated their DBs.
- One real staging site supports concurrent app/worker operation against MariaDB and shared NFS.
- Files and site configuration persist after container re-creation.
- No worker jobs begin before site initialization.
- Backup and restore demonstrated, including encryption-key recovery.
- Sensitive DocTypes are not exposed to Insights through unrestricted reporting.
- Signed-off deployment runbook and documented maintenance/rollback plan.

**The build pipeline does not perform production deployment.** This checklist must be completed for the real infrastructure before declaring the environment production-ready.
