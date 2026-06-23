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
| `.env.example` | Template for production `.env` (image ref, DB password, gunicorn settings) |
| `README.md` | Full reference documentation |
| `WORKFLOW.md` | Step-by-step workflows for 4 scenarios |
| `AI_CONTEXT.md` | This file — for AI context restoration |

## Docker Compose Stack
Base compose file is from `frappe/frappe_docker` (`compose.yaml`). Overrides used:
- `compose.mariadb.yaml` — MariaDB 11.8
- `compose.redis.yaml` — Redis cache + queue
- `compose.migrator.yaml` — Auto-migration on startup
- `compose.noproxy.yaml` — Exposes port 8080

## Build Pipeline (build.yml)
- Uses `images/layered/Containerfile` from `frappe/frappe_docker`
- Apps injected via `apps.json` using BuildKit `--secret` (not ARG)
- Build args: `FRAPPE_BRANCH=version-15`, `CACHE_BUST=${{ github.sha }}`
- Tags pushed: `latest` + commit SHA

## Deployment Commands

### Fresh install
```bash
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d

docker compose exec backend bench new-site site1.local \
  --mariadb-root-password admin \
  --admin-password admin \
  --mariadb-user-host-login-scope '%' \
  --install-app erpnext \
  --install-app caf
```

### Update (after code change + build)
```bash
gh workflow run build.yml --repo hisham733/caf-deploy --ref main
# wait for build
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always
docker compose exec backend bench --site site1.local migrate
```

### Add new app (e.g., HRMS)
1. Add to `apps.json`
2. Push → triggers build
3. `up -d --pull always`
4. `docker compose exec backend bench --site site1.local install-app hrms`

### Useful commands
```bash
docker compose exec backend bench --site site1.local list-apps
docker compose exec backend bench --site site1.local migrate
docker compose exec backend cat sites/site1.local/site_config.json
docker compose exec backend cat sites/common_site_config.json
docker compose logs backend --tail 50
docker compose logs configurator --tail 20
docker compose exec db mariadb -u root -padmin -e "SHOW DATABASES;"
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
docker compose exec backend rm /home/frappe/frappe-bench/sites/site1.local/locks/bench_migrate.lock
```

## Site Access
- URL: `http://localhost:8080`
- Login: `Administrator` / `admin`
- Site name: `site1.local`
