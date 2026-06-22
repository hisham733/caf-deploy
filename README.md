# CAF Frappe Deployment Pipeline

## Architecture Overview

```
caf_hisham (app source)  ───┐
                             ├── GitHub Actions ──→ Docker Image ──→ Production
caf-deploy (config) ────────┘   (build.yml)     hisham733/caf-hisham   Server (frappe_docker)
```

Two repos:
- **`hisham733/caf_hisham`** — CAF Frappe app source code (develop branch)
- **`hisham733/caf-deploy`** — Deployment config (this repo): `apps.json`, `build.yml`, `deploy.sh`, `.env`

The app and Frappe/ERPNext are **not installed directly on the server**. A pre-built Docker image (`hisham733/caf-hisham:latest`) contains everything: Frappe v15, ERPNext v15, and the CAF app. The production server only pulls this image.

---

## CI/CD Pipeline (GitHub Actions)

Triggered by:
- Push to `main` branch
- Manual trigger (`workflow_dispatch`)

### Steps

1. **Checkout repos** — Clones `caf-deploy` (this repo) and `frappe/frappe_docker`
2. **Copy `apps.json`** — Injects the list of custom apps into the build context
3. **Login to Docker Hub** — Uses `DOCKER_PAT` secret
4. **Build image** — Uses `images/layered/Containerfile` from frappe_docker with:
   - `FRAPPE_BRANCH=version-15` — Frappe v15 base
   - `apps.json` (secret) — Installs ERPNext + caf_hisham
   - `CACHE_BUST=${{ github.sha }}` — Busts Docker cache layers
5. **Push** — Tags pushed: `latest` + commit SHA

### Manual Trigger

```bash
gh workflow run build.yml --repo hisham733/caf-deploy --ref main
```

### `apps.json`
```json
[
  { "url": "https://github.com/frappe/erpnext", "branch": "version-15" },
  { "url": "https://github.com/hisham733/caf_hisham.git", "branch": "develop" }
]
```

---

## Deployment Process (`deploy.sh`)

### Flow

```bash
# On production server, inside frappe_docker/ directory:

./deploy.sh    # Or run steps manually
```

### What `deploy.sh` does

1. **Start the stack** — Runs `docker compose` with all overrides:
   - `compose.yaml` (base)
   - `compose.mariadb.yaml` (MariaDB 11.8)
   - `compose.redis.yaml` (Redis cache + queue)
   - `compose.migrator.yaml` (auto-migration)
   - `compose.noproxy.yaml` (port 8080)

2. **Create site** (first run only) — Checks if `site1.local/site_config.json` exists. If not, creates `site1.local` with ERPNext + CAF installed.

### Prerequisites

- Docker + Docker Compose installed on server
- `frappe_docker` repo cloned
- `.env` file configured (copy from `.env.example`)
- `compose.override.yaml` present alongside `compose.yaml`

### `.env` Configuration

```
CUSTOM_IMAGE=hisham733/caf-hisham
CUSTOM_TAG=latest
PULL_POLICY=always
DB_PASSWORD=your_db_password_here
```

### `compose.override.yaml`

Overrides the base Frappe image reference to use the custom CAF image:
```yaml
x-customizable-image: &customizable_image
  image: hisham733/caf-hisham:latest
  pull_policy: always
  restart: unless-stopped
```

---

## Full Update Cycle (app code changed)

```
1. Push app changes to hisham733/caf_hisham
         ↓
2. Trigger CAF image build:
   gh workflow run build.yml --repo hisham733/caf-deploy --ref main
         ↓
3. Wait for build to finish (check Actions tab)
         ↓
4. On production server:
   
   # Pull new image and restart
   docker compose -f compose.yaml \
     -f overrides/compose.mariadb.yaml \
     -f overrides/compose.redis.yaml \
     -f overrides/compose.migrator.yaml \
     -f overrides/compose.noproxy.yaml \
     up -d --pull always
   
   # Apply any DB schema changes
   docker compose exec backend bench --site site1.local migrate
   
   # Verify at http://localhost:8080
```

---

## Known Issues & Fixes

### DB User IP Locking

**Problem:** When `bench new-site` creates a MariaDB user, it locks it to the backend container's Docker IP (e.g., `192.168.48.9`). On container restart, the backend gets a new IP, causing `Access denied` errors.

**Error seen:**
```
pymysql.err.OperationalError: (1045, "Access denied for user '_b533f5fdd65aaf8c'@'192.168.48.6'")
```

**Diagnosis:**
```sql
SELECT User, Host FROM mysql.user WHERE User LIKE '_b533%';
-- Returns: _b533f5fdd65aaf8c | 192.168.48.9  (old IP, not current)
```

**Fix (one-time after site creation):**
```bash
docker compose exec db mariadb -u root -p"$DB_ROOT_PASSWORD" -NBe \
  "SELECT CONCAT('RENAME USER ''',User,'''@''',Host,''' TO ''',User,'''@''%%'';') FROM mysql.user WHERE User LIKE '\_%' AND Host != '%'" \
  | docker compose exec -T db mariadb -u root -p"$DB_ROOT_PASSWORD"
```

**Prevention:** The above command is permanently added to `deploy.sh` right after `bench new-site`, so it runs automatically on the first deployment.

### Configurator Errors

The `configurator` container runs on every `docker compose up -d` and can overwrite site configs with incomplete values. If you see:

```
configurator exited with code 2
Error: Missing argument 'VALUE'
```

This is a known Frappe Docker issue when restarting an existing site. The configurator tries to run `bench set-config` without all required arguments. Workaround: restart individual services instead of the full stack.

---

## Troubleshooting

### "Access denied for user" on restart
Re-run the DB user fix command above.

### Site broken after restart
```bash
# View logs
docker compose logs backend --tail 50
docker compose logs configurator --tail 20
docker compose logs migrator --tail 20

# Check current config
docker compose exec backend cat sites/site1.local/site_config.json
docker compose exec backend cat sites/common_site_config.json

# Reset completely (WIPES ALL DATA)
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  down -v
# Then re-run deploy.sh
```

### Access site
- URL: `http://localhost:8080`
- Login: `Administrator` / `admin`

---

## File Reference

| File | Purpose |
|---|---|
| `apps.json` | List of Frappe apps to install in the Docker image |
| `.github/workflows/build.yml` | GitHub Actions workflow to build and push Docker image |
| `deploy.sh` | One-shot deployment script for production server |
| `.env.example` | Template for production `.env` file |
| `compose.override.yaml` | Overrides base image to use custom CAF image |
