# Maemo Compliance — Decoupling Blueprint

**Inputs:** `.cursorrules`, `docs/MAEMO_AUDIT_REPORT.md`, `docs/MAEMO_UI_AUDIT_REPORT.md`, EF model (`MaemoComplianceDbContext` + snapshot).  
**Goal:** Standalone deployable services — **one GitHub repo each**, **own CI/CD**, **independent releases**, **Hetzner-first** (per project rules).  
**Date:** 2026-05-12  

---

## Architecture (ASCII)

```
                         Internet
                             │
              ┌──────────────┴──────────────┐
              │                             │
        maemo-compliance.co.za        app.maemo-compliance.co.za
        (maemo-public)                 (maemo-portal, static/nginx)
              │                             │
              │  signup/contact        ┌────┴────────────────────┐
              │                         │   Browser calls APIs     │
              └──────────┬─────────────┴───────────┬──────────────┘
                         │                         │
                         ▼                         ▼
              api.maemo-identity.co.za     api.maemo-compliance.co.za
              (maemo-identity)              (maemo-compliance-engine)
                         │                         │
                         │  JWT + JWKS            │  validates JWT
                         │  internal HTTP         │  internal HTTP
                         └────────────┬────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              ┌──────────┐    ┌──────────────┐  ┌──────────────┐
              │ Identity │    │ Compliance   │  │ Workers      │
              │ Postgres │    │ Postgres     │  │ (no HTTP)    │
              └──────────┘    └──────────────┘  └──────┬───────┘
                    ▲                ▲                  │
                    │                └──────────────────┘
                    │              same DB *see note*
  admin.maemo-compliance.co.za (VPN / IP allowlist)
        (maemo-admin: thin UI + BFF or direct API calls)
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   maemo-identity           maemo-compliance-engine
   /admin/v1/* (optional)      platform admin API slice
```

**Workers vs database (design choice):**

- **Target end-state:** `maemo-workers` has **no public HTTP**; it uses the **compliance-engine database** for domain state it mutates (e.g. retention, outbox) **or** a dedicated **`maemo-workers` schema** on the **same PostgreSQL instance** as the engine (still “one logical DB cluster” operationally) to avoid cross-service transactions.
- **Strict interpretation of “own PostgreSQL” for engine:** Workers remain a **separate deployable repo** but **document explicit allowed coupling:** shared Postgres instance, **engine-owned tables only**; workers are **not** second owners of tables.

---

## TASK 1 — Define the services

### Responsibility matrix

| Service | Repo (`ntokyb/*`) | Responsible for | **Not** responsible for |
|--------|-------------------|-----------------|-------------------------|
| **maemo-identity** | `maemo-identity` | Users, credentials (local), email verification, password reset, **tenant lifecycle** (create/suspend), **invitations**, **access requests** (Growth pipeline), **JWT issuance**, **tenant/user directory claims** for tokens, public signup validation, optional **MSAL federation mapping** | Documents, NCRs, risks, audits, compliance workflows, file storage, engine API keys |
| **maemo-compliance-engine** | `maemo-compliance-engine` | Documents (+ versions, workflow, POPIA trail), NCRs, risks, audits/templates/runs, departments, webhooks, engine API keys, **consultant data plane** (client-scoped operations), billing webhooks **if tied to tenant usage**, **operational logs** (API/errors/webhooks) | User password store, raw invitation token storage for IdP, platform-wide tenant CRUD that belongs in identity |
| **maemo-workers** | `maemo-workers` | Background jobs: email queue consumers, retention workers, scheduled sweeps, heartbeat, **outbox** dispatch | Public REST surface |
| **maemo-admin** | `maemo-admin` | **Codist-internal** UI + minimal API/BFF: access requests, tenant ops, logs, worker visibility | Core compliance CRUD (delegates to engine); auth source (delegates to identity) |
| **maemo-portal** | `maemo-portal` | **Tenant-facing** Angular SPA (static), MSAL + local JWT client, module-gated UX | Business logic; file storage |
| **maemo-public** | `maemo-public` | **Marketing** pages, `/contact`-style forms, static **OpenAPI/docs** links, SEO | Authenticated app features |

### Per-service deployment card

