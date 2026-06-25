# AI Context — CAF Frappe Deployment

## Project Purpose
Deploy a custom Frappe app (CAF) to production using `frappe_docker` with a custom Docker image built via GitHub Actions (layered approach).

## Repos
- **`hisham733/caf_hisham`** — CAF Frappe app source code (branch: `develop`)
- **`hisham733/caf-deploy`** — Deployment config, build pipeline, docs

## Architecture
```
caf_hisham (dev) → push → GitHub Actions (builds image) → Docker Hub → production (docker compose up -d --pull always)
```

The Docker image (`hisham733/caf-hisham:latest`) bundles Frappe v15 + ERPNext v15 + CAF app. Production server never pulls source code.

## Key Files in `caf-deploy/`

| File | Purpose |
|---|---|
| `apps.json` | Lists apps to install in the image (ERPNext, HRMS, caf_hisham, etc.) |
| `.github/workflows/build.yml` | GitHub Actions workflow: builds layered Containerfile, pushes to Docker Hub |
| `deploy.sh` | One-shot script: starts compose stack + creates site (first run only) |
| `compose.override.yaml` | Overrides base Frappe image ref to use custom image |
| `.env.example` | Template for production `.env` (image ref, DB password, site name, gunicorn) |
| `README.md` | Full reference documentation with Quick Start |
| `UPDATE.md` | Pulling new images, running migrations, rollback guide |
| `WORKFLOW.md` | Step-by-step workflows for 4 scenarios |
| `WINDOWS.md` | Windows setup guide |
| `AI_CONTEXT.md` | This file — for AI context restoration |

## Docker Compose Stack
Base compose file is from `frappe/frappe_docker` (`compose.yaml`). Overrides used:
- `compose.mariadb.yaml` — MariaDB 11.8
- `compose.redis.yaml` — Redis cache + queue
- `compose.migrator.yaml` — Auto-migration on startup
- `compose.noproxy.yaml` — Exposes port 8080

Custom image pulled via `compose.override.yaml`.

## Build Pipeline (build.yml)
- Triggered only when `apps.json` or `.github/workflows/build.yml` changes (not on doc/config pushes)
- Uses `images/layered/Containerfile` from `frappe/frappe_docker`
- Apps injected via `apps.json` using BuildKit `--secret` (not ARG)
- Build args: `FRAPPE_BRANCH=version-15`, `CACHE_BUST=${{ github.sha }}`
- Tags pushed: `latest` + commit SHA

## Environment Variables (.env)

| Variable | Default | Used By |
|---|---|---|
| `CUSTOM_IMAGE` | `hisham733/caf-hisham` | Docker Compose |
| `CUSTOM_TAG` | `latest` | Docker Compose |
| `PULL_POLICY` | `always` | Docker Compose |
| `DB_PASSWORD` | `admin` | deploy.sh + Compose |
| `SITE_NAME` | `site1.local` | deploy.sh (bench new-site) |
| `FRAPPE_SITE_NAME_HEADER` | derived from `SITE_NAME` by deploy.sh | Nginx (routes requests) |
| `GUNICORN_THREADS` | `4` | Gunicorn |
| `GUNICORN_WORKERS` | `2` | Gunicorn |
| `GUNICORN_TIMEOUT` | `120` | Gunicorn |

`FRAPPE_SITE_NAME_HEADER` is automatically exported by `deploy.sh` from `SITE_NAME`, so you only need to set one place.

## Deployment Commands

### Fresh install (README Quick Start)
```bash
git clone https://github.com/frappe/frappe_docker.git
cd frappe_docker
git clone https://github.com/hisham733/caf-deploy.git ~/caf-deploy
cp ~/caf-deploy/compose.override.yaml .
cp ~/caf-deploy/.env.example .env
# edit .env (at least DB_PASSWORD)
cp ~/caf-deploy/deploy.sh .
./deploy.sh
```

### deploy.sh does
1. Sources `.env`
2. Exports `FRAPPE_SITE_NAME_HEADER=$SITE_NAME`
3. `docker compose up -d --pull always` (with all overrides)
4. Creates site `$SITE_NAME` with erpnext + hrms + caf if not exists

### Update (after code change + build)
See `UPDATE.md` for full details, backup, rollback.

```bash
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always

docker compose exec backend bench --site "$SITE_NAME" migrate
```

### Add new app (e.g., HRMS)
1. Add to `apps.json`
2. Push → triggers build (`apps.json` path filter)
3. `up -d --pull always`
4. `docker compose exec backend bench --site "$SITE_NAME" install-app hrms`

### Useful commands
```bash
docker compose exec backend bench --site "$SITE_NAME" list-apps
docker compose exec backend bench --site "$SITE_NAME" migrate
docker compose exec backend cat "sites/$SITE_NAME/site_config.json"
docker compose exec backend cat sites/common_site_config.json
docker compose logs backend --tail 50
docker compose logs configurator --tail 20
docker compose exec db mariadb -u root -p"$DB_PASSWORD" -e "SHOW DATABASES;"
```

## Issues & Fixes

### DB user IP locking (SOLVED)
**Problem:** `bench new-site` locks DB user to container IP. On restart, backend gets new IP → `Access denied`.
**Fix:** `--mariadb-user-host-login-scope '%'` flag passed to `bench new-site` in `deploy.sh`.

### Configurator errors (KNOWN)
`configurator` exits with code 2 / `Error: Missing argument 'VALUE'` on restart. Known Frappe Docker issue. Workaround: restart individual services instead of full stack.

### Stale migrate lock
`bench_migrate.lock` stuck from migrator container. Fix:
```bash
docker compose exec backend rm "/home/frappe/frappe-bench/sites/$SITE_NAME/locks/bench_migrate.lock"
```

## Site Access
- URL: `http://localhost:8080`
- Site: `$SITE_NAME` (default `site1.local`)
- Login: `Administrator` / `admin`
