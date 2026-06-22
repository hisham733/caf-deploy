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
docker compose exec -T backend bash -c "ls sites/site1.local/site_config.json 2>/dev/null" || \
  docker compose exec -T backend bench new-site site1.local \
    --mariadb-root-password admin \
    --admin-password admin \
    --install-app erpnext \
    --install-app caf

# Fix DB user host to '%' so restarts don't break DB auth
echo "Setting DB user host to '%' for Docker IP stability..."
docker compose exec db mariadb -u root -p"$DB_PASSWORD" -NBe \
  "SELECT CONCAT('RENAME USER ''',User,'''@''',Host,''' TO ''',User,'''@''%%'';') FROM mysql.user WHERE User LIKE '\_%' AND Host != '%'" \
  | docker compose exec -T db mariadb -u root -p"$DB_PASSWORD"