| Service | Stack | Hetzner target | Port (example) | Domain / URL | Database |
|--------|-------|----------------|----------------|--------------|----------|
| **maemo-identity** | .NET 8, EF Core, PostgreSQL, MediatR | Same billable server or dedicated VM later | `8100` internal | `https://api.maemo-identity.co.za` | **Own** PostgreSQL (`maemo_identity`) |
| **maemo-compliance-engine** | .NET 8, EF Core, PostgreSQL, MediatR | Same server | `8090` internal | `https://api.maemo-compliance.co.za` (path `/` + `/engine/v1` as today **or** `https://engine.maemo-compliance.co.za`) | **Own** PostgreSQL (`maemo_compliance`) |
| **maemo-workers** | .NET 8 worker host | Same server | *none* | *none* | **Uses engine DB** (see note) |
| **maemo-admin** | Angular (+ optional small .NET BFF) | Same server; **IP allowlist / VPN** | `3030` | `https://admin.maemo-compliance.co.za` | **No** primary DB; optional cache |
| **maemo-portal** | Angular, nginx | Same server | `3020` | `https://app.maemo-compliance.co.za` | None |
| **maemo-public** | Next.js (SSG/ISR) **or** static HTML | Same server or Vercel-like (project rule: **prefer Hetzner**) | `3010` | `https://maemo-compliance.co.za` | None (form posts to identity or serverless edge function calling identity) |

### Consumes / exposes

| Service | Consumes (outbound) | Exposes (inbound) |
|--------|---------------------|-------------------|
| **maemo-identity** | Email provider (Resend); optional Entra metadata | **Public:** register, login, verify, forgot/reset, me; **Internal:** tenant/user resolution, JWKS |
| **maemo-compliance-engine** | **maemo-identity:** validate JWT (local), **optional** `GET /internal/tenants/{id}`, `GET /internal/users/{id}` for staleness checks | **Portal:** `/api/*` compliance surface; **Engine:** `/engine/v1/*`; **Admin:** delegated admin routes or separate `/admin/v1/compliance/*` |
| **maemo-workers** | **maemo-identity** (e.g. “send email” only if not embedded); **SMTP/Resend**; **engine DB** | Nothing |
| **maemo-admin** | **maemo-identity** + **maemo-compliance-engine** (+ identity-admin if split) | Admin UI; optional BFF |
| **maemo-portal** | **maemo-identity** + **maemo-compliance-engine** | Static assets only |
| **maemo-public** | **maemo-identity** (signup/contact) | HTML/JSON static |

---

## TASK 2 — Data ownership map

**Rule:** Each table has **exactly one owner**. Other services use **HTTP APIs** (or async events), **never** direct DB access to another service’s tables.

Tables are from `MaemoComplianceDbContextModelSnapshot` (`ToTable`).

| Table | Owner service | Consumers (how) |
|-------|---------------|-------------------|
| `Users` | **maemo-identity** | Engine: resolve `userId` + roles via JWT claims or `GET /internal/users/{id}` |
| `UserInvitations` | **maemo-identity** | Portal: public validate + authenticated accept via identity API |
| `Tenants` | **maemo-identity** | Engine: `tenantId` in token + `GET /internal/tenants/{id}` for active/modules |
| `TenantSettings` | **maemo-identity** | Engine: `GET /internal/tenants/{id}/settings` or JWT claims for `modulesEnabled` |
| `AccessRequests` | **maemo-identity** | maemo-admin: approve/reject via identity admin API |
| `ConsultantTenantLinks` | **maemo-identity** | Engine: `GET /internal/consultants/...` or claims for consultant client list |
| `WelcomeEmails` | **maemo-identity** | Workers: insert via identity **internal API** or outbox owned by identity |
| `Departments` | **maemo-compliance-engine** | Portal via engine |
| `Documents` | **maemo-compliance-engine** | Portal via engine |
| `DocumentVersions` | **maemo-compliance-engine** | Portal via engine |
| `Ncrs` | **maemo-compliance-engine** | Portal via engine |
| `NcrRiskLinks` | **maemo-compliance-engine** | Portal via engine |
| `NcrStatusHistory` | **maemo-compliance-engine** | Portal via engine |
| `Risks` | **maemo-compliance-engine** | Portal via engine |
| `AuditTemplates` | **maemo-compliance-engine** | Portal via engine |
| `AuditQuestions` | **maemo-compliance-engine** | Portal via engine |
| `AuditRuns` | **maemo-compliance-engine** | Portal via engine |
| `AuditAnswers` | **maemo-compliance-engine** | Portal via engine |
| `AuditFindings` | **maemo-compliance-engine** | Portal via engine |
| `AuditProgrammes` | **maemo-compliance-engine** | Portal via engine |
| `AuditScheduleItems` | **maemo-compliance-engine** | Portal via engine |
| `ApiKeys` | **maemo-compliance-engine** | External integrators via engine |
| `WebhookSubscriptions` | **maemo-compliance-engine** | Engine |
| `WebhookDeliveryLogs` | **maemo-compliance-engine** | maemo-admin via engine reports |
| `ApiCallLogs` | **maemo-compliance-engine** | maemo-admin |
| `ErrorLogs` | **maemo-compliance-engine** | maemo-admin |
| `AuditLogs` | **maemo-compliance-engine** | maemo-admin (read-only API) |
| `BusinessAuditLogs` | **maemo-compliance-engine** | maemo-admin |
| `WorkerJobLogs` | **maemo-compliance-engine** | Written by workers **through engine-owned persistence abstraction** (same DB cluster); maemo-admin reads via engine |

