# Maemo Compliance — Deep Codebase Audit

**Repository:** `c:\projects\codist\maemo`  
**Audit date:** 2026-05-12  
**Scope:** Read-only inventory and architecture assessment derived from repository analysis.  
**Auditor note:** This report does **not** reflect line-by-line reading of every file. The workspace contains **~1,016 tracked source files** (excluding `node_modules`, `bin`, `obj`, and typical build artifacts). Findings combine: directory structure, EF model snapshot, `MaemoCompliance.Api` endpoint maps, `Program.cs` wiring, domain entity list, Angular routes/services sampling, handler sampling (e.g. tenant filtering), and package manifests. Any item not explicitly verified is called out as **inferred** or **not exhaustively traced**.

**Methodology**

| Method | Coverage |
|--------|----------|
| Glob / ripgrep for routes, `Map*`, `DbSet`, `ToTable` | High for API surface and DB tables |
| Read `MaemoComplianceDbContextModelSnapshot` (partial) | Schema columns sampled; full column list per table not pasted |
| Read representative handlers | Tenant filtering pattern confirmed for Documents; not every handler verified |
| Frontend | Routes read; HTTP usage grep partial (~120 matching lines); not every component template checked |

---

## REPORT 1 — PROJECT STRUCTURE

### Top-level layout (major folders)

| Folder | Role |
|--------|------|
| `domain/src/MaemoCompliance.Domain` | Domain entities, enums, `TenantOwnedEntity`, `BaseEntity` |
| `application/src/MaemoCompliance.Application` | MediatR commands/queries, DTOs, validators, application services |
| `application/src/MaemoCompliance.Shared` | Shared contracts (e.g. Engine DTOs) |
| `infrastructure/src/MaemoCompliance.Infrastructure` | EF Core, configurations, migrations, email, multi-tenancy helpers, logging |
| `MaemoCompliance.Api` | **Primary** monolith host: Portal `/api/*`, Public `/public/*` + `/api/auth/*`, Engine `/engine/v1/*`, Admin `/admin/v1/*` |
| `engine/src/MaemoCompliance.Engine.Api` | Separate API host (duplicate stack pattern — same Application/Infrastructure refs) |
| `portal/src/MaemoCompliance.Portal.Api` | Separate Portal API host (parallel to main API) |
| `admin/src/MaemoCompliance.Admin.Api` | Separate Admin API host |
| `workers/src/MaemoCompliance.Workers` | Background worker host |
| `frontend/` | Angular portal SPA + `projects/admin-console` |
| `MaemoCompliance.UnitTests` | xUnit tests (handlers/workflows) |
| `MaemoCompliance.IntegrationTests` | Integration tests with Testcontainers |
| `MaemoCompliance.Engine.Client` | Client library for Engine API |
| `MaemoCompliance.Engine.Sample` | Sample consumer |
| `deploy/`, `docker/`, `nginx/`, `scripts/` | Deployment & ops |
| `templates/` | Markdown/JSON templates (e.g. ISO9001 doc templates) |
| `e2e/` | Playwright or similar E2E (separate `package.json`) |

### ⚠️ PARTIAL OR INCOMPLETE — structure concerns

| Finding | Severity |
|---------|----------|
| **`MaemoCompliance.Api`, `Engine.Api`, `Portal.Api`, `Admin.Api`** share the same domain/application/infrastructure — **natural duplication** of hosts; unclear which is canonical for production without reading deployment manifests end-to-end. | ⚠️ |
| **`TenantQueryInterceptor`** exists under `Infrastructure/Persistence` but **`AddInterceptors` was not found** anywhere in the repo — interceptor appears **unused**; comments in `MaemoComplianceDbContext` still say handlers “MUST use `.ForTenant()`” but **grep shows `.ForTenant(` essentially unused** outside comments. | ❌ Architecture drift / dead code |
| **`find` output** once listed `MaemoCompliance.Api/Maemo.Infrastructure` — **not verified** in this run (glob returned 0 files); may be empty, renamed, or tooling artifact — **worth a manual look**. | ⚠️ |
| **`infrastructure/portal`** under repo root (seen in `find`) — purpose not verified in this audit. | ⚠️ |

### Duplicate / overlapping surfaces

