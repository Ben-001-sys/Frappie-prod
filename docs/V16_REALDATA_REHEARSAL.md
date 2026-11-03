# Isolated v15 → v16 migration rehearsal — executable runbook

Status: **prepared, not yet executed against real staging data**.

## Scope and safety

- Input: four already verified local v15 backup files from the staging site, dated 2026-11-03 11:34 UTC.
- Frappe Suite v16 candidate: `ghcr.io/ben-001-sys/frappie-suite-v16-candidate@sha256:49a29105cfe6d99101e37ec92009d7510cddc31ef60ff4bf2daca9cde59d5383`.
- The existing operational v15 staging server has only 3.7 GiB RAM, **no swap**, and 38 GiB free. Do **not** run the candidate image + MariaDB 11.8 rehearsal on that app server.
- Use an **independent, disposable, x86_64 Docker host** with about 8 GiB RAM and at least 60 GiB free storage. It must not be the current staging app, worker or database host, and must not mount production NFS.
- The rehearsal creates *local test Docker volumes and containers only*, an internal-only Docker network, and does **not** publish host ports or connect to the live MariaDB.
- No scripts alter the staging server's configuration, database, deployments, or NFS backup source.
- Site configuration backup contains the encryption key; handle every exported archive as confidential.
- This is a **migration engineering test**. Do not merge or deploy to current staging merely because this script completes. Business, scheduled backups, email, permissions and multi-host/NFS workflows still require validation.

## Step A — Export the four already verified backup archives (on `frappe-stg-app`)

Review the script source, then run as root:

```bash
curl -fsSLo /root/export-v15-rehearsal-backup.sh \
  'https://raw.githubusercontent.com/Ben-001-sys/Frappie-prod/upgrade/v16-staging-20261103/scripts/export-v15-rehearsal-backup.sh'
bash -n /root/export-v15-rehearsal-backup.sh
bash /root/export-v15-rehearsal-backup.sh
```

It creates exactly one local restricted file, `/root/frappe-v16-rehearsal-backup-20261103.tar.gz`, without touching or rewriting the live NFS source.

## Step B — Transfer privately to the dedicated rehearsal VM (from `frappe-stg-app`)

Replace `REHEARSAL_VM_IP` with the **new isolated test VM's private or authorized SSH address** (not the staging DB/app/worker VM):

```bash
scp -p /root/frappe-v16-rehearsal-backup-20261103.tar.gz \
  root@REHEARSAL_VM_IP:/root/
```

Do not send this archive by email, paste it in chat, or upload it to a public GitHub repository.

## Step C — Run database restoration and v16 migration (on the separate rehearsal VM)

Install/configure Docker first. Then:

```bash
set -euo pipefail
umask 077
mkdir -p /root/frappe-v16-rehearsal-input
tar -xzf /root/frappe-v16-rehearsal-backup-20261103.tar.gz \
  -C /root/frappe-v16-rehearsal-input
curl -fsSLo /root/run-isolated-v16-rehearsal.sh \
  'https://raw.githubusercontent.com/Ben-001-sys/Frappie-prod/upgrade/v16-staging-20261103/scripts/run-isolated-v16-rehearsal.sh'
bash -n /root/run-isolated-v16-rehearsal.sh
bash /root/run-isolated-v16-rehearsal.sh \
  /root/frappe-v16-rehearsal-input/frappe-v16-rehearsal-backup-20261103
```

The script performs the following as a single fail-fast run:

1. Refuse known staging hosts, active production NFS mounts and operational container names.
2. Check the backup SHA-256 manifest, gzip, tar and backup site-config JSON.
3. Pull the pinned v16 image plus MariaDB 11.8 and Redis 7.4.
4. Create a new internal-only Docker network and **unique-to-this-rehearsal** named test volumes/containers; refuse to reuse any pre-existing resources.
5. Create a disposable v16 site and copy **only** the backup encryption key into the new site's configuration, retaining a *new* isolated database and credentials.
6. Restore the v15 SQL and file archives into the disposable site using the documented `bench restore` command, then run the v15→v16 `bench migrate` with no `--skip-failing`.
7. Install `offsite_backups`, perform a final migration check, list apps and verify database access.
8. Retain disposable volumes for diagnosis. No public ingress or scheduler/worker containers are started. Docker networking blocks external callbacks.

**If any step fails, stop.** Do not work around failures with `--skip-failing`, change the network to permit public egress, or rerun the script against partially created resources. Review the error, diagnose, then rebuild the rehearsal in a *fresh* isolated environment.

## Step D — Acceptance evidence

Before approving any staging changes, record:

- All nine originally installed apps migrated, plus the v16 `offsite_backups` app.
- Schema migrations and Frappe patch logs; no skipped failures.
- Business records, attachments, file permissions and the original encryption key.
- POS, accounting, HR, CRM, Helpdesk, LMS, Raven, Payments and Telephony workflows.
- Migration of backup settings, with outbound Backblaze tests coordinated separately with the backup owner.
- App/Worker same image digest, Redis queues, WebSocket, NFS and Traefik on a controlled later multi-host test.
- A separate **v15 pre-upgrade recovery set** is independently restorable.

The script alone covers the CLI/database portion, not every application and infrastructure acceptance criterion.

## Step E — Cleanup (only after recording results)

On the disposable rehearsal VM, manually delete the *exact* named test containers, volumes and network **only when finished**:

```bash
docker rm -f \
  frappe-v16-realdata-rehearsal-db \
  frappe-v16-realdata-rehearsal-redis
docker network rm frappe-v16-realdata-rehearsal-net
docker volume rm \
  frappe-v16-realdata-rehearsal-sites \
  frappe-v16-realdata-rehearsal-dbdata
```

After verifying your migration evidence is safely recorded, securely remove the copied backup from the test VM under the organization's data retention policy. No script automatically deletes test evidence.

## References

- https://docs.frappe.io/framework/user/en/bench/reference/restore
- https://docs.frappe.io/framework/user/en/bench/reference/migrate
- https://docs.frappe.io/cloud/sites/migrate-an-existing-site