**Cross-cutting implication:** Today `Tenants` holds SharePoint / Azure AD fields used by compliance features. After split, either:

- **Option A (recommended):** Move integration secrets to **identity** `Tenants` + expose `GET /internal/tenants/{id}/integrations` for engine (engine caches).  
- **Option B:** Move SharePoint-specific columns to **engine** table `TenantIntegrations` keyed by `tenantId` (identity remains canonical for tenant existence only).

Pick one before migration; **avoid** two services writing the same logical row.

---

## TASK 3 — API contract between services

### maemo-portal → maemo-identity

Align with current monolith paths **or** version cleanly under `/v1`:

| Operation | Method / path (proposed) | Notes |
|-----------|---------------------------|-------|
| Register | `POST /api/auth/register` | Same body as today |
| Login | `POST /api/auth/login` | Returns JWT + refresh policy |
| Me | `GET /api/auth/me` | |
| Verify email | `POST /api/auth/verify-email` | |
| Resend verification | `POST /api/auth/resend-verification` | |
| Forgot password | `POST /api/auth/forgot-password` | |
| Reset password | `POST /api/auth/reset-password` | |
| Public invite validate | `GET /public/invite/validate` | |
| Accept invitation | `POST /api/tenant/invitations/accept` | **May stay identity-only** |

**CORS:** Identity allows origins: `app.maemo-compliance.co.za`, `maemo-compliance.co.za`, localhost dev.

### maemo-portal → maemo-compliance-engine

- **All** `/api/documents/*`, `/api/ncrs/*`, `/api/risks/*`, `/api/audits/*`, `/api/dashboard/*`, `/api/popiatrail/*`, `/api/consultants/*`, `/api/onboarding/*` (if “compliance” — **or** split onboarding: company wizard steps that touch **only** identity vs engine per domain decision), `/api/tenant/me` **if profile is split** (UI audit shows profile on tenant — candidate for **identity** as `GET /api/users/me/profile`).

**Clarification for migration:** Rename mentally to:

- **Identity:** `/api/identity/...` or keep `/api/auth` + `/api/tenants` (lifecycle).  
- **Engine:** `/api/compliance/...` **or** keep existing `/api/*` on engine host to reduce portal churn.

### maemo-admin → maemo-identity + maemo-compliance-engine

- **Identity:** `/admin/v1/access-requests*`, tenant suspension, user directory overrides.
- **Engine:** `/admin/v1/logs/*`, `/admin/v1/workers/*`, compliance exports.

*(Today’s monolith combines these under one host; split preserves paths via **reverse proxy** routing.)*

### maemo-compliance-engine → maemo-identity (server-to-server)

| Call | Purpose |
|------|---------|
| `GET /internal/tenants/{id}` | Exists, active, plan, modules |
| `GET /internal/users/{id}` | Exists, locked state |
| `POST /internal/token/introspect` | Optional opaque token validation |

**Auth:**

- **User → services:** JWT signed by **maemo-identity** (`iss`, `aud`, `tid`/`tenant_id`, `sub`, roles). **Engine** validates signature using **JWKS** from identity (`GET /.well-known/jwks.json`). Entra tokens: identity issues **Maemo JWT** after federated login **or** engine trusts two issuers (higher operational cost — prefer **one internal JWT**).
- **Service → service:** `X-Maemo-Internal-Secret` or **mTLS** between Docker networks; rotate via secrets manager. **Never** use internal secret from browser.

---

## TASK 4 — Migration path

### Principles

1. **Strangler fig:** Move **traffic** before moving **data**.  
2. **Single write master** per table at any moment (no dual-write without outbox).  
3. **Releases:** each new service gets **its own** `docker-compose.prod.yml` + GH Actions → GHCR.

### Numbered sequence

