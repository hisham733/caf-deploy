#!/bin/bash
set -e

# Start the stack
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d

# Create site with all apps (only if site doesn't exist)
docker compose exec -T backend bench new-site site1.local \
    --mariadb-root-password admin \
    --admin-password admin \
    --mariadb-user-host-login-scope '%' \
    --install-app erpnext \
    --install-app caf