| Area | Notes |
|------|-------|
| Portal REST | Implemented in **`MaemoCompliance.Api/Portal/*`** and mirrored by **`portal/src/MaemoCompliance.Portal.Api`** |
| Engine REST | **`MaemoCompliance.Api/Engine/*`** vs standalone **`MaemoCompliance.Engine.Api`** |
| Signup | **`POST /public/signup`** (legacy `SignupCommand`) vs **`POST /api/auth/register`** (email/password onboarding) |

---

## REPORT 2 — BACKEND API INVENTORY

**Legend:** Status is **best-effort** from static analysis. “UNUSED” = no match in partial frontend grep of `/api/...`; Engine/Admin may still be used by other clients.

**Convention:** “Controller” = **minimal API endpoint group** (there are **no** classic MVC `Controller` classes in `MaemoCompliance.Api` for these modules).

### Global / misc (`MaemoCompliance.Api`)

| Group | Route | Method | Auth (typical) | Purpose | Status |
|------|-------|--------|----------------|--------|--------|
| Health | `/health/live`, `/health/ready` | GET | Anonymous | K8s probes | ✅ COMPLETE AND WORKING |
| Legacy | `/api/health` | GET | Anonymous | Health | ✅ COMPLETE AND WORKING |
| — | `/api/tenants/current` | GET | Unclear / often used with context | Returns current tenant id | ⚠️ PARTIAL OR INCOMPLETE — depends on middleware |
| — | `/api/secure-test` | GET | JWT | Dev smoke test | ⚠️ UNUSED from portal grep |

### Public marketing & access

| Group | Route | Method | Auth | Purpose | Status |
|------|-------|--------|------|---------|--------|
| `PublicMarketingEndpoints` | `/public/contact` | POST | Anonymous | Contact form | ✅ COMPLETE AND WORKING |
| | `/public/request-access` | POST | Anonymous | Access request | ✅ COMPLETE AND WORKING |
| `PublicSignupEndpoints` | `/public/signup` | POST | Anonymous | Legacy self-service signup | ✅ COMPLETE (⚠️ DUPLICATE vs `/api/auth/register`) |
| | `/public/invite/validate` | GET | Anonymous | Invite preview | ✅ COMPLETE AND WORKING |
| `AuthEndpoints` | `/api/auth/register` | POST | Anonymous | Email/password + tenant | ✅ COMPLETE AND WORKING |
| | `/api/auth/verify-email` | POST | Anonymous | Verify + issue JWT | ✅ COMPLETE AND WORKING |
| | `/api/auth/login` | POST | Anonymous | Local login | ✅ COMPLETE AND WORKING |
| | `/api/auth/resend-verification` | POST | Anonymous | Resend email | ✅ COMPLETE AND WORKING |
| | `/api/auth/forgot-password` | POST | Anonymous | Reset flow | ✅ COMPLETE AND WORKING |
| | `/api/auth/reset-password` | POST | Anonymous | Reset password | ✅ COMPLETE AND WORKING |
| | `/api/auth/me` | GET | JWT | Current user | ✅ COMPLETE AND WORKING |

### Portal — `MaemoCompliance.Api/Portal/*`

| File (group prefix) | Example routes | Auth | Tests |
|---------------------|----------------|------|-------|
| `DemoEndpoints` | `/api/demo/tenant`, `/api/demo/seed` | Mixed (`seed` likely restricted) | ❌ Not verified |
| `DashboardEndpoints` | `/api/dashboard/summary`, plus dashboard-related document helpers referenced in code paths | JWT | ❌ |
| `DocumentsEndpoints` | `/api/documents/*`, approvals, upload, download, versions | JWT + policies | ⚠️ Unit tests for **workflow** exist |
| `NcrsEndpoints` | `/api/ncrs/*` | JWT | ⚠️ Partial |
| `RisksEndpoints` | `/api/risks/*` | JWT | ❌ |
| `AuditsEndpoints` | `/api/audits/*` | JWT | ⚠️ Unit tests for audit **programme** |
| `AuditProgrammesEndpoints` | `/api/audit-programmes/*` | JWT | ⚠️ Same |
| `TenantSelfServiceEndpoints` | `/api/tenant/*` (me, onboarding, invite, settings, sharepoint) | JWT + tenant admin where marked | ⚠️ |
| `TenantsEndpoints` | `/api/tenants/*`, provision, connect M365 | JWT + admin policies | ❌ |
| `ConsultantsEndpoints` | `/api/consultants/*` | JWT + consultant policies | ❌ |
| `BillingEndpoints` | `/api/billing/webhook/payfast` | Webhook | ❌ |
| `AuditLogEndpoints` | `/api/auditlogs/*` | `RequireAdminOrTenantAdmin` | ❌ |
| `OnboardingEndpoints` | `/api/onboarding/status`, wizard steps, `/api/onboarding/run` | JWT | ⚠️ Newer wizard wired from Angular |
| `DocumentsEndpoints` (extension) | `/api/popiatrail/*` | JWT | ⚠️ |