1. **Document & freeze public API shapes** — OpenAPI for identity + engine slices; add contract tests in monolith.  
2. **Edge routing prep** — nginx on Hetzner gains **location blocks** that can point to **new upstreams** (`identity_upstream`, `engine_upstream`) while default remains monolith.  
3. **Extract maemo-identity (first data split)**  
   - Create `maemo_identity` DB; migrate **Users, Tenants, UserInvitations, AccessRequests, TenantSettings, ConsultantTenantLinks, WelcomeEmails**.  
   - Deploy `maemo-identity` read-only shadow mode: monolith **reads** identity via HTTP for `me`/`login` while still using local DB (compare responses).  
   - Cut writes for auth tables to identity; monolith removes direct EF sets for those entities **or** monolith becomes thin proxy.  
4. **Parallel run** — `/api/auth/*` nginx → identity; other paths → monolith.  
5. **Extract maemo-compliance-engine**  
   - Create `maemo_compliance` DB; migrate remaining tables; remove FKs to `Users`/`Tenants` **replace with** `uuid` references validated via identity API.  
   - Point portal `environment.apiBaseUrl` compliance calls to engine host (path-preserving).  
6. **maemo-workers** — change connection string to engine DB; deploy independent image from `maemo-workers` repo.  
7. **maemo-public** — move marketing routes from Angular `Home/About/Contact` to Next/static; redirect apex → public site; `app.` hosts SPA only.  
8. **maemo-portal** — split repo; nginx serves only SPA; update env for split APIs.  
9. **maemo-admin** — extract `access-requests` + platform tools; IP restrict.  
10. **Decommission monolith** `MaemoCompliance.Api` host once traffic = 0.

### Zero-downtime data migration (outline)

- **Phase:** Online dump or logical replication **per table group** with cutover window **seconds**:  
  - Enable replication / dual-read validation.  
  - Stop writes globally **once** (maintenance banner) **or** use **outbox + consumer** for true ZDT (larger build).  
  - Flip nginx upstream.  
  - Roll back = DNS/nginx pointer only if DB not destroyed.

### Gradual portal API updates

- Introduce `environment.identityUrl` + `environment.complianceUrl` in Angular **before** split; interceptor routes by path prefix.  
- Feature flag: `useSplitApi: boolean` for pilot users.

### Effort per service (indicative person-weeks, one senior full-stack + reviews)

| Service | Effort | Notes |
|---------|--------|------|
| maemo-identity | **8–12** | JWT, Entra bridge, admin APIs, migration |
| maemo-compliance-engine | **12–18** | Largest EF surface, webhooks, files |
| maemo-workers | **2–5** | Wiring + reliability |
| maemo-public | **2–5** | Content + forms |
| maemo-portal | **8–14** | PrimeNG rebuild overlaps |
| maemo-admin | **4–8** | BFF + lockdown |

---

## TASK 5 — PrimeNG migration plan

### Version

- **Current portal:** Angular **~20.2** (`frontend/package.json`).  
- **PrimeNG:** Use **`primeng@20.x` LTS** (Angular 20 compatible). **Verify** peer dependencies at install time — PrimeNG **21.x** may target Angular 21; pin explicitly in `package.json`.  
- **Themes:** `@primeng/themes` with **Aura** preset.

### Theme — Aura + Maemo brand

Per audit/UI direction:

```typescript
// app.config.ts — provideAnimationsAsync()
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
```

```typescript
// e.g. styles entry + preset
import { definePreset } from '@primeng/themes';
import Aura from '@primeng/themes/aura';

export const MaemoPreset = definePreset(Aura, {
  semantic: {
    primary: {
      500: '#0F4C81',
      600: '#0c3e6a',
      700: '#093153'
    }
  }
});
```

**Install (target):**

```bash
npm install primeng @primeng/themes
```

Add PrimeNG **optional** styles per component docs (Aura is preset-driven).

### Pages to rebuild first (highest user impact)

Based on `MAEMO_UI_AUDIT_REPORT.md`:

1. **App shell** — responsive layout, sidebar, unified auth header (local JWT + MSAL), logout.  
2. **Dashboard** — summary cards, onboarding checklist, fix broken POPIA/retention widgets **after** engine API parity.  
3. **Documents list + document form** — tables (`p-table`), file upload (`p-fileupload`), dialogs (`p-dialog`).  
4. **NCR list + offline create** — forms + validation feedback.  
5. **Risk register** — same patterns.  
6. **Tenant settings** — tabs (`p-tabView`), forms.  
7. **Consultant audit run** — stepper/wizard (`p-stepper` / `p-stepperPanel`), file evidence.  
8. **Admin access requests** (if remaining in portal vs `maemo-admin`) — `p-table`, confirm dialogs.

### Component migration table

Current portal uses **custom HTML + SCSS** (no Angular Material). “Migration” = **adopt** PrimeNG primitives:

