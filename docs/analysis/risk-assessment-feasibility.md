# Risk Assessment (HIRA) Module — Codebase Discovery & Feasibility Analysis

**Date:** 2026-07-07  
**Scope:** Maemo Compliance platform (this repo `maemo-compliance` monolith + related split repos)  
**Method:** Read-only audit — no application code changed  
**Author role:** Senior architect discovery pass  

---

## 1. Executive summary

### Recommendation: **BUILD-IN (extend the compliance engine + portal)** — not a separate product

HIRA should live as a **new module inside the existing compliance domain**, primarily in **`maemo-compliance-engine`** (target architecture) with parallel implementation in the **`maemo-compliance` monolith** until nginx/DB cutover completes. The platform already has a **generic risk register** with 5×5 L×I inherent/residual scoring (`Risk` entity), **department** scoping, **document-style approval workflow** patterns, **file evidence storage**, **audit/business logging**, and **background workers** for due-date reminders — enough to reuse ~40% of the plumbing. What does **not** exist: configurable risk matrices, hazard/control libraries, hierarchical controls, HIRA-specific assessment lifecycle, structured sign-off trail, recurrence, or PDF export. Those require **new entities and UI**, but not a new microservice: coupling to tenant context, evidence files, NCR links, and JWT auth is tight enough that a separate HIRA product would duplicate the engine’s reason for being.

**Justification in one paragraph:** South African HIRA (OHS Act 85/1993, Construction Reg 9, ISO 45001 §6.1.2) maps naturally onto Maemo’s existing **HealthSafety risk category**, **tenant-owned registers**, and **compliance evidence** model. Building HIRA inside the engine keeps one Postgres tenant boundary, one portal module gate, and one worker host for review-due alerts. The main cost is **new domain** (matrices, hazards, assessments, sign-offs), not new infrastructure. PDF and configurable matrices are **Phase 2+** to protect M0 scope.

---

## 2. Phase 1 — Discovery findings

### 2.1 Solution topology

#### 2.1.1 This repo (`maemo` / GitHub: `Codist-Pty-Ltd/maemo-compliance`)

| Project | Path | Stack | Entry / role |
|---------|------|-------|----------------|
| **MaemoCompliance.Api** | `MaemoCompliance.Api/` | .NET **8** (`MaemoCompliance.Api.csproj`) | **Production API** — portal + engine + admin + public minimal APIs (`Program.cs`) |
| **MaemoCompliance.Application** | `application/src/MaemoCompliance.Application/` | MediatR **12**, FluentValidation **11** | CQRS handlers |
| **MaemoCompliance.Domain** | `domain/src/MaemoCompliance.Domain/` | Pure C# | Entities, enums |
| **MaemoCompliance.Infrastructure** | `infrastructure/src/MaemoCompliance.Infrastructure/` | EF Core **8**, Npgsql **8** | Persistence, email, storage |
| **MaemoCompliance.Workers** | `workers/src/MaemoCompliance.Workers/` | .NET Worker | `BackgroundService` jobs |
| **MaemoCompliance.Engine.Api** | `engine/src/MaemoCompliance.Engine.Api/` | .NET 8 | Split experiment — engine-only host |
| **MaemoCompliance.Portal.Api** | `portal/src/MaemoCompliance.Portal.Api/` | .NET 8 | Split experiment — portal-only host |
| **MaemoCompliance.Admin.Api** | `admin/src/MaemoCompliance.Admin.Api/` | .NET 8 | Split experiment — admin-only host |
| **MaemoCompliance.UnitTests / IntegrationTests** | `MaemoCompliance.UnitTests/`, `MaemoCompliance.IntegrationTests/` | xUnit, Testcontainers | CI gates |
| **Frontend (embedded)** | `frontend/` | Angular **~20.2.1** (`frontend/package.json`) | Production portal UI in monolith image |
| **E2E** | `e2e/maemo-compliance/` | Playwright | Smoke tests in CI |

**Solution file:** `MaemoCompliance.sln` lists all of the above .NET projects.

**Docker (production):** `docker-compose.prod.yml` — services `postgres` (16-alpine), `api` (`ghcr.io/codist-pty-ltd/maemo-compliance-api:latest`, `127.0.0.1:8090→8080`), `workers`, `frontend` (`127.0.0.1:3020→80`). Env: `/opt/maemo-compliance/.env`.

**Docker (local):** `docker-compose.yml` — postgres **5433**, api **8080**, frontend **80**.

**CI:** `.github/workflows/ci.yml` — unit + integration tests → GHCR push → SSH deploy to `/opt/maemo-compliance/app`.

**Reverse proxy:** Not in repo; `docs/MAEMO_REPOS_AND_CI.md` documents nginx loopback upstreams on Hetzner `65.109.7.45`. No Caddy config found in codebase.

#### 2.1.2 Related split repos (platform context — not in this repo root)