**Portal status summary:** ✅ Endpoints are **wired** to `Program.cs` and generally **delegate to MediatR or `IApplicationDbContext`**. Automated **API-level tests** are limited; **handler unit tests** exist for subsets (documents, NCR root cause, audit programme).

### Engine — `/engine/v1/*` (within `MaemoCompliance.Api` and duplicate `Engine.Api`)

| Module | Routes (pattern) | Auth | Purpose |
|--------|------------------|------|---------|
| Documents | CRUD, upload, download, versions | `EngineClients` (JWT or API key) | External / integration API |
| NCRs | CRUD, status, history, risk links | Same | Same |
| Risks | CRUD, NCR linkage | Same | Same |
| Audits | Templates, runs, answers, evidence | Same | Same |
| Tenants | Get/patch tenant, API keys | Same | Same |
| Webhooks | Subscriptions CRUD | Same | Same |
| Consultants | Dashboard, clients | Same | Narrow surface |

**Status:** ✅ **COMPLETE AND WIRED** as code; ⚠️ **DUPLICATE** host project; ⚠️ Portal UI primarily uses **`/api/*`**, not Engine — Engine is **backend-first / integration**.

### Admin — `/admin/v1/*`

| Module | Routes | Auth | Purpose |
|--------|--------|------|---------|
| `AdminDashboardEndpoints` | `/admin/v1/dashboard/summary` | Platform admin (see `AdminV1Endpoints`) | Ops dashboard |
| `AdminTenantEndpoints` | tenants list/detail, branding, SharePoint, license | Platform admin | Tenant admin |
| `AdminAccessRequestEndpoints` | access requests, approve/reject | Platform admin | Growth/access pipeline |
| `AdminWorkersEndpoints` | worker status/history | Platform admin | Workers observability |
| `AdminLogsEndpoints` | business audit logs | Platform admin | Forensics |
| `AdminBillingEndpoints` | billing stubs | Platform admin | Billing |
| `AdminSeedEndpoints` | seed (env-gated) | Platform admin / dev | Seeding |

**Status:** ✅ Implemented; Angular **`access-requests`** uses `/admin/v1/access-requests` (from earlier project knowledge); full admin UI may live in **`frontend/projects/admin-console`** — **not exhaustively audited here**.

### Development

| Route | Purpose | Status |
|-------|---------|--------|
| `/dev/seed-demo` (approx.) / `MapDevelopmentDemoSeedEndpoints` | Demo seed | ⚠️ Development only |

---

## REPORT 3 — DATABASE SCHEMA INVENTORY

### Tables (from EF Core snapshot — `ToTable`)

