# Maemo Compliance — Deployment & Operations Guide

**Version:** 1.0 — May 2026  
**Audience:** DevOps, platform engineers, and developers deploying or supporting Maemo.  
**Related docs:** `docs/MAEMO_DECOUPLING_BLUEPRINT.md`, `docs/MAEMO_AUDIT_REPORT.md`, `docs/MAEMO_UI_AUDIT_REPORT.md`

---

## 1. Executive summary

Maemo is moving from a **single monolith** (`maemo` / `MaemoCompliance`) to **six deployable services** plus a **legacy stack** that stays online until cutover.

| State | What it means |
|--------|----------------|
| **Production today (typical)** | Monolith on Hetzner: API + portal + workers + Postgres in one compose stack under `/opt/maemo-compliance`. |
| **In progress** | **`maemo-identity`** — standalone .NET 8 service with its own DB, GHCR image, and GitHub Actions deploy to `/opt/maemo-identity`. |
| **Planned** | `maemo-compliance-engine`, `maemo-workers`, `maemo-portal`, `maemo-admin`, `maemo-public` as separate repos (see blueprint). |

This document lists **repos**, **server paths**, **ports**, **secrets**, **CI/CD**, and **deploy order** for the full program and what is implemented **now**.

---

## 2. Architecture (target)

```
Internet
    │
    ├── maemo-compliance.co.za          → maemo-public        (port 3010, nginx)
    ├── app.maemo-compliance.co.za    → maemo-portal        (port 3020, nginx)
    ├── api.maemo-compliance.co.za    → maemo-compliance-engine (8090) OR monolith API (cutover)
    ├── api.maemo-identity.co.za      → maemo-identity      (port 8100, nginx)
    └── admin.maemo-compliance.co.za  → maemo-admin         (3030, VPN/SSH only — not public nginx)

Internal only (never expose via public nginx):
    /internal/* on maemo-identity — X-Service-Key
```

**Auth flow (target):** Portal and engine validate JWTs from **maemo-identity** (issuer `maemo-identity`, audience `maemo-compliance`). Engine does **not** store passwords.

---

## 3. GitHub repositories

Create each repo as **Private**, default branch **`main`**, Actions **Read and write** (for GHCR).

| Repo | Purpose | Status (Jun 2026) |
|------|---------|-------------------|
| `codist-pty-ltd/maemo-identity` | Auth, tenants, users, invites, access requests | **CI + deploy** — cutover in progress |
| `codist-pty-ltd/maemo-compliance-engine` | Compliance domain API | **CI + deploy** — parallel to monolith API |
| `codist-pty-ltd/maemo-workers` | Background workers | **CI + deploy** — checks out engine in workflow |
| `codist-pty-ltd/maemo-portal` | Tenant Angular SPA | **CI + deploy** |
| `codist-pty-ltd/maemo-admin` | Internal admin UI | **CI + deploy** |
| `codist-pty-ltd/maemo-public` | Marketing site | **CI + deploy** |
| `codist-pty-ltd/maemo-compliance` | **Legacy monolith** — API + portal + workers | **Production** until cutover |

> **GHCR:** All images use `ghcr.io/codist-pty-ltd/<repo>:latest`. See [MAEMO_REPOS_AND_CI.md](./MAEMO_REPOS_AND_CI.md) for secrets and server paths.

---

## 4. Production server (Hetzner)

| Item | Value |
|------|--------|
| **Host** | `65.109.7.45` (per project rules / blueprint) |
| **OS user (examples)** | `maemo-identity`, `maemo-portal`, `maemo-admin`, `maemo-public`, plus existing **`billable`** or compliance deploy user for monolith |

### 4.1 Directory layout (per service)

| Service | UNIX user (Phase 0) | App checkout | Env file | Notes |
|---------|---------------------|--------------|----------|--------|
| **maemo-identity** | `maemo-identity` | `/opt/maemo-identity/app` | `/opt/maemo-identity/app/.env` (or bootstrap via CI) | Compose in `app/` |
| **Monolith (current)** | (your deploy user) | `/opt/maemo-compliance/app` | `/opt/maemo-compliance/.env` | **Not** inside `app/` — env one level up |
| **maemo-portal** (future) | `maemo-portal` | `/opt/maemo-portal/app` | — | Static nginx image |
| **maemo-admin** (future) | `maemo-admin` | `/opt/maemo-admin/app` | — | SSH tunnel to `127.0.0.1:3030` |
| **maemo-public** (future) | `maemo-public` | `/opt/maemo-public/app` | — | Port `3010` |

