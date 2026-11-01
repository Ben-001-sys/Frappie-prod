# Build and release procedure

Images are built from pinned upstream frappe_docker commit 61d35da827ebc04d01b64c9e78385597ccebc9d8. The operational Frappe image is shared between application and worker hosts; Insights is a separate image and site.

- On pushes affecting apps, workflow or this file, Actions builds both images to GHCR.
- Container images should be deployed with immutable digests to Dokploy.
- Build branch references (currently version-15 and main for some apps) are preliminary. Verify exact revisions and installed-app smoke tests before production.
- Never auto-deploy images to production from a build workflow.
- Deploy MariaDB, Redis and shared NFS first, then application site, then workers, then Insights.
- Apply schema migrations once with appropriate backups and a maintenance window.
- Test restore, NFS outage behavior, private networking and Redis ACLs before production.

## Dependency repair (2026-11-01)

First full Suite smoke-install run 41339169444 failed on Helpdesk due to missing Telephony; the previous suite GHCR image must not be deployed. Upstream Learning also declares Payments as a required app. The corrected suite image includes Telephony (`develop`) and Payments (`version-15`), installed in dependency order before Helpdesk and Learning. Both are supporting apps, not additional independent sites. Bench smoke tests are triggered automatically after a successful image build.