| Table | Domain entity | Notes |
|-------|---------------|--------|
| `AccessRequests` | `AccessRequest` | Public signup / growth approval |
| `AuditLogs` | `AuditLogEntry` | Immutable-ish audit trail rows |
| `BusinessAuditLogs` | `BusinessAuditLog` | Higher-level business events |
| `AuditAnswers` | `AuditAnswer` | Audit execution |
| `AuditFindings` | `AuditFinding` | Audit findings |
| `AuditProgrammes` | `AuditProgramme` | Audit programme (yearly plan) |
| `AuditQuestions` | `AuditQuestion` | Template questions |
| `AuditRuns` | `AuditRun` | Runs |
| `AuditScheduleItems` | `AuditScheduleItem` | Scheduled items |
| `AuditTemplates` | `AuditTemplate` | Templates |
| `Documents` | `Document` | Document control |
| `DocumentVersions` | `DocumentVersion` | Versioning |
| `ApiCallLogs` | `ApiCallLog` | HTTP logging |
| `ErrorLogs` | `ErrorLog` | Error storage |
| `WebhookDeliveryLogs` | `WebhookDeliveryLog` | Webhook deliveries |
| `WorkerJobLogs` | `WorkerJobLog` | Worker runs |
| `WelcomeEmails` | `WelcomeEmail` | **Write-only audit of welcome sends** (no read API found) |
| `Ncrs` | `Ncr` | NCR |
| `NcrRiskLinks` | `NcrRiskLink` | NCR–Risk |
| `NcrStatusHistory` | `NcrStatusHistory` | History |
| `Risks` | `Risk` | Risk register |
| `ApiKeys` | `ApiKey` | Engine API keys |
| `Departments` | `Department` | Org structure |
| `Tenants` | `Tenant` | Workspace |
| `TenantSettings` | `TenantSettings` | Key-value settings |
| `ConsultantTenantLinks` | `ConsultantTenantLink` | Consultant assignments |
| `Users` | `User` | Users + local auth fields (migration added) |
| `UserInvitations` | `UserInvitation` | Invites |
| `WebhookSubscriptions` | `WebhookSubscription` | Webhooks |

### Flags

| Flag | Detail |
|------|--------|
| 🗑️ **WelcomeEmails** | ⚠️ **No read/list endpoint** located — table is **write-oriented** / ops-only unless Admin has hidden query (not found in grep). |
| 📋 **Indexes** | Snapshot shows multiple indexes (e.g. `AuditLogs` composite). **Not audited** table-by-table for missing FK indexes — **manual pass recommended**. |
| 🔒 **Soft delete** | ⚠️ No uniform **soft-delete** pattern observed at domain level; entities use `IsActive` / workflow states **ad hoc**. |
| ❓ **Dev data** | “Has data in dev” **not verified** (no DB connection run). |

### Relationships

- **Tenant-scoped** entities inherit or carry `TenantId`; **`TenantOwnedEntity`** exists for shared pattern.
- **`AccessRequests.CreatedTenantId`** links to pre-provisioned tenant (Growth flow).

---

## REPORT 4 — DOMAIN AND BUSINESS LOGIC

### Domain entities (files under `domain/src/MaemoCompliance.Domain`)

| Entity | Business case | End-to-end | UI | Tests |
|--------|---------------|------------|-----|-------|
| `Document`, `DocumentVersion` | ISO document control | ✅ Typical | ✅ Documents UI | ✅ Workflow tests |
| `Ncr`, `NcrStatusHistory`, `NcrRiskLink` | CAPA / NCR | ✅ | ✅ NCR UI | ⚠️ Root cause tests |
| `Risk` | Risk register | ✅ | ✅ Risks UI | ❌ Not seen |
| Audit * | Internal/ISO audits | ✅ | ✅ Consultant audit UI | ⚠️ Programme tests |
| `Tenant`, `TenantSettings`, `Department` | Multi-tenant workspace | ✅ | ✅ Settings / admin | ❌ |
| `User`, `UserInvitation` | Identity & onboarding | ✅ | ✅ Signup/login/invite | ❌ |
| `AccessRequest` | Sales/growth pipeline | ✅ | ✅ Access requests (admin) | ❌ |
| `ApiKey`, `WebhookSubscription` | Engine integration | ✅ API | ⚠️ Limited UI | ❌ |
| `ConsultantTenantLink` | Consultant model | ✅ | ✅ Consultant screens | ❌ |
| `WelcomeEmail` | Mail tracking | ⚠️ Backend only | ❌ No UI | ❌ |
| Logging tables | Ops | ⚠️ Backend/admin | ⚠️ Admin logs API | ❌ |

### ❌ BROKEN OR MISSING — “entity with no clear surface”

- **`WelcomeEmail`**: business case = **email audit**, but **no portal feature** to browse sends.
- **`TenantQueryInterceptor`**: **infrastructure artifact** without DI registration — suggests **abandoned automatic tenant filter**; **risk of inconsistent enforcement** if any query omits `TenantId`.

---

## REPORT 5 — FRONTEND INVENTORY

### Router (`frontend/src/app/app.routes.ts`)