### 4.2 Loopback ports (nginx upstreams)

| Service | Container port | Host bind | Public hostname |
|---------|----------------|-----------|-----------------|
| maemo-identity API | 8080 | `127.0.0.1:8100` | `api.maemo-identity.co.za` |
| Compliance API (monolith or engine) | 8080 | `127.0.0.1:8090` | `api.maemo-compliance.co.za` |
| Portal (monolith or maemo-portal) | 80 | `127.0.0.1:3020` | `app.maemo-compliance.co.za` |
| Public site (future) | 80 | `127.0.0.1:3010` | `maemo-compliance.co.za` |
| Admin (future) | 80 | `127.0.0.1:3030` | Restricted — no public proxy |

**Rule:** Only **nginx** (or VPN) faces the internet; APIs bind to **127.0.0.1**.

---

## 5. DNS & TLS (Phase 0)

Add **A records** → `65.109.7.45` (adjust if IP changes):

| Hostname | Points to service |
|----------|-------------------|
| `maemo-compliance.co.za` | maemo-public (after cutover) or legacy portal |
| `app.maemo-compliance.co.za` | Tenant portal |
| `api.maemo-compliance.co.za` | Compliance API |
| `api.maemo-identity.co.za` | Identity API |
| `admin.maemo-compliance.co.za` | Admin (optional; prefer VPN only) |

**TLS example (Certbot + nginx):**

```bash
sudo certbot --nginx \
  -d app.maemo-compliance.co.za \
  -d api.maemo-identity.co.za \
  -d admin.maemo-compliance.co.za \
  --non-interactive --agree-tos \
  -m admin@maemo-compliance.co.za
```

**Nginx (identity example):**