Documented in `docs/MAEMO_REPOS_AND_CI.md`:

| Service | Local folder | Port | Dockerfile |
|---------|--------------|------|------------|
| maemo-identity | `../maemo-identity` | 8100 | `src/MaemoIdentity.Api/Dockerfile` |
| maemo-compliance-engine | `../maemo-compliance-engine` | 8090 | `Dockerfile` |
| maemo-workers | `../maemo-workers` | none | `Dockerfile` |
| maemo-portal | `../maemo-portal` | 3020 | `Dockerfile` |
| maemo-admin | `../maemo-admin` | 3030 | `Dockerfile` |
| maemo-public | `../maemo-public` | 3010 | `Dockerfile` |

**Production today:** monolith still serves live API/portal (`docs/MAEMO_REPOS_AND_CI.md` L17). Split repos deploy in parallel; cutover is host-by-host.

#### 2.1.3 Dependency graph (sync calls)

```
[Browser: maemo-portal / monolith frontend]
    │ HTTPS + Bearer JWT (+ X-Tenant-Id)
    ├─► [maemo-identity :8100]  — login, register, tenant, onboarding (split target)
    └─► [maemo-compliance API :8090]  — documents, NCRs, risks, audits (monolith OR engine)

[maemo-compliance-engine :8090]  — validates JWT (Identity:Authority); tenant_id claim
    └─► (optional) maemo-identity /internal/* via X-Service-Key — not required for basic CRUD

[maemo-workers]  — no HTTP; reads/writes compliance Postgres; Resend via EmailQueue
    └─► shares maemo-compliance-network (external in docker-compose.prod.yml)

[maemo-admin]  — X-Admin-Key + HTTP to identity/engine /admin/v1/*
[maemo-public]  — static; POST to identity public APIs only
```

**Async:** Email via `EmailQueue` table + `EmailQueueWorker` (`../maemo-workers/src/MaemoWorkers/EmailQueueWorker.cs`). Monolith workers mostly **log-only** reminders (`ComplianceJobsWorker.cs`).

---

### 2.2 Data model & persistence

#### 2.2.1 DbContext (monolith)

**Class:** `MaemoComplianceDbContext` — `infrastructure/src/MaemoCompliance.Infrastructure/Persistence/MaemoComplianceDbContext.cs`  
**Interface:** `IApplicationDbContext` — `application/src/MaemoCompliance.Application/Common/IApplicationDbContext.cs`  
**Snapshot:** `infrastructure/src/MaemoCompliance.Infrastructure/Migrations/MaemoComplianceDbContextModelSnapshot.cs`

**Base types:**
- `BaseEntity` — `Id`, `CreatedAt`, `CreatedBy`, `ModifiedAt`, `ModifiedBy` (`domain/src/MaemoCompliance.Domain/Common/BaseEntity.cs`)
- `TenantOwnedEntity` — adds `TenantId` (`domain/src/MaemoCompliance.Domain/Common/TenantOwnedEntity.cs`)

#### 2.2.2 Entity inventory (monolith — all `DbSet`s)

| Entity | Table | Key fields / notes |
|--------|-------|-------------------|
| `Tenant` | `Tenants` | `Name`, `Domain`, `Edition`, `Plan`, `ModulesEnabledJson`, M365 fields, onboarding/setup wizard fields |
| `TenantSettings` | `TenantSettings` | Per-tenant config |
| `Department` | `Departments` | `Name`, `Description`, `IsActive` — **org unit, not “site”** (`domain/.../Tenants/Department.cs`) |
| `User` | `Users` | `Email`, `Role`, `PasswordHash`, auth/onboarding fields |
| `UserInvitation` | `UserInvitations` | Invite flow |
| `ConsultantTenantLink` | `ConsultantTenantLinks` | Consultant ↔ tenant |
| `Document` | `Documents` | Workflow, POPIA, retention, `StorageLocation`, `FileHash`, approver fields |
| `DocumentVersion` | `DocumentVersions` | Versioned file metadata |
| `Ncr` | `Ncrs` | `Severity`, `Status`, `DueDate`, root cause, `LinkedAuditFindingId` |
| `NcrRiskLink` | `NcrRiskLinks` | M:N NCR ↔ Risk |
| `NcrStatusHistory` | `NcrStatusHistory` | Status trail |
| `Risk` | `Risks` | L×I inherent/residual, `RiskCategory`, `RiskStatus`, `OwnerUserId` |
| `AuditTemplate` | `AuditTemplates` | `Name`, `ConsultantUserId` — **no Standard/Clause in monolith** |
| `AuditQuestion` | `AuditQuestions` | Template questions |
| `AuditRun` | `AuditRuns` | Execution |
| `AuditAnswer` | `AuditAnswers` | `EvidenceFileUrl`, `EvidenceFileHash` |
| `AuditFinding` | `AuditFindings` | `LinkedNcrId` |
| `AuditProgramme` | `AuditProgrammes` | `Year`, `Title`, `Status` |
| `AuditScheduleItem` | `AuditScheduleItems` | `PlannedDate`, `Status`, `LinkedAuditId` |
| `AccessRequest` | `AccessRequests` | Growth pipeline |
| `ApiKey` | `ApiKeys` | Engine integration keys |
| `WebhookSubscription` | `WebhookSubscriptions` | Outbound webhooks |
| `AuditLogEntry` | `AuditLogs` | Technical audit |
| `BusinessAuditLog` | `BusinessAuditLogs` | Compliance events |
| `ApiCallLog`, `ErrorLog`, `WorkerJobLog`, `WebhookDeliveryLog` | respective tables | Observability |
| `WelcomeEmail` | `WelcomeEmails` | Email tracking |