| Route pattern | Guard chain | Notes |
|---------------|-------------|--------|
| `''` (home), `about`, `contact`, `signup`, `verify`, `forgot-password`, `reset-password` | None / public | Marketing & auth funnel |
| `login` | None | Local + Microsoft |
| `accept-invite` | None | Invite flow |
| `setup` | `portalAuthGuard`, `tenantGuard` | Company wizard |
| `account-pending` | `portalAuthGuard` | Growth pending |
| `onboarding` | `portalAuthGuard`, `tenantGuard`, `onboardingPageGuard` | User profile wizard |
| Shell `''` (Layout) | `portalAuthGuard`, `tenantGuard`, `companySetupGuard`, `userOnboardingGuard` | Main app |
| `admin/*`, `consultant/*`, CRUD modules | `tenantModuleGuard` / `platformAdminGuard` | Feature modules |

**⚠️ PARTIAL:** Guard order is plausible; **`companySetupGuard`** depends on `/api/onboarding/status` — errors fall through to `of(true)` (**permissive** on failure).

### Components / pages (non-exhaustive)

| Component / feature | Route | Real API (sample) | Status |
|---------------------|-------|-------------------|--------|
| `Home`, `About`, `Contact` | public | `POST /api/public/contact` | ⚠️ PARTIAL — static + contact |
| `Signup` | `/signup` | `POST /api/auth/register` | ✅ WORKING (wired) |
| `VerifyEmail` | `/verify` | `POST /api/auth/verify-email` | ✅ WORKING |
| `ForgotPassword`, `ResetPassword` | auth | `/api/auth/*` | ✅ WORKING |
| `Login` | `/login` | MSAL + `POST /api/auth/login`, `GET /api/demo/tenant` | ✅ WORKING |
| `CompanySetup` | `/setup` | `POST /api/onboarding/*` | ⚠️ PARTIAL — **needs full E2E** |
| `Layout` + `Dashboard` | `/dashboard` | dashboard + documents hooks | ⚠️ PARTIAL — verify each widget |
| `documents-list`, `document-form` | `/documents` | `/api/documents` | ✅ Likely working |
| `ncr-*`, `risk-*` | module routes | `/api/ncrs`, `/api/risks` | ⚠️ PARTIAL — offline layers add complexity |
| `consultant-*` | `/consultant` | `/api/consultants`, `/api/audits` | ⚠️ PARTIAL |
| `access-requests` | `/admin/access-requests` | `/admin/v1/access-requests` | ✅ Wired |
| `tenant-settings`, `m365-connection`, `billing-info` | admin | `/api/tenant/*`, tenants | ⚠️ PARTIAL |

### Orphaned / duplicate frontend (heuristic)

| Item | Note |
|------|------|
| `*.component.ts` vs `*.ts` | Many features use **`documents-list.ts`** style (not `*.component.ts`) — **not orphaned**, naming convention mixed. |
| `admin-console` project | Separate app — **may duplicate** portal admin routes; **needs product decision**. |
| `onboarding-wizard` under `components/` | May overlap `user-onboarding-page` — ⚠️ **verify usage** (not traced in this audit). |

### Services (`frontend/src/app/services`)

| Service | API targets | Auth header |
|---------|-------------|-------------|
| `auth.service.ts` | `/api/auth/*` | Via interceptor (local token) |
| `documents.service.ts` | `/api/documents` | MSAL or local JWT |
| `ncr.service.ts` | `/api/ncrs` | Same |
| `risks.service.ts` | `/api/risks` | Same |
| `tenant.service.ts` | `/api/tenants`, `/api/tenant` | Same |
| `dashboard.service.ts` | `/api/dashboard` | Same |
| `consultant.service.ts` | `/api/consultants`, `/api/audits` | Same |
| `popia.service.ts` | `/api/popiatrail` | Same |
| `onboarding.service.ts` | `/api/onboarding` | Same |

**`auth.interceptor`:** ✅ Prefers **local JWT**, then **MSAL silent token**; attaches `X-Tenant-Id` when known.

---

## REPORT 6 — DEPENDENCY AUDIT

### NuGet (representative — **not** every transitive dependency audited)

