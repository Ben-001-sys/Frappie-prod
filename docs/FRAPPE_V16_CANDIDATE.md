# CETECH Ghana — Frappe 16 candidate upgrade

Status: **candidate only — not deployed and not approved for production**.

## Scope

Build and smoke-test Frappe Framework 16, ERPNext 16, HRMS 16, and the eight-app operational Suite before replacing the current isolated staging trial. Keep Insights on its separate host and site, using Frappe 16 + Insights `version-3` only after its own CI installation tests pass.

This branch is intentionally isolated from `main`. Never point an existing Dokploy environment at an unverified `sha-` image tag or switch the current `FRAPPE_SUITE_IMAGE` value without recording a passing candidate image digest and a tested rollback.

## Source manifests

- `apps/suite-v16.json`: ERPNext and HRMS `version-16`, CRM `main`, Telephony `develop`, Helpdesk `main`, Payments `version-16`, LMS `version-16`, Raven `main`.
- `apps/insights.json`: Insights `version-3`, whose declared Frappe dependency currently supports versions 15 and 16.
- `apps/suite.json`: retained v15 manifest. Do not change the v15 staging release `release/verified-staging.json` until a v16 candidate has passed installation and regression tests.

The pinned upstream Frappe Docker builder `61d35da827ebc04d01b64c9e78385597ccebc9d8` uses `frappe/build:version-16` and `frappe/base:version-16` when given `FRAPPE_BRANCH=version-16`. Verify the candidate image inside CI: Frappe 16, Python 3.14, Node 24, all app code present, and assets successfully built.

## Required database and infrastructure gates

Frappe's v16 installation documentation targets **MariaDB 11.8**, Python 3.14 and Node 24. The running MariaDB `10.11.19` is the v15 staging database and is **not** an approved v16 database target.

1. **Do not change or downgrade the MariaDB 10.11 image against its existing Docker volume.** No `docker compose down -v`, `bench drop-site`, recursive NFS removal or destructive DB cleanup.
2. Before any v16 site creation, create a **separate MariaDB 11.8 deployment using a new empty volume** and a verified private IP/port; budget and confirm resources. Do not expose port 3306 publicly. Preserve the existing 10.11 server as rollback evidence until the new environment is accepted.
3. Use a **new isolated NFS sites directory** (not the incomplete v15 site directory) for a v16 integration test; verify UID/GID 1000 and cross-host NFS semantics, and do not alter the running Frappe site's config.
4. Reuse Redis only after checking ACL authentication, protocol compatibility and isolated queue state; avoid mixing v15 and v16 job queues.
5. Keep all external integrations and production records disabled until all acceptance tests pass.
6. Handle the incomplete `frappe-suite-prod.benuel.dedyn.io` v15 site only after verifying its database identity, backing up the site directory/DB state and explicitly approving a changeover.

## CI acceptance gates

- Candidate image build and GHCR publication succeeded for both Suite and Insights (immutable digests recorded).
- Inspect `bench version` in each candidate image: Frappe 16, ERPNext 16, HRMS 16; confirm Python 3.14 and Node 24.
- Fresh disposable MariaDB 11.8 site created; installation of `frappe`, then `erpnext`, `hrms`, `crm`, `telephony`, `helpdesk`, `payments`, `lms`, `raven` tested in dependency order.
- Run `bench migrate`, `bench --site <test-site> list-apps`, and exercise Frappe server startup.
- Independently smoke-test Insights `version-3` with Frappe 16 and its own MariaDB 11.8 database.
- Record precise upstream app commit SHAs from the images. Current branch-based inputs are mutable; digest pins alone do not prove source-revision reproducibility.
- Validate Dokploy compose interpolation, encrypted Redis URLs, NFS outage fail-closed behavior, persistent MariaDB volumes, background jobs, realtime, uploaded files, TLS and isolated backups/restores.
- Only after all checks pass should the repository's verified-staging release record and Dokploy settings be intentionally updated.

## Current staging inventory (2026-11-02)

| Role | Public IP | Private IP |
|---|---|---|
| Application | 152.228.229.221 | 10.12.1.82 |
| Worker | 152.228.243.169 | 10.12.1.12 |
| MariaDB 10.11 (v15 staging only) | 57.128.30.144 | 10.12.0.92 |
| Insights host | 57.128.24.99 | 10.12.3.21 |
| Managed NFS | n/a | 10.12.0.212 |

Existing managed NFS export: `10.12.0.212:/shares/share-6cf129ad-2f50-4377-a570-2aa58464bbb9`. The current sites host path `/mnt/frappe-sites/frappe-site-data` is **v15 staging**, not the fresh v16 integration-test path.

## Safety

No commands in this document perform a live migration. An image build does not deploy an image. A CI success does not substitute for four-host staging acceptance. Do not enable the worker `site-ready` profile against the interrupted v15 site.