**Not found:** `Hazard`, `RiskMatrix`, `ControlMeasure`, `RiskAssessment`, `Site`, `Framework`, `Requirement`, `Control` (as domain entities).

#### 2.2.3 DbContext (split engine)

**Class:** `ComplianceDbContext` — `../maemo-compliance-engine/src/MaemoComplianceEngine.Infrastructure/Persistence/ComplianceDbContext.cs`  
Subset of compliance entities + `EmailQueue`, `TenantWorkerContact`; **no** `Tenant`, `User`, `AuditLogEntry`, `BusinessAuditLog`.

**Parallel `Risk` model** differs: `RiskNumber`, string `Category`/`Status`, `AssessAsync`/`TreatAsync` (`RiskService.cs`), `ReviewDate`, `RelatedStandard` string.

#### 2.2.4 Migrations

| Location | Count | Path |
|----------|-------|------|
| Monolith | **20** migrations + snapshot | `infrastructure/src/MaemoCompliance.Infrastructure/Migrations/` |
| Engine split | **2** migrations + snapshot | `../maemo-compliance-engine/src/.../Migrations/` |

Risk introduced in monolith: `20251118152527_AddRiskRegister.cs`, NCR link: `20251118152904_AddNcrRiskLinking.cs`.

**Apply strategy:** Monolith runs `Migrate()` in Development (`MaemoCompliance.Api/Program.cs`); production expects migrated schema before deploy. Engine `.env.example` has `Compliance__AutoMigrate=true`.

#### 2.2.5 Multi-tenancy (exact mechanism)

**Monolith:**
1. `TenantMiddleware` sets `TenantContext.TenantId` from JWT claim `tenant_id`, API key `NameIdentifier`, or header `X-Tenant-Id` (`MaemoCompliance.Api/Middleware/TenantMiddleware.cs`).
2. **No EF global query filter** — removed intentionally; comment in `MaemoComplianceDbContext.cs` directs handlers to use `QueryExtensions.ForTenant()` (`infrastructure/.../Persistence/QueryExtensions.cs`).
3. `Guid.Empty` tenant skips filter (admin/seeding only).

**Engine split:**
- EF global filters via `TenantOwnedQueryFilterConfigurator` + `HttpTenantContext` (evidence: `TenantIsolationTests` in engine unit tests).

**Column pattern:** `TenantId` on `TenantOwnedEntity` descendants — shared DB column, not separate schema per tenant.

---

### 2.3 Compliance engine — frameworks, controls, evidence, scoring

#### 2.3.1 Framework / standard / requirement / control hierarchy

**Not implemented as relational entities.** Search of `domain/` and `MaemoComplianceEngine.Domain` found no `Framework`, `Requirement`, or `Control` classes.

**Related metadata only:**

| Mechanism | Evidence |
|-----------|----------|
| Tenant standards JSON | `Tenant.TargetStandardsJson` (`domain/.../Tenants/Tenant.cs`) |
| User standards JSON | `User.ComplianceStandardsJson` |
| Signup ISO list | `SignupCommand.cs` — `IsoFrameworks[]` |
| Engine audit template standard | `AuditTemplate.Standard`, `AuditQuestion.IsoClause` (`maemo-compliance-engine/.../AuditEntities.cs`) |
| Engine risk standard link | `Risk.RelatedStandard` string (`maemo-compliance-engine/.../Risk.cs`) |
| Monolith risk controls | `Risk.ExistingControls` **free text** only (`domain/.../Risks/Risk.cs`) |

#### 2.3.2 Control / requirement status tracking

No compliant/in-progress control status model. Closest patterns:
- **Document** `Status` + `DocumentWorkflowState` enum (`domain/.../Documents/DocumentWorkflowState.cs`)
- **Ncr** `Status` enum + `NcrStatusHistory`
- **Risk** `RiskStatus`: `Identified`, `Analysed`, `Mitigated`, `Accepted`, `Closed` (`domain/.../Risks/RiskStatus.cs`)
- **AuditScheduleItem** `Status` on programme items

