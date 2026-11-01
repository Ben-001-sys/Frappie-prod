# Architecture

- Four distinct Docker Compose projects on independent VMs managed by Dokploy; no Docker Swarm required.
- **Application**: Frappe backend, frontend, WebSocket and one authoritative configurator.
- **Workers**: Redis cache, Redis queue, RQ workers and one scheduler.
- **Database**: primary MariaDB, bound only to the private VM address.
- **Insights**: a separate Frappe Insights application, its own database and Redis, with read-only analytics access to operational data.
- **Shared files**: operational App and Worker servers mount the *same real NFSv4 filesystem* at `/mnt/frappe-sites`, mapped to `/home/frappe/frappe-bench/sites` inside containers. Insights does not mount that NFS.
- **Code**: App and Worker use the same immutable GHCR suite image digest; different container startup commands.
- **Initialization**: one Bench site installation from the App backend, never from workers; no automatic production migrations.
- **Network**: private routes between services; only two frontend services exposed through HTTPS.
- **Backups**: protect MariaDB, binlogs, NFS files, site encryption keys, Insights data, Dokploy control state and versioned images.
- **Production gate**: integration tests, restored backup, image compatibility, documented NFS outage handling, Redis ACLs, DB security and recovery targets.
