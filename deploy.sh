#!/bin/bash
set -e

# Load from .env if present
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

SITE_NAME="${SITE_NAME:-site1.local}"
DB_PASSWORD="${DB_PASSWORD:-admin}"

# Start the stack
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always

# Create site only if it doesn't already exist
if ! docker compose exec -T backend test -f "sites/$SITE_NAME/site_config.json"; then
  echo "Creating site $SITE_NAME..."
  docker compose exec -T backend bench new-site "$SITE_NAME" \
      --mariadb-root-password "$DB_PASSWORD" \
      --admin-password admin \
      --mariadb-user-host-login-scope '%' \
      --install-app erpnext \
      --install-app caf
else
  echo "Site $SITE_NAME already exists, skipping creation."
fi