#### 2.3.3 Evidence system

| Concern | Implementation | Path |
|---------|----------------|------|
| Abstraction | `IFileStorageProvider` | `application/.../Common/IFileStorageProvider.cs` |
| Local storage | `{basePath}/{tenantId}/{category}/{guid}{ext}` | `infrastructure/.../Storage/LocalFileStorageProvider.cs` |
| SharePoint | SaaS mode | `SharePointFileStorageProvider.cs` |
| Document upload | `UploadDocumentFileCommandHandler` | `application/.../Documents/Commands/` |
| Audit evidence | `UploadAuditEvidenceCommandHandler` → `AuditAnswer.EvidenceFileUrl` | `application/.../Audits/Commands/` |
| Evidence register query | Aggregates documents + audit files | `application/.../Evidence/Queries/GetEvidenceRegisterQueryHandler.cs` |
| Integrity | SHA256 `FileHash` on documents | domain `Document.cs` |
| Retention | `RetainUntil`, workers | `RecordsRetentionWorker.cs`, `DocumentDestructionWorker.cs` |

**Not MinIO** — local disk or SharePoint only. Engine `Document.FilePath` string; no `IFileStorageProvider` in engine repo (verified by exploration).

#### 2.3.4 Review cycles / recurrence

| Feature | Exists? | Evidence |
|---------|---------|----------|
| Document review date | Yes | `Document.ReviewDate`; worker `ProcessDocumentReviewRemindersAsync` in `ComplianceJobsWorker.cs` (14-day window) |
| NCR due dates | Yes | `Ncr.DueDate`; `ProcessOverdueNcrsAsync` |
| Risk review date (monolith) | **No** | `Risk.cs` has no `ReviewDate` |
| Risk review (engine) | Partial | `Risk.ReviewDate` on engine entity only |
| Audit programme schedule | Yes | `AuditProgramme`, `AuditScheduleItem.PlannedDate` |
| Recurrence / ReviewCycle entity | **No** | No matches for `Recurrence`, `ReviewCycle`, `NextReview` in repos |
| Schedule overdue automation | Partial | `ApplyOverdueIfNeeded()` on schedule item — **only referenced in unit tests**, not in query handlers (exploration finding) |

Split `AuditScheduleWorker` sends email reminders (`../maemo-workers/src/MaemoWorkers/AuditScheduleWorker.cs`).

#### 2.3.5 Scoring / weighting / maturity

| Concept | Implementation |
|---------|----------------|
| Risk L×I (1–5) | `InherentScore = L×I`, `ResidualScore = L×I` in `CreateRiskCommandHandler` / `UpdateRiskCommandHandler` |
| Risk bands | Hard-coded in `RiskDto.GetRiskLevel`: ≤5 Low, ≤10 Medium, ≤15 High, else Critical (`application/.../Risks/Dtos/RiskDto.cs`) |
| High-risk worker threshold | `ResidualScore >= 15` in `ComplianceJobsWorker.ProcessHighResidualRisksAsync` |
| Engine clamp | `Math.Clamp(value, 1, 5)` in `RiskService.cs` |
| L×S×E (exposure) | **Not found** |
| Configurable matrix | **Not found** |
| Maturity levels | **Not found** |

---

### 2.4 Identity, roles & authorization

#### 2.4.1 Monolith auth

| Mechanism | Path |
|-----------|------|
| Smart JWT (local vs Azure AD by issuer) | `MaemoCompliance.Api/Program.cs`, `Authentication/MaemoAuthSchemes.cs` |
| Local JWT claims | `LocalJwtTokenFactory.cs` — `sub`, `email`, `tenant_id`, `ClaimTypes.Role` |
| Azure AD | `Authentication:Authority`, `Authentication:Audience` |
| API keys | `ApiKeyAuthenticationHandler.cs`, header `X-Api-Key` |
| Policies | `RequireAdmin`, `PlatformAdmin`, `RequireTenantAdmin`, `RequireConsultant`, `RequireDocumentApprover`, `EngineClients` — `Program.cs` |

**Roles (monolith):** `UserRole` enum — `Admin`, `TenantAdmin`, `TenantUser`, `Consultant` (`domain/.../Users/UserRole.cs`).

#### 2.4.2 Split identity service

**Roles differ:** `Viewer`, `Manager`, `Admin`, `PlatformAdmin` (`../maemo-identity/src/MaemoIdentity.Domain/Enums/UserRole.cs`).  
JWT claims: `tenant_id`, `role` (int), `plan`, `setup_complete` (`JwtTokenService.cs`).

#### 2.4.3 Module authorization (feature flags)

`ITenantModuleChecker` / `TenantModuleChecker` — `Tenant.ModulesEnabledJson` array (e.g. `"Risks"`) enforced on endpoints via filter (`MaemoCompliance.Api/Portal/RisksEndpoints.cs` L27–35). Default signup modules: `Documents`, `NCR`, `Risks`, `Audits` (`AuthEndpoints.cs` L178).

