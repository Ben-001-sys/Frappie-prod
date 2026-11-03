# Frappe Suite v16 staging migration candidate — 2026-11-03

Status: **PREPARATION ONLY — DO NOT DEPLOY TO CURRENT STAGING YET.**

## Scope and non-goals

- Intended target after approval: staging site `frappe-suite-prod.benuel.dedyn.io`.
- Actual live `frappe-suite.benuel.dedyn.io` must remain untouched.
- Keep the approved v15 image/digest in `release/verified-staging.json` and the current `apps/suite.json` unchanged.
- `apps/suite-v16-candidate.json` includes the eight suite apps plus official `offsite_backups` (moved out of Framework v16).
- A fresh-site smoke test is not proof of a successful v15-to-v16 migration of the actual staging database.

## Upstream release targets checked 2026-11-03

- Frappe Framework v16.54.0; ERPNext v16.53.0; HRMS v16.53.0.
- ERPNext and HRMS require Frappe >=16.50.0 and <17.0.0.
- CRM v1.91.1, Helpdesk v1.31.1, LMS v2.68.0, Raven v3.2.0.
- Telephony `develop`, Payments `version-16`, Offsite Backups `version-16`: no comparable stable release tag selected; record actual commit SHAs after image build.
- All candidates require integration and schema migration tests, regardless of declared compatibility.

## Infrastructure blockers and requirements

- Official Framework v16 prerequisites: MariaDB 11.8; Python 3.14; Node.js 24.
- Staging currently uses MariaDB 10.11 in a Docker container on the dedicated DB VM.
- The current Build Images workflow is explicitly v15; its existing paths, image names and pinned v15 digest must not be overwritten by experimental artifacts.
- The Suite image deployed to APP and WORKER must always have the same tested immutable GHCR digest.
- v16 offsite S3 backups require the separate `frappe/offsite_backups` app; protect/verify existing Backblaze B2 data and site settings before migration.
- Site's shared NFS data must not be mounted read-write by both v15 staging and an independently migrated test clone.
- Redis queue jobs pending at an upgrade point need review; a migrated database must not consume old incompatible queued jobs.
- Test actual Docker/Redis/Traefik/NFS behavior, not just fresh Bench installs.
- Insights remains on a separate VM/site and is not included in this Suite migration.

## Verified candidate build and fresh-site smoke test (2026-11-03)

- **Completed:** GitHub Actions run [41627916016](https://github.com/Ben-001-sys/Frappie-prod/actions/runs/41627916016) built and published the separate v16 candidate image and successfully ran the disposable nine-app fresh-install smoke test.
- Immutable candidate image: `ghcr.io/ben-001-sys/frappie-suite-v16-candidate@sha256:49a29105cfe6d99101e37ec92009d7510cddc31ef60ff4bf2daca9cde59d5383`.
- Tested against Python 3.14.10, Node 24.22.2, MariaDB 11.8.9 and Redis 7.4. The installed Frappe 16.54.0 / ERPNext 16.53.0 / HRMS 16.53.0 and remaining dependencies were recorded in `release/v16-candidate-smoke-20261103.json`.
- The isolated smoke test created a new site, installed ERPNext, HRMS, CRM, Telephony, Helpdesk, Payments, LMS, Raven and Offsite Backups, then ran `bench migrate` successfully.
- **Still unverified:** v15-to-v16 migration of the existing staging database/files, existing Backblaze B2 configuration/restore, production-like business workflows, multi-host runtime operation and upgrade rollback. Do not merge, redeploy or run staging migration based on the fresh-install test alone.
- The v15 operational Docker image, MariaDB 10.11 data volume, NFS sites and Dokploy deployments remain unchanged.

## Release gates

1. Confirm existing v15 staging recovery remains healthy. Independently verify complete downloadable Backblaze backup (DB, config, public and private archives) and preserve additional local full backup and database dump, including encryption key if later generated.
2. Build a **separate v16 candidate image** from version-16 upstream Frappe Docker image layers using `apps/suite-v16-candidate.json`. Do not replace `ghcr.io/ben-001-sys/frappie-suite` or deploy to Dokploy. Record all included app versions and exact commits and the image digest.
3. Run `scripts/smoke-install-v16.sh` against that candidate, an isolated MariaDB 11.8 and Redis instance. It must create and migrate a disposable site with all nine apps.
4. Clone the current v15 DB and uploaded files into a test-only storage/database environment, using fresh protected backups, no outbound side effects, separate paths and a separate hostname. Validate MariaDB 10.11→11.8 database upgrade path in this disposable environment.
5. Execute **one** v15→v16 `bench migrate` with the candidate image on the isolated clone. Include tests for offsite Backblaze configuration and the former v15 S3 Backup Settings migration. No `--skip-failing`.
6. Verify business-critical DocTypes, accounting, POS, HR, CRM, Helpdesk, LMS, Raven, Telephony, Payments, file attachments, PDF and WebSocket, workers and scheduler, permissions, and the Backblaze download path. Record actual acceptance evidence.
7. Only after passing all gates: schedule downtime on staging, capture a complete new v15 recovery point, stop writes and queues, upgrade the DB under a separately tested procedure, deploy the *same pinned v16 image digest* to APP and WORKER, migrate staging exactly once, validate, reopen traffic, and retain rollback artifacts.
8. Rollback from a failed v16 migration means **restoring the pre-upgrade v15 DB/files onto the previous v15 stack**, not merely changing the Docker image back. Preserve database snapshots and compatible configuration for rollback.

## Build/test note

The existing `.github/workflows/build-images.yml` publishes v15 Suite and Insights images and remains untouched. The separate `.github/workflows/build-v16-candidate.yml` was added to this draft branch on 2026-11-03; it publishes only `ghcr.io/ben-001-sys/frappie-suite-v16-candidate`, never the approved v15 image. The candidate Dockerfile (`images/frappe-suite-v16/Containerfile`) uses the pinned `frappe_docker` source at `fbf76edcf5791b1d9743955b85caf0a19974d5a6`, v16 base layers and the exact Frappe tag `v16.54.0`. It then runs `scripts/smoke-install-v16.sh` against *disposable* MariaDB 11.8 and Redis instances, with one-run-only passwords and separate Docker volume/network names. This is **not** a migrated staging clone and does not satisfy the upgrade rehearsal gate. The workflow includes no Dokploy deployment step. Record successful build and test evidence and the published digest before using the candidate in the subsequent rehearsal. Do not use the v15 smoke pipeline's MariaDB 10.11 for v16 validation.

## References

- https://docs.frappe.io/framework/user/en/installation
- https://github.com/frappe/frappe/wiki/Migrating-to-version-16
- https://docs.frappe.io/framework/user/en/bench/reference/migrate
- https://github.com/frappe/offsite_backups
- https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/02-build-setup.md