```nginx
server {
    server_name api.maemo-identity.co.za;
    location / {
        proxy_pass http://127.0.0.1:8100;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Do **not** proxy `/internal/*` to the public internet.

---

## 6. Deploy order (full program)

1. **Phase 0** — Repos, DNS, server users, deploy keys, TLS, GHCR permissions.  
2. **maemo-identity** — Deploy + migrate DB + smoke tests (`/health/live`, register/login).  
3. **maemo-compliance-engine** (or keep monolith API) — JWT validation against identity; tenant isolation tests.  
4. **maemo-workers** — Same DB/network as engine; no HTTP.  
5. **maemo-portal** — Point `identityApiUrl` + `engineApiUrl` at production APIs.  
6. **maemo-public** — Marketing + contact → identity public APIs.  
7. **maemo-admin** — Admin APIs + SSH tunnel only.  
8. **Cutover** — Switch nginx/DNS; stop monolith after soak period.

---

## 7. maemo-identity (detailed — implemented)

### 7.1 Repository layout (local / server `app/`)

```
maemo-identity/
├── MaemoIdentity.sln
├── src/
│   ├── MaemoIdentity.Api/          # Host, Program.cs, Dockerfile
│   ├── MaemoIdentity.Application/  # MediatR, validators
│   ├── MaemoIdentity.Domain/
│   └── MaemoIdentity.Infrastructure/  # EF, migrations, email, JWT
├── tests/
│   ├── MaemoIdentity.UnitTests/
│   └── MaemoIdentity.IntegrationTests/
├── docker-compose.prod.yml
├── .env.example
├── .github/workflows/ci.yml
└── .cursorrules
```

### 7.2 Database

| Item | Value |
|------|--------|
| Engine | PostgreSQL 16 (container `maemo-identity-postgres`) |
| Database name | `maemo_identity` |
| User | `maemo_identity` |
| Connection (in container network) | `Host=maemo-identity-postgres;Port=5432;Database=maemo_identity;...` |

**Migrations:** Run from SDK on server or CI — **not** inside the slim production API image:

```bash
dotnet ef database update \
  --project src/MaemoIdentity.Infrastructure/MaemoIdentity.Infrastructure.csproj \
  --startup-project src/MaemoIdentity.Api/MaemoIdentity.Api.csproj
```

Use connection string pointing at `maemo-identity-postgres` when running from a one-off SDK container on the same Docker network.

### 7.3 Runtime configuration (`.env`)

Copy from `.env.example`. Keys use ASP.NET Core `__` for nesting:

| Variable | Required | Description |
|----------|----------|-------------|
| `ConnectionStrings__IdentityDatabase` | Yes | Npgsql connection string |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | Yes | Postgres container |
| `Jwt__SigningKey` | Yes | **≥ 32 characters** — signs all JWTs |
| `Jwt__Issuer` | Yes | `maemo-identity` |
| `Jwt__Audience` | Yes | `maemo-compliance` |
| `Resend__ApiKey` | No* | Email via Resend; empty → log-only sender |
| `Resend__FromAddress` | Yes | e.g. `admin@maemo-compliance.co.za` |
| `InternalService__ServiceKey` | Yes for `/internal/*` | Shared secret for service-to-service |
| `AdminApi__Key` | Recommended | `X-Admin-Key` for admin routes without platform JWT |
| `App__PublicPortalUrl` | Optional | Links in emails (default production portal URL) |

\* Without Resend, verification emails appear in API logs only.

**Never commit `.env` or real keys to git.** Rotate any key that was ever committed.

### 7.4 Docker (production)

```bash
cd /opt/maemo-identity/app
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
curl -fsS http://127.0.0.1:8100/health/live
```

Image (align with your GHCR org):

- `ghcr.io/<org>/maemo-identity:latest`

If the package is **private**, on the server once:

```bash
echo "<GITHUB_PAT_with_read:packages>" | docker login ghcr.io -u <github-user> --password-stdin
```

### 7.5 GitHub Actions — `maemo-identity`

**File:** `.github/workflows/ci.yml`

| Job | When | What |
|-----|------|------|
| `unit` | Every push / PR | `dotnet test` unit tests |
| `integration` | Every push / PR | Integration tests (Testcontainers; `TESTCONTAINERS_RYUK_DISABLED=true`) |
| `build-push` | Push to **`main` only** | Build Dockerfile → push GHCR |
| `deploy` | After `build-push` on **`main`** | SSH deploy script |

**Deploy step (summary):**

1. SSH as `maemo-identity` using Actions secrets.  
2. Clone/pull repo into `/opt/maemo-identity/app` via `git@github.com:<org>/maemo-identity.git` (deploy key at `~/.ssh/deploy_key`).  
3. If `.env` missing → create from bootstrap secrets (see below).  
4. `docker compose pull && up -d`  
5. `curl http://127.0.0.1:8100/health/live`

#### GitHub repository secrets (maemo-identity)

**Settings → Secrets and variables → Actions**

| Secret | Required for deploy | Purpose |
|--------|---------------------|---------|
| `MAEMO_IDENTITY_SSH_HOST` | Yes | e.g. `65.109.7.45` |
| `MAEMO_IDENTITY_SSH_USER` | Yes | e.g. `maemo-identity` |
| `MAEMO_IDENTITY_SSH_KEY` | Yes | **Full private key** PEM (`BEGIN OPENSSH PRIVATE KEY` … `END`). This is for **Actions → server SSH**, not the `.pub` deploy key. |
| `MAEMO_IDENTITY_POSTGRES_PASSWORD` | First deploy only* | Bootstrap `.env` Postgres password |
| `MAEMO_IDENTITY_JWT_SIGNING_KEY` | First deploy only* | Bootstrap JWT signing key (≥ 32 chars) |
| `MAEMO_IDENTITY_INTERNAL_SERVICE_KEY` | Optional | Bootstrap internal API key |
| `MAEMO_IDENTITY_ADMIN_API_KEY` | Optional | Bootstrap admin API key |
| `MAEMO_IDENTITY_RESEND_API_KEY` | Optional | Bootstrap Resend |

\* If `.env` already exists on the server, bootstrap secrets are ignored for file creation (file is not overwritten).

**GitHub Deploy key (separate from SSH_KEY):**

- Repo → **Settings → Deploy keys** → add **`deploy_key.pub`** from server user.  
- Allows `git clone` / `git pull` on the server.  
- Does **not** replace `MAEMO_IDENTITY_SSH_KEY` unless you intentionally use the same key for both (not recommended).

**Environment secrets warning:** If you use GitHub **Environments** (e.g. `production`), blank environment secrets **override** repository secrets and break deploy. Either set real values on the environment or remove empty environment secrets.

#### SSH key checklist

| Mistake | Symptom |
|---------|---------|
| Pasted `.pub` into `MAEMO_IDENTITY_SSH_KEY` | `ssh: no key found` |
| Truncated / one-line private key | Parse or auth failure |
| Wrong user in `authorized_keys` | `unable to authenticate` |

### 7.6 Server user setup (one-time, Phase 0)

```bash
sudo useradd -m -s /bin/bash maemo-identity
sudo usermod -aG docker maemo-identity
sudo mkdir -p /opt/maemo-identity
sudo chown maemo-identity:maemo-identity /opt/maemo-identity

sudo -u maemo-identity ssh-keygen -t ed25519 -C "maemo-identity@codist" \
  -f /home/maemo-identity/.ssh/deploy_key -N ""
# Add deploy_key.pub to GitHub Deploy keys; append pub to authorized_keys if needed for git
```

### 7.7 Test users (identity)

Identity does **not** ship seed users. Use:

1. **Register** — `POST /api/auth/register` (Starter or Growth) or portal signup when live.  
2. **Verify email** — Resend or read `EmailVerificationToken` from DB if logging sender.  
3. **Tenant admin / “tester”** — First registered user is **Admin** (`Role = 2`) for that tenant.  
4. **Platform admin** — SQL once: `UPDATE "Users" SET "Role" = 3 WHERE LOWER("Email") = 'you@example.com';` then log in again for `/admin/v1/*`.  
   Or call admin routes with header **`X-Admin-Key`** matching `AdminApi__Key`.

**Roles:** `0` Viewer, `1` Manager, `2` Admin, `3` PlatformAdmin.

### 7.8 Smoke tests (identity)

```bash
curl -fsS https://api.maemo-identity.co.za/health/live
curl -fsS https://api.maemo-identity.co.za/health/ready
```

Register → verify → login → `GET /api/auth/me` with `Authorization: Bearer <token>`.

---

## 8. Legacy monolith — `maemo` (production today)

### 8.1 Repository layout

```
maemo/
├── MaemoCompliance.sln
├── MaemoCompliance.Api/
├── frontend/                    # Angular portal (built into portal image)
├── docker/
│   ├── Dockerfile.api
│   ├── Dockerfile.portal
│   └── Dockerfile.workers
├── docker-compose.prod.yml
├── .env.example
└── .github/workflows/ci.yml
```

### 8.2 Production paths

| Path | Purpose |
|------|---------|
| `/opt/maemo-compliance/app` | Git checkout (compose file lives here) |
| `/opt/maemo-compliance/.env` | **Production env** (referenced by compose `--env-file`) |

### 8.3 Compose services

| Service | Image | Host port |
|---------|-------|-----------|
| `postgres` | `postgres:16-alpine` | internal only |
| `api` | `ghcr.io/codist-pty-ltd/maemo-compliance-api:latest` | `127.0.0.1:8090` |
| `workers` | `ghcr.io/codist-pty-ltd/maemo-compliance-workers:latest` | none |
| `frontend` | `ghcr.io/codist-pty-ltd/maemo-compliance-portal:latest` | `127.0.0.1:3020` |

**Deploy command (on server):**

```bash
cd /opt/maemo-compliance/app
git pull origin main
docker login ghcr.io   # if images are private
docker compose --env-file /opt/maemo-compliance/.env -f docker-compose.prod.yml pull
docker compose --env-file /opt/maemo-compliance/.env -f docker-compose.prod.yml up -d --remove-orphans
curl -f http://localhost:8090/health/live
```

### 8.4 Monolith `.env` (see `.env.example`)

| Variable | Purpose |
|----------|---------|
| `ConnectionStrings__MaemoDatabase` | `Host=postgres;...` (service name **`postgres`** in compose) |
| `POSTGRES_*` | Database bootstrap |
| `AZURE_AUTHORITY` / `AZURE_AUDIENCE` / `AZURE_CLIENT_ID` | Microsoft login |
| `Resend__ApiKey` / `Resend__FromAddress` | Email |
| `App__PublicPortalUrl` | Links in emails |
| `Storage__LocalBasePath` | Uploaded files volume |
| `Admin__DemoSeedApiKey` | Optional demo |

### 8.5 GitHub Actions — monolith (`maemo`)

**File:** `.github/workflows/ci.yml`

| Job | Purpose |
|-----|---------|
| `unit` / `integration` | .NET tests |
| `frontend` | `npm run build` in `frontend/` |
| `playwright-smoke` | Optional; needs staging URL secrets |
| `docker-build` | Push API, portal, workers images to GHCR |
| `deploy` | SSH to server, compose pull/up, health check |

#### GitHub secrets (monolith)

| Secret | Purpose |
|--------|---------|
| `MAEMO_COMPLIANCE_SSH_HOST` | Server IP/hostname |
| `MAEMO_COMPLIANCE_SSH_USER` | SSH user with access to `/opt/maemo-compliance` |
| `MAEMO_COMPLIANCE_SSH_KEY` | Full **private** key for SSH (preflight checks format in workflow) |
| `MAEMO_COMPLIANCE_STAGING_URL` | Optional — Playwright smoke |
| `MAEMO_COMPLIANCE_API_STAGING_URL` | Optional — Playwright smoke |

Uses built-in `GITHUB_TOKEN` for GHCR push on `main`.

---

## 9. Future services (blueprint — not yet separate deploys)

Use the **same pattern** as identity for each new repo when implemented:

| Service | GHCR image (planned) | Port | Deploy user | GitHub secrets pattern |
|---------|----------------------|------|-------------|-------------------------|
| maemo-compliance-engine | `maemo-compliance-engine` | 8090 | TBD | `MAEMO_ENGINE_SSH_*` + DB/JWT/identity URL |
| maemo-workers | `maemo-workers` | — | TBD | `MAEMO_WORKERS_SSH_*` + engine DB connection |
| maemo-portal | `maemo-portal` | 3020 | `maemo-portal` | `MAEMO_PORTAL_SSH_*` + build-time API URLs |
| maemo-public | `maemo-public` | 3010 | `maemo-public` | `MAEMO_PUBLIC_SSH_*` |
| maemo-admin | `maemo-admin` | 3030 | `maemo-admin` | `MAEMO_ADMIN_SSH_*` + admin keys |

**Engine-specific (when split):**

- `Identity__Authority=https://api.maemo-identity.co.za`  
- Validate JWT audience `maemo-compliance`  
- **Never** expose engine admin routes without auth  
- **Tenant isolation** enforced in EF global query filters  

---

## 10. Keys & secrets matrix (quick reference)

| Secret / key | Where stored | Used by |
|--------------|--------------|---------|
| SSH deploy private key | GitHub Actions `MAEMO_*_SSH_KEY` | CI → server SSH |
| Git deploy key (pub on GitHub) | Server `~/.ssh/deploy_key` | `git pull` on server |
| Postgres password | Server `.env` + optional Actions bootstrap | Compose + API |
| JWT signing key | Identity `.env` / `MAEMO_IDENTITY_JWT_SIGNING_KEY` | Identity tokens; engine must trust same secret or JWKS |
| Internal service key | Identity `.env` | `X-Service-Key` on `/internal/*` |
| Admin API key | Identity `.env` | `X-Admin-Key` on `/admin/v1/*` |
| Resend API key | `.env` per service | Outbound email |
| GHCR PAT | Server `docker login` (manual or deploy script) | Pull private images |
| Azure AD app registration | Monolith `.env` (until portal uses identity MSAL only) | Microsoft login |

---

## 11. Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| No workflow runs | Invalid `ci.yml` or Actions disabled | Fix YAML; enable Actions |
| `Unrecognized named-value: secrets` in `if` | `secrets.*` in job-level `if` | Use `env:` mapping + `env.*` in step `if` (identity pattern) |
| `missing server host` | Empty `MAEMO_*_SSH_HOST` | Set repo secret; check Environment override |
| `ssh: no key found` | Wrong key in `SSH_KEY` secret | Full private PEM |
| `cd: /opt/.../app: No such file` | First deploy | CI clone/bootstrap (identity) or mkdir + clone manually |
| `.env` missing | First deploy | Create from `.env.example` or set bootstrap Actions secrets |
| GHCR pull 401 | Private package | `docker login ghcr.io` on server |
| Image tag mismatch | workflow vs compose vs server pull | Use `ghcr.io/codist-pty-ltd/*` everywhere |
| Health check fails after up | DB migration not applied, bad JWT key length, Postgres not healthy | Logs: `docker compose logs`; run EF migrate |

---

## 12. Return checklist (per phase)

Hand this to whoever verifies a phase:

**Phase 1 — Identity**

- [ ] `curl https://api.maemo-identity.co.za/health/live` → 200  
- [ ] Register → verify → login works  
- [ ] `dotnet test` green on `main`  
- [ ] GHCR image exists; server containers healthy  
- [ ] `/internal/*` not reachable from public internet  

**Phase 2 — Engine**

- [ ] `curl https://api.maemo-compliance.co.za/health/live` → 200  
- [ ] JWT from identity accepted; tenant B cannot read tenant A document (404)  

**Phase 3 — Portal**

- [ ] `curl -sI https://app.maemo-compliance.co.za` → 200  
- [ ] Login → dashboard with PrimeNG UI  

**Phase 4–6 — Public, workers, admin**

- Per blueprint smoke tests and worker heartbeat logs  

---

## 13. Document maintenance

When you change org name, server IP, ports, or secret names, update this file and the service’s `.cursorrules` / `.env.example` in the same PR.

**Last reviewed against:** `maemo-identity` CI workflow, `maemo` `docker-compose.prod.yml` and CI workflow, `MAEMO_DECOUPLING_BLUEPRINT.md`.