#### 2.4.4 Legal appointments / designated persons / sign-off

**No domain entity** for OHS Act §16.2 appointee, SHE rep, or formal sign-off chain.

**Closest primitives:**
- `Risk.OwnerUserId`, `Ncr.OwnerUserId`, `Document.ApproverUserId` / `ApprovedBy` / `ApprovedAt`
- Document workflow: `ApproveDocumentCommandHandler` (`application/.../Documents/Commands/ApproveDocumentCommandHandler.cs`)
- Policy `RequireDocumentApprover` — approver role only for documents, not HIRA

---

### 2.5 Portal (frontend)

#### 2.5.1 Split portal (`maemo-portal`) — target for new module UI

| Item | Detail |
|------|--------|
| Framework | Angular **19.2**, PrimeNG **19.1.4** (`package.json`) |
| Routes | `src/app/app.routes.ts` — `/app/risks`, `/app/risks/new`, `/app/risks/:id` |
| Risk list | `src/app/pages/risk-list.component.ts` — inline `p-table`, filters, tags, calls `environment.engineApiUrl/api/risks` |
| Risk detail/form | `risk-detail.component.ts`, `risk-form.component.ts` |
| State | Angular signals + `HttpClient` in components; no NgRx |
| API auth | `core/interceptors/auth.interceptor.ts` — Bearer to `/api/`, `/engine/v1/` |
| Design system | PrimeNG Aura preset in `app.config.ts` |

#### 2.5.2 Monolith frontend (production UI today)

Angular **20.2.1** (`frontend/package.json`), **no PrimeNG** — custom tables.  
`frontend/src/app/services/risks.service.ts` → `/api/risks`.  
Routes mirror portal under authenticated layout (`frontend/src/app/app.routes.ts`).

#### 2.5.3 Reusable register / table patterns

- **No shared register component** — each list page embeds table markup (portal: PrimeNG `p-table`; monolith: HTML `<table>`).
- Status display: PrimeNG `p-tag` on risk list; NCR/document lists follow same pattern.
- **PDF/export:** No `jspdf`/`pdfmake` in `maemo-portal/package.json`. Monolith has CSV export only in `frontend/.../records-retention/records-retention.ts`. Document download button on portal documents list is stubbed (`preventDefault`).

---

### 2.6 Cross-cutting

| Concern | Monolith | Split workers / identity |
|---------|----------|---------------------------|
| Email | `ResendEmailSender` — `infrastructure/.../Email/ResendEmailSender.cs`; fallback `LoggingEmailSender` | Identity + `maemo-workers` Resend + `EmailQueue` |
| Audit trail | `IAuditLogger`, `IBusinessAuditLogger` — used on risk create/update | Engine: **no** business audit tables |
| Background jobs | `ComplianceJobsWorker` (5 min), retention/destruction (24h), heartbeat | `NcrOverdueWorker`, `RetentionWorker`, `AuditScheduleWorker`, `EmailQueueWorker` |
| Tests | xUnit; unit = EF InMemory; integration = Testcontainers PostgreSQL — `MaemoCompliance.IntegrationTests/` | Engine: same pattern in `tests/MaemoComplianceEngine.*` |
| CI failure gates | `.github/workflows/ci.yml` — unit + integration + frontend build | Per-repo `ci.yml` in split repos |

---

## 3. Phase 2 — Fit analysis

### 3.1 Reuse map