| Package | Where | Note |
|---------|-------|------|
| `Microsoft.EntityFrameworkCore` 8.0.x | Application, Infrastructure | Core ORM |
| `Npgsql.EntityFrameworkCore.PostgreSQL` 8.0.x | Infrastructure | PG provider |
| `MediatR` 12.x | Application, API hosts | CQRS |
| `FluentValidation.AspNetCore` 11.x | Application, API hosts | Validation |
| `Microsoft.AspNetCore.Authentication.JwtBearer` 8.0.x | API hosts | JWT |
| `Serilog.AspNetCore` | API hosts, workers | Logging |
| `Swashbuckle.AspNetCore` | API hosts | OpenAPI |
| `BCrypt.Net-Next` | `MaemoCompliance.Api` | Password hashing |
| `Azure.Identity` | Infrastructure | Azure integrations |

**Flags**

| Flag | Detail |
|------|--------|
| ⚠️ **Version skew** | Infrastructure references **Microsoft.Extensions.Configuration 10.0.0** while EF Core is **8.0.x** — **works but mixes major lines**; verify compatibility. |
| 🔒 **CVE scan** | **Not run** in this audit (`dotnet list package --vulnerable` / GitHub Dependabot recommended). |
| 🗑️ **Unused packages** | **Not proven** package-by-package (would require per-project reference analysis). |

### npm (main portal `frontend/package.json`)

| Package | Role |
|---------|------|
| `@angular/*` ~20.2 | Framework |
| `@azure/msal-angular`, `@azure/msal-browser` | Microsoft auth |
| `rxjs`, `zone.js` | Std |

**Flags**

| Flag | Detail |
|------|--------|
| ⚠️ **Heavy / duplicate** | MSAL + Angular — **large** but justified for Entra. |
| ⚠️ **Unused deps** | **Not computed** with `depcheck` — recommend running tooling. |

---

## REPORT 7 — ARCHITECTURE ASSESSMENT

1. **Clean Architecture:** ✅ **Mostly** — `Domain` has no EF references; `Application` references `Domain` + abstractions; `Infrastructure` implements `IApplicationDbContext`, etc. ⚠️ **Minimal API** files in `MaemoCompliance.Api` sometimes use `IApplicationDbContext` **directly** (bypassing MediatR pattern).

2. **MediatR consistency:** ⚠️ **Mixed** — Many flows use MediatR; **Onboarding** and **Auth** use **inline handlers** with EF + mail. Not a violation, but **inconsistent**.

3. **Error handling:** ⚠️ **Mixed** — `ErrorResults` helpers vs `Results.Json` anonymous for some auth errors. Generally HTTP status codes used; **not 100% uniform**.

4. **Multi-tenancy:** ⚠️ **PARTIAL OR INCOMPLETE** — **`TenantQueryInterceptor` is not registered**; enforcement is **per-handler** `Where(d => d.TenantId == tenantId)`. **Evidence queries** allow `request.TenantId` override pattern — must be **authorization-reviewed** on every entry point.

5. **Audit trail:** ⚠️ `BaseEntity` has `CreatedAt`/`ModifiedBy` fields; **population is not verified** as consistent on all writes.

6. **N+1:** ❓ **Not profiled** — would need runtime analysis.

7. **Validation:** ⚠️ **FluentValidation** in Application + ad-hoc validation in minimal APIs.

8. **Security gaps (examples):**  
   - 🔒 **Tenant ID header** (`X-Tenant-Id`) + JWT `tenant_id` — **must align**; mismatches historically caused bugs.  
   - 🔒 **File upload** endpoints exist on documents — **size/type checks** not verified in this audit.  
   - 🔒 **Admin** routes rely on **PlatformAdmin** policy — implementation must be reviewed in `Program.cs` for dev vs prod.

---

## REPORT 8 — WHAT ACTUALLY WORKS

**Minimum set that is plausibly end-to-end** (API + DB + UI), based on wiring + tests + recent features:

- ✅ Public marketing pages + contact + access request.  
- ✅ **Email/password signup**, verification, login, forgot/reset (new).  
- ✅ Microsoft login path (existing MSAL).  
- ✅ **Document** lifecycle (strongest test coverage).  
- ✅ **NCR** core flows + root cause tests.  
- ✅ **Risk** CRUD via portal (handlers exist).  
- ✅ **Audit programme** unit tests + consultant audit UI presence.  
- ✅ **Engine API** surface for headless integrations (parallel to portal).  
- ✅ **Admin access request** approval flow (API + portal admin page).  

**Backend-only / weak UI**

- ⚠️ Webhooks, extensive Engine tenant admin, worker logs, business audit log surfacing.  
- ⚠️ `WelcomeEmails` table.  

