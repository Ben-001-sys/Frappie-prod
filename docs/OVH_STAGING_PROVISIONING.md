# OVHcloud staging hosts and NFS provisioning runbook

This is the staging **planning and execution checklist** for our four independent Dokploy Compose projects. These examples must be replaced with actual values and validated on the chosen OVHcloud region before use. Never reuse the current live ERPNext database or NFS data for the trial.

## Required infrastructure inventory

Record these values in a private inventory, not in the public GitHub repository:

| Role | Private IPv4 or resolvable DNS | Operating system | Persistent disk |
|---|---|---|---|
| Application | App-host private endpoint | Ubuntu 24.04 LTS | Image and container state |
| Worker / Redis | Worker-host private endpoint | Ubuntu 24.04 LTS | Redis queue AOF and logs |
| MariaDB | DB-host private endpoint | Ubuntu 24.04 LTS | Dedicated MariaDB storage |
| Insights | Insights-host private endpoint | Ubuntu 24.04 LTS | Its own DB and site files |
| NFS managed share | Provider-supplied private NFS endpoint and export path | Managed | Shared Frappe `sites/` files |
| Dokploy | Existing management endpoint, if suitable | Existing | Management DB / backup |

Do not deploy the test environment to the existing production Frappe site or production MariaDB. The test must have its own domain and database.

## Managed NFS capacity and region gate

**Check the actual OVHcloud region and service availability before ordering.** OVHcloud's public File Storage product page currently advertises share sizes starting at **150 GiB**, not the 20–50 GiB previously considered for this proof of concept. Expect this to affect monthly staging cost. Do not assume a smaller share can be created.

The [official File Storage setup guide](https://docs.ovhcloud.com/en/guides/storage-and-backup/file-storage/file-storage-service/getting-started) documents private-network association, ACLs and a provider-supplied export path. Obtain the exact mount command from the created share, and check whether NFSv4 is supported for that provisioned service; do not mix protocol assumptions from older OVHcloud marketing pages and newer setup instructions. The share must be in a compatible region/network reachable by both staging clients.

**Cost approval gate:** Before creating billable OVH resources, record the region, VM flavors, managed NFS plan/minimum size, hourly pricing, bandwidth and snapshot charges. User approval is required for billable provisioning.

## Private network and firewall

- Put the four instances and managed NFS in an appropriate private network/vRack with verified end-to-end routes. Different Compose projects do **not** share Docker DNS.
- Inbound to operational MariaDB 3306: only the application, worker and authorized temporary provisioning sources. No public exposure.
- Inbound to Redis ports 6379 (cache) and 6380 (queue): only app and worker sources, using private IP bindings and ACL authentication. Redis does not need public exposure.
- NFS access: authorize only application and worker private client IPs, using the provider's documented NFS port/protocol requirements.
- Only the Frappe web and Insights web frontends should be reachable through their TLS reverse proxies. Set Dokploy to route to container port `8080`.
- Restrict SSH to Dokploy management and authorized administrator sources; do not depend on the public internet for app-to-database traffic.

## Install host runtime on each VM (once)

Install Docker Engine and the Docker Compose plugin from the official Docker package repository for the chosen Ubuntu release, following [Docker's Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/). Then verify:

```bash
docker version
docker compose version
sudo systemctl is-active docker
```

Add only the needed remote servers to Dokploy; verify you are selecting the intended host when creating each Compose service.

## Mount managed NFS on the application and worker VMs

For both Linux hosts (not the MariaDB or Insights VMs):

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
sudo mkdir -p /mnt/frappe-sites

# Replace NFS_SERVER and EXPORT_PATH with the actual OVH-managed share values.
sudo mount -t nfs4 NFS_SERVER:EXPORT_PATH /mnt/frappe-sites

findmnt -T /mnt/frappe-sites -o TARGET,SOURCE,FSTYPE,OPTIONS
mountpoint /mnt/frappe-sites
```

Provision a persistent systemd mount/fstab entry using the actual export and required NFS protocol version. Do not automatically start site-dependent Docker services when the mount is unavailable. Avoid a silent local-directory fallback; the repository's `scripts/check-nfs.sh` checks for a real NFS mount.

**Cross-host test:** On the application host, create a temporary test file in the share. On the worker host, confirm the exact contents, modify it, and check the change from the app host. Remove the file after the test. Also verify write permissions under the container's effective user UID/GID, not only as root.

NFS file permissions and root-squash behavior are provider-specific. Validate on the actual share before using it for a Frappe site.

## GitHub Container Registry

Both application and worker Compose deployments must reference **the exact same immutable suite digest** after the new full Bench smoke test succeeds. Insights uses its independent digest. If GHCR packages are private, configure read access in Dokploy without committing credentials.

## Deploy order

1. Create the separate staging private network, hosts and NFS share.
2. Verify ports, storage, SSH and NFS on both app/worker hosts.
3. Deploy MariaDB and Redis Compose services; test healthy and private-only connectivity.
4. Deploy Frappe application Compose to the app host.
5. Initialize the single operational site **once** using the designated backend and authorized temporary DB provisioning credentials. Do not repeat site creation on workers.
6. Enable the worker profile and verify jobs, scheduler, realtime, files and site configuration.
7. Deploy Insights on its independent host, create its own site and verify read-only reporting connectivity.
8. Demonstrate snapshots, independent backups, and a safe isolated restore test before moving beyond staging.

## Staging acceptance tests

- `bench --site <staging-site> list-apps` shows all eight installed packages (six business apps plus Telephony and Payments dependencies).
- Browser login and one basic business workflow operate across the web/backend tier.
- An enqueued job runs on the worker host, not just inside the app host.
- A public and a private attachment are available through the backend while residing on shared NFS.
- Frappe and Insights remain separate sites, databases and application images.
- A file created on one NFS client becomes visible to the other.
- Database and NFS files persist across container recreation and host reboot.
- Missing NFS prevents startup rather than writing to a local substitute directory.
- Restore and rollback procedures are verified before any real business data is imported.

No scripts in this repository automatically provision OVH resources, change Dokploy's existing projects, or touch live Frappe data.
