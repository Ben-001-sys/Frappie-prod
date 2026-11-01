# Build and release procedure

Images are built from pinned upstream frappe_docker commit 61d35da827ebc04d01b64c9e78385597ccebc9d8. The operational Frappe image is shared between application and worker hosts; Insights is a separate image and site.

- On pushes affecting apps, workflow or this file, Actions builds both images to GHCR.
- Container images should be deployed with immutable digests to Dokploy.
- Build branch references (currently version-15 and main for some apps) are preliminary. Verify exact revisions and installed-app smoke tests before production.
- Never auto-deploy images to production from a build workflow.
- Deploy MariaDB, Redis and shared NFS first, then application site, then workers, then Insights.
- Apply schema migrations once with appropriate backups and a maintenance window.
- Test restore, NFS outage behavior, private networking and Redis ACLs before production.