| Target capability | Classification | Existing mechanism / gap |
|-------------------|----------------|--------------------------|
| Tenant-scoped data | **REUSE AS-IS** | `TenantOwnedEntity.TenantId` + `ForTenant()` / engine filters |
| 5×5 L×S scoring (fixed) | **REUSE AS-IS** | `Risk.InherentLikelihood/Impact`, `ResidualLikelihood/Impact`, `RiskDto` bands |
| Configurable matrices (3×3–5×5, custom bands, L×S×E) | **NEW** | Bands hard-coded in `RiskDto.GetRiskLevel` only |
| Green/amber/red thresholds | **EXTEND** | Replace hard-coded bands with tenant matrix config |
| Department / org scope | **EXTEND** | `Department` exists; **no Site** entity — link assessments to `DepartmentId` |
| Hazard library (industry pack) | **NEW** | No hazard entity; onboarding seeder has OH&S **question text** only (`OnboardingSeeder.cs`) |
| Tenant-defined hazards | **NEW** | — |
| Control library + hierarchy of controls | **NEW** | `ExistingControls` is free text on `Risk` |
| Risk register per site/dept | **EXTEND** | Generic `Risk` register + filters; add `RiskAssessment` container |
| Initial → residual scoring flow | **PARTIAL REUSE** | Inherent/residual on single `Risk` row; engine has separate `Assess`/`Treat` steps |
| Assessment lifecycle (draft→review→approved→active→review-due) | **EXTEND** | Mirror `DocumentWorkflowState` pattern — not on `Risk` today |
| Sign-off trail (who, role, timestamp) | **EXTEND** | Document approver fields + audit logs; no multi-step sign-off entity |
| Evidence attachments | **REUSE AS-IS** | `IFileStorageProvider` + link table to assessment items |
| Review cycles / recurrence | **EXTEND** | Document review + NCR due workers; **no recurrence model** |
| Overdue dashboards | **EXTEND** | Dashboard queries exist; add HIRA review-due widgets |
| Email alerts for review-due | **EXTEND** | `EmailQueue` + workers pattern (split); monolith worker logs only |
| PDF export for DoL/auditors | **NEW** | No PDF library in portal or backend |
| ISO 31000 / 45001 / OHS Act alignment | **NEW (metadata)** | Standards as strings/JSON today — add `RegulatoryReference` links, not full framework tree |
| NCR linkage from assessed risks | **REUSE AS-IS** | `NcrRiskLink` + endpoints on `NcrsEndpoints.cs` |
| Module gating | **REUSE AS-IS** | Add `"HIRA"` or extend `"Risks"` in `ModulesEnabledJson` |
| Role: assessor vs approver | **EXTEND** | Only `RequireDocumentApprover`; need HIRA-specific policies |
| Legal appointments (16.2) | **NEW** | No appointee entity — could extend identity later |

---

### 3.2 Data model proposal

All new entities extend **`TenantOwnedEntity`** (monolith pattern) or engine equivalent with **`TenantId`**.

```
RiskMatrix (tenant config, optional per DepartmentId)
  ├── MatrixBand[] (label, color, minScore, maxScore, sortOrder)
  ├── MatrixSize (3|4|5), ScoringMethod (LxS | LxSxE)
  └── IsDefault

HazardLibraryEntry
  ├── Source (SystemPack | Tenant), PackCode (e.g. "construction-2014-baseline")
  ├── CategoryId → HazardCategory
  ├── Title, Description, TypicalControls (JSON or child rows)

HazardCategory (tenant + optional system seed)

RiskAssessment (container — one HIRA exercise)
  ├── DepartmentId? (FK Departments)
  ├── Title, AssessmentType (Baseline|Task|IssueBased)
  ├── WorkflowState (draft|review|approved|active|reviewDue) — mirror DocumentWorkflowState
  ├── RiskMatrixId (FK), NextReviewDate, ReviewFrequencyMonths
  ├── RegulatoryTags (JSON: ISO45001-6.1.2, OHS-Act, Construction-Reg9)

RiskAssessmentItem (line item — hazard in context)
  ├── RiskAssessmentId, HazardLibraryEntryId? (nullable if ad hoc)
  ├── Activity/TaskDescription, Location
  ├── InherentLikelihood, InherentImpact, [Exposure?]
  ├── InherentScore (computed)
  ├── ResidualLikelihood, ResidualImpact, ResidualScore
  ├── LinkedRiskId? (FK legacy Risks for migration bridge)
  └── SortOrder

ControlMeasure (per item, ordered)
  ├── RiskAssessmentItemId
  ├── HierarchyLevel (Elimination|Substitution|Engineering|Admin|PPE)
  ├── Description, IsImplemented, EffectivenessNotes

RiskAssessmentEvidence
  ├── RiskAssessmentItemId or RiskAssessmentId
  ├── StoragePath, FileHash, UploadedByUserId, UploadedAt

RiskAssessmentSignOff
  ├── RiskAssessmentId
  ├── UserId, RoleAtSignOff (string or enum), SignOffType (Prepared|Reviewed|Approved)
  ├── SignedAt, Comments

ReviewCycle (optional normalize recurrence)
  ├── RiskAssessmentId, FrequencyMonths, LastReviewedAt, NextDueAt
```

**Links to existing entities:**
- `Department` — `domain/.../Tenants/Department.cs`
- `User` / JWT `sub` — sign-off user ids (identity service long-term)
- `Risk` — optional bridge via `LinkedRiskId` for customers already on generic register
- `NcrRiskLink` — link residual high items to NCRs (existing join table pattern)

**Draft migration plan (engine / monolith — keep in sync during split):**

| Order | Migration | Content |
|-------|-----------|---------|
| M0-1 | `AddHiraCoreTables` | `RiskAssessment`, `RiskAssessmentItem`, `ControlMeasure`, `RiskAssessmentSignOff` (fixed 5×5, no matrix table) |
| M0-2 | `AddHiraEvidence` | `RiskAssessmentEvidence` + FK indexes |
| M1-1 | `AddRiskMatrixAndBands` | Configurable matrix |
| M1-2 | `AddHazardLibrary` | `HazardCategory`, `HazardLibraryEntry` + seed pack |
| M2-1 | `AddReviewCycle` | Normalized recurrence + indexes on `NextReviewDate` |
| M2-2 | `ExtendRiskBridge` | `LinkedRiskId`, views for dashboard |