| Current pattern | PrimeNG target |
|-----------------|----------------|
| Custom tables / lists | `p-table`, `p-datatable` features as needed |
| Custom modals | `p-dialog` |
| Raw inputs | `p-floatlabel` + `p-inputtext`, `p-textarea`, `p-select` / `p-dropdown` |
| Cards / panels | `p-card`, `p-panel` |
| Buttons | `p-button` |
| Toasts | `p-toast` + `MessageService` (replace or wrap custom toast) |
| Progress | `p-progressspinner`, `p-progressbar` |
| Tabs | `p-tabview` |
| Checkboxes / radios | `p-checkbox`, `p-radiobutton` |
| File upload | `p-fileupload` |
| Menus | `p-menu`, `p-tieredmenu` |
| Sidebar layout | `p-sidebar` + flex layout for shell |

---

## TASK 6 — Quality standards checklist (per service)

### Backend (each .NET service)

- [ ] Clean Architecture (Domain / Application / Infrastructure / Api)  
- [ ] MediatR for commands/queries  
- [ ] FluentValidation on inputs  
- [ ] Global exception handler  
- [ ] Correlation ID middleware (`X-Correlation-Id`)  
- [ ] Structured logging (Serilog)  
- [ ] `/health/live` and `/health/ready`  
- [ ] xUnit unit tests  
- [ ] Testcontainers integration tests  
- [ ] Docker + `docker-compose.prod.yml`  
- [ ] GitHub Actions CI/CD → GHCR  
- [ ] `.cursorrules` with **that repo’s** deploy path, domains, migrations, secrets policy  

### Frontend (maemo-portal)

- [ ] PrimeNG + Aura + Maemo primary `#0F4C81`  
- [ ] Loading / error / empty on every route  
- [ ] Responsive from **375px** (sidebar → drawer)  
- [ ] Auth guard on all private routes  
- [ ] HTTP interceptor: Bearer + tenant header  
- [ ] Consistent error toasts  
- [ ] No hardcoded API URLs — `environment*.ts` only  
- [ ] Playwright smoke tests (login, documents list, NCR create stub)  

### Frontend (maemo-public)

- [ ] Lighthouse budget for marketing  
- [ ] No secrets in client  
- [ ] Forms POST to identity or server-side handler  

### maemo-admin

- [ ] IP allowlist / VPN  
- [ ] No public signup of admin users  

---

## DNS / infrastructure changes

| Record | Points to | Purpose |
|--------|-----------|---------|
| `maemo-compliance.co.za` | maemo-public | Marketing |
| `app.maemo-compliance.co.za` | maemo-portal | Angular SPA |
| `api.maemo-compliance.co.za` | maemo-compliance-engine | Compliance API |
| `api.maemo-identity.co.za` | maemo-identity | Auth & tenants |
| `admin.maemo-compliance.co.za` | maemo-admin | Internal admin |
| `engine.maemo-compliance.co.za` | optional second name | If path-splitting avoided |

**TLS:** Extend certbot SANs for `app.`, `api.`, `admin.`, `api.maemo-identity` as added.

**nginx:** One ingress VM can reverse-proxy to multiple Docker networks on **65.109.7.45**; decoupling does **not** require new server day-one.

---

## Repo creation checklist

For each `ntokyb/maemo-*` repo:

1. Create repo from template (`.gitignore`, `LICENSE`, branch protection).  
2. Add `Dockerfile`, `docker-compose.prod.yml`, `.env.example`.  
3. Add `.github/workflows/ci.yml` (build, test, push image).  
4. Add `.cursorrules` (deployment truth for **this** service).  
5. Configure GH secrets for deploy (SSH, registry).  
6. Create GHCR package + workflow permissions.  
7. Document **owned tables** + **OpenAPI** export in `/docs`.  
8. Register **Dependabot** + **CodeQL** if org standard.  
9. Add **migration runbook** (SDK container pattern per `.cursorrules`).  
10. Smoke test: `curl` health + one authenticated API.

---

## Risks & decisions log

| Item | Risk | Mitigation |
|------|------|------------|
| JWT trust between services | Token forgery if misconfigured | JWKS, short TTL, `aud` restriction |
| Tenant module checks | Engine needs fresh module flags | Cache + identity `ETag` or signed claims refresh |
| File storage | Documents binary | Shared volume **or** S3-compatible on Hetzner storage box — **single owner: engine** |
| Duplicate hosts in repo today | `Portal.Api`, `Engine.Api` confusion | Delete/archive after cutover; one canonical OpenAPI each |
| UI audit gaps (broken endpoints) | Split amplifies 404s | Fix parity **before** or **during** engine extract |

---

*End of Maemo Decoupling Blueprint.*