**Frontend-only / mock risk**

- ⚠️ Any dashboard widget not matching a live endpoint (needs click-through QA).  

**Built but disconnected**

- 🗑️ **`TenantQueryInterceptor`** — implemented, **not registered**.  

**Potentially broken / environment-dependent**

- ❌ Anything requiring **Azure AD** + correct **Authority/Audience** + **SharePoint** — historically fragile per prior context.  
- ⚠️ **Duplicate API hosts** — risk of deploying wrong project or drift.

---

## REPORT 9 — DECOUPLING ASSESSMENT

| Candidate service | Natural boundary | Needs from others | Shared DB? |
|-----------------|------------------|-------------------|------------|
| **Compliance Engine** (`/engine/v1`) | Documents, NCR, Risk, Audit runs, webhooks | Auth (JWT/API keys), tenant resolution | Today: **same DB** — future: **tenant service + per-tenant DB or row-level** |
| **Tenant / Auth / Directory** | Tenants, users, invites, local auth, M365 connect | Email provider, secrets | Same |
| **Public marketing** | Static + `public/*` | API for forms | None / CDN |
| **Admin / Operations** | `/admin/v1`, workers, logs | Auth (platform), read/write tenants | Same |
| **Workers** | Retention, sync, scheduled jobs | Queue or DB polling, Engine/Portal callbacks | Same |
| **Marketing site** | Could be **pure static** | `POST` contact to API | No |

**Recommended split (pragmatic):**

1. **`maemo-engine-api`** — `/engine/v1` only + API keys + webhooks.  
2. **`maemo-portal-api`** — `/api/*` + `/public/*` + `/api/auth/*`.  
3. **`maemo-admin-api`** — `/admin/v1/*` (or merge with portal behind stronger RBAC).  
4. **`maemo-workers`** — async.  
5. **`maemo-web`** — Angular + static marketing.

**Shared kernel:** `MaemoCompliance.Shared` contracts; **avoid shared DB** long-term — use **tenant service API** + **eventing** for cross-service consistency.

---

## OVERALL HEALTH SCORE: **6/10**

**Why not higher:** duplicate hosts, unregistered tenant interceptor, inconsistent architectural patterns (MediatR vs inline), incomplete automated API/UI coverage, high coupling to monolith DB.

**Why not lower:** clear domain model, substantive ISO-aligned features, real tests on critical workflows, Engine surface for integrations.

---

## TOP 5 CRITICAL ISSUES

1. ❌ **`TenantQueryInterceptor` dead code** — docs claim enforced filtering; **reality is handler-by-handler** → **cross-tenant leakage risk** if any query slips.  
2. 🔒 **Multi-tenant enforcement not centralized** — requires **security review** of every new query/command.  
3. ⚠️ **Multiple API hosts** (`MaemoCompliance.Api` vs `Engine.Api` vs `Portal.Api` vs `Admin.Api`) — **deployment and drift risk**.  
4. ⚠️ **Dual signup** (`/public/signup` vs `/api/auth/register`) — **product/technical confusion**.  
5. 🔒 **Azure AD + SharePoint** fragility — **ops burden**; local auth mitigates but M365 path still critical for many tenants.

---

## TOP 5 QUICK WINS

1. ✅ **Register or delete `TenantQueryInterceptor`** — pick one; update `MaemoComplianceDbContext` comments to match.  
2. ✅ **Document canonical API host** in `README` / runbooks (single source of truth).  
3. ✅ **Deprecate one signup path** or clearly name “legacy” vs “new”.  
4. ✅ **`dotnet list package --vulnerable`** + Dependabot.  
5. ✅ **Frontend guard hardening** — avoid `catchError(() => of(true))` for security-sensitive guards without UX for failure.

---

## RECOMMENDED SPLIT ARCHITECTURE

**Phase 1 (logical split, same repo):** solution folders + clear boundaries + shared contracts only.  
**Phase 2 (deployable):** extract Engine + Workers first (least UI coupling).  
**Phase 3:** Tenant/Auth service + BFF for portal.  
**Phase 4:** Separate databases or schemas per bounded context with **eventual consistency**.

---

## honesty clause

This report is the best **static** picture available without running the full system, reading every file, or executing dynamic security tools. Treat it as **directionally accurate** with **known gaps** called out above.

---

*End of report.*