**Estimated count:** 4–6 migrations phased; **do not** alter existing `Risks` table in M0 (additive only).

---

### 3.3 Service placement

**Recommendation: inside `maemo-compliance-engine` (and mirrored in monolith until cutover).**

| Factor | Observation | Implication |
|--------|-------------|-------------|
| Shared entities | HIRA links `Department`, evidence files, NCRs, audit logs | Same DB boundary as engine |
| Auth | JWT `tenant_id` already required on engine (`Program.cs`) | No new service auth |
| Evidence | `IFileStorageProvider` lives in monolith infrastructure today | Port storage abstraction to engine or share library — **gap to close** |
| Workers | Review-due jobs need Postgres access | Extend `maemo-workers`, not new worker service |
| Identity | Sign-off needs user display names | JWT claims sufficient M0; optional `/internal/users/{id}` later |

**Tradeoff:** Engine repo lacks `BusinessAuditLogger` — either add audit tables to engine or emit events to monolith during transition.

**Against separate HIRA microservice:** Would duplicate tenant filtering, file storage, NCR links, portal API client, and migrations for little isolation benefit; HIRA is not an independent bounded context from compliance engine.

---

### 3.4 API surface (following existing conventions)

Mirror **`/api/...`** (portal) and **`/engine/v1/...`** (integrators) pattern from `RisksEndpoints.cs` / `RisksController.cs`.

