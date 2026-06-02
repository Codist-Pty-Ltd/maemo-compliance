# Maemo repositories and CI

Split services live under **Codist-Pty-Ltd** on GitHub. Container images publish to **GHCR** as `ghcr.io/codist-pty-ltd/<repo>:latest`.

## Repository map

| Service | GitHub repo | Local folder | Server path | Loopback port |
|---------|-------------|--------------|-------------|---------------|
| Identity | [maemo-identity](https://github.com/Codist-Pty-Ltd/maemo-identity) | `maemo-identity` | `/opt/maemo-identity/app` | 8100 |
| Compliance engine | [maemo-compliance-engine](https://github.com/Codist-Pty-Ltd/maemo-compliance-engine) | `maemo-compliance-engine` | `/opt/maemo-compliance-engine/app` | 8090 |
| Workers | [maemo-workers](https://github.com/Codist-Pty-Ltd/maemo-workers) | `maemo-workers` | `/opt/maemo-workers/app` | (none) |
| Tenant portal | [maemo-portal](https://github.com/Codist-Pty-Ltd/maemo-portal) | `maemo-portal` | `/opt/maemo-portal/app` | 3020 |
| Public site | [maemo-public](https://github.com/Codist-Pty-Ltd/maemo-public) | `maemo-public` | `/opt/maemo-public/app` | 3010 |
| Admin UI | [maemo-admin](https://github.com/Codist-Pty-Ltd/maemo-admin) | `maemo-admin` | `/opt/maemo-admin/app` | 3030 |
| Legacy monolith | [maemo-compliance](https://github.com/Codist-Pty-Ltd/maemo-compliance) | `maemo` (this repo) | `/opt/maemo-compliance/app` | 8090 / 3020 |

**Production today:** the **maemo-compliance** monolith stack still serves live traffic. Other repos can deploy in parallel; cut over nginx host-by-host when each stack is verified.

## GitHub Actions (each repo)

Workflow file: `.github/workflows/ci.yml`

| Repo | Jobs | Deploy secrets (optional; skip deploy if empty) |
|------|------|--------------------------------------------------|
| maemo-identity | unit, integration, build-push, deploy | `MAEMO_IDENTITY_SSH_*`, `MAEMO_IDENTITY_POSTGRES_PASSWORD`, `MAEMO_IDENTITY_JWT_SIGNING_KEY` |
| maemo-compliance-engine | unit, integration, build-push, deploy | `MAEMO_COMPLIANCE_ENGINE_SSH_*` |
| maemo-workers | build (+ engine checkout), build-push, deploy | `MAEMO_WORKERS_SSH_*` |
| maemo-portal | npm build, build-push, deploy | `MAEMO_PORTAL_SSH_*` |
| maemo-public | npm build, build-push, deploy | `MAEMO_PUBLIC_SSH_*` |
| maemo-admin | npm build, build-push, deploy | `MAEMO_ADMIN_SSH_*` |
| maemo-compliance | unit, integration, frontend, docker-build, deploy | `MAEMO_COMPLIANCE_SSH_*` (existing) |

Workers CI checks out **maemo-compliance-engine** into `maemo-compliance-engine/` so Docker and `dotnet build` work in an isolated repo.

## GHCR and server login

1. In each GitHub repo: **Settings → Actions → General → Workflow permissions** → read/write packages.
2. Make package **public** or grant the server user `docker login ghcr.io` with a PAT that has `read:packages`.
3. After renaming images from `ntokyb` to `codist-pty-ltd`, run `docker compose pull` on the server once CI has pushed new tags.

## DNS (your records → nginx upstream)

| Host | Upstream (loopback) |
|------|---------------------|
| `identity.maemo-compliance.co.za` | `127.0.0.1:8100` |
| `api.maemo-compliance.co.za` | `127.0.0.1:8090` (monolith or engine after cutover) |
| `app.maemo-compliance.co.za` | `127.0.0.1:3020` |
| `admin.maemo-compliance.co.za` | `127.0.0.1:3030` |
| `maemo-compliance.co.za` (apex) | `127.0.0.1:3010` |

## Push checklist (per repo)

```bash
cd /path/to/repo
git remote -v   # should point at git@github.com:Codist-Pty-Ltd/<name>.git
git add .github docker-compose.prod.yml   # and other changes
git commit -m "Add CI and production compose for Codist GHCR"
git push origin main
```

Then in GitHub: add SSH secrets, watch Actions, on server create `.env` from `.env.example` before first deploy (identity can bootstrap from Actions secrets).

## Local dev: maemo-workers + engine

```bash
cd maemo-workers
git clone git@github.com:Codist-Pty-Ltd/maemo-compliance-engine.git maemo-compliance-engine
# or: mklink /J maemo-compliance-engine ..\maemo-compliance-engine   (Windows)
dotnet build src/MaemoWorkers/MaemoWorkers.csproj -c Release
```

See also [MAEMO_DEPLOYMENT_GUIDE.md](./MAEMO_DEPLOYMENT_GUIDE.md).
