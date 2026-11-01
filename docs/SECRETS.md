# Secrets and network policy

Never commit production passwords, .env files or actual Redis ACLs. Store credentials in Dokploy or a dedicated secret manager; archive recovery credentials separately from live infrastructure.

## Redis ACL configuration

On the worker host, create two distinct ACL files with strong unique secrets at `/srv/frappe/redis/cache.acl` and `/srv/frappe/redis/queue.acl`. Grant the Redis container read access while restricting other users:

```text
user default on >REPLACE_WITH_STRONG_SECRET ~* &* +@all
```

Set both URLs in Dokploy's Application environment, URI-encoding passwords where necessary:

```text
REDIS_CACHE_URL=redis://:URL_ENCODED_CACHE_PASSWORD@10.20.0.20:6379
REDIS_QUEUE_URL=redis://:URL_ENCODED_QUEUE_PASSWORD@10.20.0.20:6380
```

Restrict both ports to the private network and authorized application hosts. Container admins may inspect environment URLs, so restrict Docker and Dokploy access.

## MariaDB

MariaDB root is local-only. Provision a temporary administrative SQL user specifically for one-time site creation, allowing only the required private source hosts and grants. Ensure the site's SQL account can connect from the app and worker hosts. Revoke the setup account after use.

## Reporting

Insights connects with a restricted read-only SQL identity, ideally using a separate reporting replica for heavier dashboards. Direct SQL access does not enforce Frappe document permissions: protect HR, payroll and messaging data through dataset curation and access control.