**Module gate:** `"HIRA"` or extend `"Risks"` via `ITenantModuleChecker`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/hira/assessments` | List (filter dept, state, review-due) |
| GET | `/api/hira/assessments/{id}` | Detail + items + controls + sign-offs |
| POST | `/api/hira/assessments` | Create draft assessment |
| PUT | `/api/hira/assessments/{id}` | Update header |
| POST | `/api/hira/assessments/{id}/items` | Add line item |
| PUT | `/api/hira/assessments/{id}/items/{itemId}` | Score + controls |
| POST | `/api/hira/assessments/{id}/submit-for-review` | Workflow transition |
| POST | `/api/hira/assessments/{id}/approve` | Approver sign-off |
| POST | `/api/hira/assessments/{id}/activate` | Go live |
| GET | `/api/hira/assessments/{id}/sign-offs` | Sign-off trail |
| POST | `/api/hira/assessments/{id}/evidence` | Upload attachment |
| GET | `/api/hira/dashboard/summary` | Overdue / due in 30 days / by band |
| GET | `/api/hira/hazards` | Library search (M1+) |
| GET/PUT | `/api/hira/matrix` | Tenant matrix config (M1+) |
| GET | `/api/hira/assessments/{id}/export/pdf` | PDF (M2+) |

Engine mirrors under `/engine/v1/hira/...` with API key policy where applicable.

---

### 3.5 Frontend plan

**Target repo:** `maemo-portal` (Angular 19 + PrimeNG).

| Screen | Copy / generalize from | Notes |
|--------|------------------------|-------|
| Risk register list | `risk-list.component.ts` | Filters, `p-table`, tags for band color |
| Detail / editor | `risk-form.component.ts`, `risk-detail.component.ts` | Multi-item editor = new |
| Workflow / sign-off | `approvals.component.ts`, document approval flow | Sign-off stepper new |
| Matrix config | **New** | PrimeNG `p-table` + color picker; no precedent |
| Dashboard widgets | `dashboard.component.ts` | Add HIRA overdue cards |
| Evidence upload | `document-form.component.ts` upload patterns | Reuse HTTP multipart pattern |

**Monolith frontend:** Only if production cutover to portal is delayed — otherwise **portal-only** to avoid dual Angular versions (19 vs 20).

---

### 3.6 Gaps & risks (ranked)

| Severity | Gap | Evidence |
|----------|-----|----------|
| **High** | No PDF export stack | No PDF libs in `maemo-portal/package.json` |
| **High** | No hazard/control domain | Domain search — only `Risk.ExistingControls` text |
| **High** | Dual codebase (monolith + engine) during split | `docs/MAEMO_REPOS_AND_CI.md` — production on monolith |
| **Medium** | No recurrence / review cycle entity | No `ReviewCycle` in codebase |
| **Medium** | Sign-off not generalized | Document-specific approver fields |
| **Medium** | Role model mismatch identity vs monolith | Different `UserRole` enums |
| **Medium** | Engine lacks file storage provider | Engine uses `FilePath` string |
| **Medium** | Authz too coarse for assessor/approver/SHE rep | No appointee; only `RequireDocumentApprover` |
| **Low** | No Site entity — only `Department` | `Department.cs` |
| **Low** | Monolith workers log-only vs email in split workers | `ComplianceJobsWorker` vs `EmailQueueWorker` |
| **Low** | Hard-coded risk bands | `RiskDto.GetRiskLevel` |

---

## 4. Phased implementation plan

| Phase | Scope | Effort | Delivers |
|-------|--------|--------|----------|
| **M0** | Fixed **5×5** matrix (reuse `RiskDto` bands), `RiskAssessment` + items + `ControlMeasure` (flat list), workflow draft→approved→active, `RiskAssessmentSignOff`, evidence upload via storage port, portal list/detail/sign-off, module gate `"HIRA"`, basic dashboard counts | **L** | Demoable HIRA to consultants; one **seed hazard pack** (JSON/SQL seed, ~20 construction hazards) |
| **M1** | `RiskMatrix` + bands, L×S×E option, hazard library CRUD + industry pack loader, department scoping, email review-due via `maemo-workers`, link items to NCR | **L** | Tenant-configurable matrix; recurring review dates |
| **M2** | PDF export (backend render e.g. QuestPDF or headless Chromium), ISO/OHS regulatory tags on assessment, bridge to legacy `Risk` register, engine audit logging parity | **M** | DoL/auditor-ready export |
| **M3** | Legal appointee roles (identity extension), consultant multi-site mode, advanced dashboard analytics, API key access for `/engine/v1/hira` | **M** | Enterprise / multi-org |

**M0 explicit exclusions:** configurable matrix UI, PDF, L×S×E, recurrence worker (manual next review date only), separate product branding.

**Rough calendar (1 team):** M0 ~6–8 weeks, M1 ~4–6 weeks, M2 ~3–4 weeks (parallelizable after M0 API stable).

---

## 5. Open questions (product owner decisions)

1. **Module naming:** New module `"HIRA"` in `ModulesEnabledJson`, or extend existing `"Risks"` module?
2. **Target codebase first:** Implement in **split engine** only (portal → engine), or **monolith first** because it still serves production traffic?
3. **Site vs department:** Is `Department` sufficient, or do customers require a **Site/Location** entity (multi-site mines, construction projects)?
4. **Relationship to existing Risk register:** Replace, coexist, or sync (`LinkedRiskId` bridge)? Migration for tenants already using `/app/risks`?
5. **Sign-off roles:** Which sign-off types are mandatory for Reg 9 baseline (preparer, reviewer, approver, 16.2 appointee)? Are electronic signatures legally sufficient?
6. **Industry pack priority:** Which first pack — **Construction Reg 9 baseline**, mining, manufacturing, office?
7. **Scoring method M0:** Confirm fixed **L×S only** (no exposure factor) for MVP.
8. **PDF template:** Codist-branded vs white-label per tenant? Required sections for DoL inspection?
9. **Identity cutover:** Will HIRA launch on **monolith JWT** or **maemo-identity** tokens only? Role enum alignment needed?
10. **Evidence retention:** Same POPIA retention policies as documents, or shorter OHS retention rules?
11. **Consultant mode:** Can one consultant manage HIRAs across linked tenants (`ConsultantTenantLink`) in M0 or defer to M3?
12. **Offline / mobile:** Any requirement for field hazard capture offline ( affects PWA scope)?
13. **Integrations:** Must HIRA items push to existing **webhooks** (`WebhookSubscription`) on approve?
14. **Language:** English only, or Afrikaans labels on matrix bands / PDF?

---

## 6. Appendix — key file index

| Topic | Path |
|-------|------|
| Risk entity (monolith) | `domain/src/MaemoCompliance.Domain/Risks/Risk.cs` |
| Risk endpoints | `MaemoCompliance.Api/Portal/RisksEndpoints.cs` |
| Risk scoring DTO | `application/src/MaemoCompliance.Application/Risks/Dtos/RiskDto.cs` |
| Tenant filtering | `infrastructure/.../Persistence/QueryExtensions.cs` |
| Tenant middleware | `MaemoCompliance.Api/Middleware/TenantMiddleware.cs` |
| Document workflow model | `domain/.../Documents/DocumentWorkflowState.cs` |
| File storage | `application/.../Common/IFileStorageProvider.cs` |
| Workers (monolith) | `workers/src/MaemoCompliance.Workers/Services/ComplianceJobsWorker.cs` |
| Workers (split email) | `../maemo-workers/src/MaemoWorkers/EmailQueueWorker.cs` |
| Portal risk UI | `../maemo-portal/src/app/pages/risk-list.component.ts` |
| Engine risk service | `../maemo-compliance-engine/src/.../Services/RiskService.cs` |
| Repo / deploy map | `docs/MAEMO_REPOS_AND_CI.md` |
| Decoupling blueprint | `docs/MAEMO_DECOUPLING_BLUEPRINT.md` |

---

*End of report — read-only discovery; no application code modified.*
