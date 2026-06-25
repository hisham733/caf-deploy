# Updating CAF in Production

This guide covers pulling a new Docker image and applying updates to your running Frappe site without losing data.

## Table of Contents

1. [When to Update](#when-to-update)
2. [Pre-Update: Backup](#pre-update-backup)
3. [Pull & Restart](#pull--restart)
4. [Run Migrations](#run-migrations)
5. [Verify](#verify)
6. [Rollback](#rollback)

---

## When to Update

You should update when:

- New code was pushed to `caf_hisham` and a fresh Docker image was built
- A new app was added to `apps.json` and the image was rebuilt
- You triggered a manual rebuild via `workflow_dispatch`
- You want the latest Frappe/ERPNext patches included in the base image

---

## Pre-Update: Backup

Before updating, back up your database and site files:

```bash
# Inside frappe_docker/

# Backup the entire site (DB + files)
docker compose exec backend bench --site "$SITE_NAME" backup \
  --with-files

# Or backup just the database
docker compose exec db mariadb-dump -u root -p"$DB_PASSWORD" \
  --all-databases > caf_backup_$(date +%Y%m%d_%H%M%S).sql
```

Backups are stored inside the backend container at `sites/$SITE_NAME/private/backups/` by default.

---

## Pull & Restart

Pull the latest image and recreate containers:

```bash
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always
```

What happens:

| Component | Gets replaced? | Data lost? |
|---|---|---|
| `backend` (Frappe) | Yes | No |
| `frontend` (Nginx) | Yes | No |
| `migrator` (one-shot) | Runs fresh | No |
| `db` (MariaDB) | No | No |
| `redis-cache` | No | Cache cleared |
| `redis-queue` | No | Queue cleared |

We also recommend copying the latest `compose.override.yaml` and `deploy.sh` from this repo if they've changed:

```bash
cp ~/caf-deploy/compose.override.yaml .
cp ~/caf-deploy/deploy.sh .
```

---

## Run Migrations

After the new backend starts, apply any pending database schema changes:

```bash
docker compose exec backend bench --site "$SITE_NAME" migrate
```

If the `migrator` container is included in your compose stack (it is by default), this runs automatically on startup.

---

## Verify

Check that everything is working:

```bash
# List installed apps
docker compose exec backend bench --site "$SITE_NAME" list-apps

# Check backend logs for errors
docker compose logs backend --tail 30

# Check migrator ran successfully
docker compose logs migrator --tail 20
```

Also visit `http://localhost:8080` and confirm your data, users, and modules are all present.

---

## Rollback

If the new image has issues, roll back to the previous version:

### Option A: Roll back by tag

Each build pushes two tags: `latest` and the commit SHA. You can pin to a known-good SHA:

1. Find the previous SHA on [GitHub Actions](https://github.com/hisham733/caf-deploy/actions)
2. Update `.env`:

```
CUSTOM_IMAGE=hisham733/caf-hisham
CUSTOM_TAG=<previous-sha>
```

3. Restart with the old image:

```bash
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always
```

4. Revert any DB migrations if needed:

```bash
docker compose exec backend bench --site "$SITE_NAME" migrate
```

### Option B: Full restore from backup

If the site is broken and you need a clean start:

```bash
# Stop and wipe containers (data in volumes stays)
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  down

# Restore DB from backup
docker compose exec -T db mariadb -u root -p"$DB_PASSWORD" < caf_backup_*.sql

# Restart
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always
```

### Option C: Reset everything (last resort)

This **wipes all data**:

```bash
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  down -v
./deploy.sh
```
