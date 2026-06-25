# CAF Deployment Workflows

Four common scenarios for managing your Frappe production server.

All commands assume you are inside `frappe_docker/` with `.env`, `compose.override.yaml`, and `deploy.sh` in place.

---

## 0. Develop and Push App Changes

Use this before scenarios 2 and 3 below. App source code lives in the dev environment at `/workspace/development/frappe-bench/apps/caf/` (the `caf_hisham` repo, `develop` branch).

### Step 1 — Make changes
Edit files in `apps/caf/` as needed.

### Step 2 — Stage, commit, push
```bash
# In /workspace/development/frappe-bench/apps/caf/
git add .
git commit -m "description of changes"
git push
```

### Step 3 — Proceed to pipeline
After push succeeds, follow **Scenario 2** below to trigger the image build and deploy to production.

---

## 1. Fresh Install (from zero)

Use this when setting up a brand new server or after wiping everything with `down -v`.

### Prerequisites

- Docker + Docker Compose installed
- `frappe_docker` repo cloned on the server
- `compose.override.yaml` copied next to `compose.yaml`
- `.env` configured (copy from `caf-deploy/.env.example`)

### Option A — Use deploy.sh (recommended)

```bash
cp ~/caf-deploy/deploy.sh .
./deploy.sh
```

### Option B — Manual steps

```bash
# 1. Ensure FRAPPE_SITE_NAME_HEADER matches SITE_NAME (deploy.sh does this automatically)
export FRAPPE_SITE_NAME_HEADER="${SITE_NAME:-site1.local}"

# 2. Start the stack (MariaDB, Redis, backend, frontend, migrator)
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always

# 3. Create site with all apps
docker compose exec backend bench new-site "$SITE_NAME" \
  --mariadb-root-password "$DB_PASSWORD" \
  --admin-password admin \
  --mariadb-user-host-login-scope '%' \
  --install-app erpnext \
  --install-app hrms \
  --install-app caf

# 4. Access at http://localhost:8080
#    Login: Administrator / admin
```

---

## 2. Update CAF App (after code changes)

Use this after completing **Scenario 0** (push changes to `caf_hisham`). Triggers a new Docker image build and deploys it to production.

### Step 1 — Trigger image build

```bash
# From any machine with gh CLI
gh workflow run build.yml --repo hisham733/caf-deploy --ref main
```

Wait ~5-10 minutes for the build to finish. Check status:

```bash
gh run list --repo hisham733/caf-deploy --limit 3
```

### Step 2 — Deploy to production

```bash
# On production server, inside frappe_docker/
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always
```

`--pull always` pulls the new `hisham733/caf-hisham:latest` image before recreating containers. No separate `docker compose pull` needed.

### Step 3 — Apply DB migrations (if any)

```bash
docker compose exec backend bench --site "$SITE_NAME" migrate
```

### Step 4 — Verify

```bash
docker compose exec backend bench --site "$SITE_NAME" list-apps
# Confirm caf app is listed
```

Open `http://localhost:8080` and confirm the changes are live.

---

## 3. Install a New App (e.g., HRMS)

Use this when you want to add a new Frappe app to the stack.

### Step 1 — Add the app to `apps.json`

Edit `apps.json` in the `caf-deploy` repo:

```json
[
  { "url": "https://github.com/frappe/erpnext", "branch": "version-15" },
  { "url": "https://github.com/frappe/hrms",     "branch": "version-15" },
  { "url": "https://github.com/hisham733/caf_hisham.git", "branch": "develop" }
]
```

Rules:
- **Public repos** use `https://` URL
- **Branch** must match the Frappe version (version-15)
- **Order:** core apps first, then custom apps

### Step 2 — Commit and push

```bash
git add apps.json
git commit -m "feat: add hrms app"
git push
```

Pushing to `main` triggers the GitHub Action build automatically (only `apps.json` or workflow changes trigger it).

### Step 3 — Wait for the build to complete

```bash
# Optional: check build status
gh run list --repo hisham733/caf-deploy --limit 3
```

Or check [github.com/hisham733/caf-deploy/actions](https://github.com/hisham733/caf-deploy/actions).

### Step 4 — Deploy the new image

```bash
# On production server, inside frappe_docker/
docker compose -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.migrator.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d --pull always
```

### Step 5 — Install the app on the site

The app is now in the Docker image but not yet registered on your site:

```bash
docker compose exec backend bench --site "$SITE_NAME" install-app hrms
```

### Step 6 — Verify

```bash
docker compose exec backend bench --site "$SITE_NAME" list-apps
```

Expected output includes: `erpnext`, `hrms`, `caf`.

Open `http://localhost:8080` and check that HRMS modules appear in the desk.

---

> **For production updates** (backup, migrations, rollback), see [UPDATE.md](./UPDATE.md).
