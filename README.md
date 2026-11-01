# Frappie-prod

Source repository for CETECH-style Frappe Suite multi-host infrastructure and image builds.

## Images

- `ghcr.io/ben-001-sys/frappie-suite` — Frappe Framework v15, ERPNext, HRMS, CRM, Helpdesk, LMS and Raven. One identical image is reused across application and worker containers.
- `ghcr.io/ben-001-sys/frappie-insights` — separate Frappe v15 / Insights v3 application.
- MariaDB and Redis use official upstream images; they do not require custom image builds.

Image builds are triggered by changes to app manifests or the image workflow and published under commit-SHA tags. Deployment is **manual**, not part of the build pipeline. See [Actions](https://github.com/Ben-001-sys/Frappie-prod/actions) for build status. A successful build does not imply successful app installation.

## Dokploy Compose projects

| Project | Compose file | Remote server |
|---|---|---|
| Database | `compose/database/compose.yml` | MariaDB VM |
| Worker | `compose/workers/compose.yml` | Redis + workers VM |
| Application | `compose/application/compose.yml` | Frappe application VM |
| Insights | `compose/insights/compose.yml` | Separate Insights VM |

The Dokploy management server is an additional control-plane role. Independent remote hosts have no implicit shared Docker network.

## Proof-of-concept deployment order

1. Verify v15 compatibility and inspect the Actions image-build results; record exact manifest digests.
2. Provision private networking, firewalls and NFSv4; mount the **same** live NFS share on application and worker hosts at `/mnt/frappe-sites`. Run `scripts/check-nfs.sh` on both hosts before deployment.
3. Deploy MariaDB (private TCP 3306) and Redis services (worker-private TCP 6379/6380). Configure Redis ACLs and a restricted MariaDB provisioning account.
4. Deploy Frappe application Compose; ensure the shared configurator writes the correct site configuration.
5. From an authorized backend container, run the reviewed `scripts/init-suite.sh` *once* (copy or pipe the script into the container; scripts are not bundled into the image). Install all selected apps in the operational Frappe site.
6. Enable `COMPOSE_PROFILES=site-ready` on workers to start queues and scheduler. Test background job processing and NFS file read/write between hosts.
7. Deploy Insights Compose, initialize its separate site with `scripts/init-insights.sh` and enable its worker profile. Add a read-only database connection for reporting.
8. Configure public HTTPS routes only to each frontend service, port 8080. Verify backups, restores, file uploads, workers, permissions, migrations and app compatibility.

## Build decisions and caveats

- The upstream Docker builder is pinned to commit `61d35da827ebc04d01b64c9e78385597ccebc9d8`.
- App manifests use preliminary mutable branches; production requires pinned, **tested and reproducible** application versions.
- Applications may need install-order or dependency changes after actual image and site testing.
- Do not deploy unverified POC images to production.
- Never manually run `bench update` inside a production container.
- No production infrastructure is altered automatically by this repository.

See `docs/ARCHITECTURE.md`, `docs/SECRETS.md` and `docs/RELEASE.md` for implementation and security guidance.
