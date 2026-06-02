# Maemo Compliance — UI / UX Audit Report

**Scope:** `frontend/src` only (Angular portal). **Backend cross-check:** `MaemoCompliance.Api` (primary production API).  
**Rules:** Read `.cursorrules` first per audit instructions; **no code changes** in this pass.  
**Method:** All routed standalone components and shell were reviewed via their TypeScript + HTML (+ SCSS where relevant). Services and guards were grep’d for HTTP usage. Global styles and `package.json` were read. Static assets under `frontend/src/assets` were not read line-by-line. A separate legacy `portal/src/MaemoCompliance.Portal.Api` exists in-repo with some routes the main API lacks — this report treats **main API** as the source of truth for “endpoint exists” unless noted.

---

## REPORT 1 — Component by component

For each **routed** component (or shell child): route, intent vs code, APIs, backend presence, auth header, states, responsiveness, data source, status.

**Auth token (`Authorization` + `X-Tenant-Id`):** `auth.interceptor.ts` attaches a local JWT from `AuthService` if present; otherwise attempts a silent MSAL token. Relative `/api`, `/admin`, `/engine` requests to the app origin are covered; absolute `environment.apiBaseUrl` URLs are covered when they share the API host.

| Component | Route(s) | Supposed to show | Actually shows (code) | API calls | Endpoint exists (main API)? | Auth token | Loading | Error | Empty | Mobile | Data | Status |
|-----------|----------|------------------|------------------------|-----------|------------------------------|------------|---------|-------|-------|--------|------|--------|
| **AcceptInviteComponent** | `/accept-invite` | Validate invite token; accept | Token query + validate; POST accept | `GET /public/invite/validate`, `POST /api/tenant/invitations/accept` | Yes (Public group + TenantSelfService) | Validate: anonymous; accept: yes when logged in | Partial | Yes | N/A | Likely ok (simple layout) | Real | **WORKING** (paths match) |
| **Login** | `/login` | Email/password + Microsoft + demo | Tabs; MSAL redirect; demo tenant fetch | `POST /api/auth/login` (via AuthService); `GET /api/demo/tenant` | Yes | Login public; demo: if authed | Yes | Yes | N/A | Likely ok | Real | **WORKING** |
| **TenantSelectorComponent** | `/tenant-selector` | Pick / set tenant context | Demo tenant + navigation | `GET /api/demo/tenant` | Yes | If API call after login | Yes | Partial | N/A | Unknown (needs visual pass) | Real/demo | **PARTIAL** |
| **HomeComponent** | `/` | Marketing home | Static + links | None | — | — | — | — | — | Uses `public-brand` | Static | **WORKING** |
| **AboutComponent** | `/about` | About | Static | None | — | — | — | — | — | — | Static | **WORKING** |
| **ContactComponent** | `/contact` | Contact form | Form POST | `POST /api/public/contact` | Yes | No (anonymous) | Yes | Yes | — | — | Real | **WORKING** |
| **SignupComponent** | `/signup` | Self-service signup | Multi-step; POST register | `POST /api/auth/register` | Yes | No | Yes | Yes | — | — | Real | **WORKING** |
| **VerifyEmailComponent** | `/verify` | Email verification | Token in query; verify | `POST /api/auth/verify-email` (AuthService) | Yes | No | Partial | Yes | — | — | Real | **WORKING** |
| **ForgotPasswordComponent** | `/forgot-password` | Request reset | POST | `POST /api/auth/forgot-password` | Yes | No | Partial | Yes | — | — | Real | **WORKING** |
| **ResetPasswordComponent** | `/reset-password` | Set new password | POST | `POST /api/auth/reset-password` | Yes | No | Partial | Yes | — | — | Real | **WORKING** |
| **CompanySetupComponent** | `/setup` | Post-registration company wizard | Steps; profile, standards, invites, complete | `POST /api/onboarding/company-profile`, `target-standards`, `invite-team`, `complete` | Yes (OnboardingEndpoints) | Yes | Yes | Yes | — | — | Real | **WORKING** |
| **AccountPendingComponent** | `/account-pending` | Pending approval messaging | Static / minimal | None typical | — | N/A | — | — | — | — | N/A | **WORKING** (guard-driven) |
| **UserOnboardingPageComponent** | `/onboarding` | User profile / standards / invites wizard | 5 steps; `getMe` + `complete-wizard` | `GET /api/tenant/me`, `POST /api/tenant/onboarding/complete-wizard` | Yes | Yes | Yes | Yes (toast) | — | — | Real | **WORKING** |
| **Layout** (shell) | parent `''` with guards | App chrome, sidebar, outlet | Nav + `router-outlet`; MSAL-centric header | `GET /admin/v1/access-requests/pending-count` (platform admin); consultant client APIs via service | Yes | Yes when calling API | Partial (clients) | Silently on badge | N/A | **No `@media` in layout.scss** — sidebar risk | Real | **PARTIAL** — see below |
| **Dashboard** | `/dashboard` | Summary + widgets | Cards + onboarding checklist | `GET /api/dashboard/summary`; `GET /api/audits/runs?tenantId=`; documents pending/BBBEE; **POP widgets**; `GET/POST /api/tenant/onboarding-status` etc. via TenantService | **Summary yes**; audits runs **yes** (query param ignored server-side — tenant from context); **POPIA personal + retention widget URLs absent**; pending/BBBEE **yes** | Yes | Yes | Summary yes; widgets partial | Widgets only if length > 0 | Weak responsive | Real + **broken widgets** | **PARTIAL** |
| **DocumentsListComponent** | `/documents` | Document table | List + category filter from query | `GET /api/documents` (+ params) | Yes | Yes | Yes | Yes | Implicit empty list | Unknown | Real | **WORKING** — **but** ignores `workflowState` query (see nav) |
| **DocumentFormComponent** | `/documents/new`, `/documents/:id` | Create/edit document + workflow | Large form + uploads + **audit evidence export** | Many `/api/documents/*`; **GET `.../audit-evidence`** | Most yes; **`/api/documents/{id}/audit-evidence` NOT in main API** | Yes | Partial | Partial | — | Heavy form | Real | **PARTIAL** / evidence **BROKEN** |
| **DocumentTemplatePickerComponent** | embedded | Pick ISO template | Modal/picker | Loads `assets/templates/...` via TemplateLibraryService | N/A (static) | N/A | — | — | — | — | Asset files | **WORKING** |
| **ApprovalDashboardComponent** | `/documents/approvals` | Pending approvals | List | `GET /api/documents/pending-approval` | Yes | Yes | Yes | Yes | Likely empty state in template | — | Real | **WORKING** |
| **NcrListComponent** | `/ncrs` | NCR list | Filters + list | `GET /api/ncrs` (+ query) | Yes | Yes | Yes | Yes | Check template | — | Real | **WORKING** |
| **NcrFormOfflineComponent** | `/ncrs/new` | Create NCR (offline-capable) | Form + sync | `NcrService` → `/api/ncrs` | Yes | Yes | Partial | Partial | — | — | Real + offline | **WORKING** / **PARTIAL** |
| **NcrStatusUpdateComponent** | `/ncrs/:id/status` | Update status | Form | `PUT /api/ncrs/{id}/status` (typical) | Yes | Yes | Partial | Partial | — | — | Real | **PARTIAL** (verify template) |
| **RiskListComponent** | `/risks` | Risk register | Filters | `GET /api/risks` | Yes | Yes | Yes | Yes | — | — | Real | **WORKING** |
| **RiskFormComponent** | `/risks/new`, `/risks/:id` | Create/edit risk | Form | `POST/PUT /api/risks` | Yes | Yes | Partial | Partial | — | — | Real | **PARTIAL** |
| **AccessRequestsComponent** | `/admin/access-requests` | Growth queue approve/reject | List + modals | `GET/POST /admin/v1/access-requests*` | Yes | Yes (platform admin JWT) | Yes | Toast | Empty list | — | Real | **WORKING** |
| **TenantSettingsComponent** | `/admin/tenant-settings` | Tenant settings tabs | General / SP / users | `GET /api/tenants/current`, `GET/PUT /api/tenants/{id}`, `PUT /api/tenant/settings`, SharePoint PUT/test, users list/invite | Yes | Yes | Yes | Yes | Partial | — | Real | **WORKING** |
| **M365ConnectionComponent** | `/admin/m365-connection` | Connect Azure app | Form | `GET tenant`, `POST /api/tenants/{id}/connect-m365` | Yes | Yes | Yes | Yes | — | — | Real | **WORKING** |
| **BillingInfoComponent** | `/admin/billing-info` | Subscription info | Displays tenant; cancel **stub** | `GET /api/tenants/current`, `GET /api/tenants/{id}` | Yes | Yes | Yes | Yes | — | — | Real + **stub action** | **PARTIAL** |
| **PopiaReportComponent** | `/admin/popia-report` | POPIA trail + inventories | Trail via PopiaService + **dashboard doc lists** | `GET /api/popiatrail/report` ✓; **`GET /api/dashboard/popia-personal-info-documents` ✗**; **`GET /api/dashboard/documents-near-retention-expiry` ✗** | Trail yes; inventory **no** | Yes | Yes | Yes | Partial | Real where API exists | **PARTIAL** |
| **RecordsRetentionComponent** | `/admin/records-retention` | Past retention docs | List + archive | **`GET /api/documents/past-retention`** | **NOT in main API** | Yes | Yes | Yes | — | — | Real | **BROKEN** (404) |
| **ConsultantDashboardComponent** | `/consultant/dashboard` | Consultant summary | Cards | `GET /api/consultants/dashboard` | Yes (consultant policy) | Yes | Partial | Partial | — | — | Real | **PARTIAL** |
| **ConsultantClientsComponent** | `/consultant/clients` | Client list | List | `GET /api/consultants/me/clients` | Yes | Yes | Partial | Partial | — | — | Real | **PARTIAL** |
| **ConsultantBrandingComponent** | `/consultant/branding` | Branding CRUD | Form + uploads | `GET /api/consultants/branding` (**placeholder response**); **`PUT /api/consultants/branding`**; **`POST /api/consultants/branding/{logo|loginBanner}`** | GET exists as stub; **PUT/POST absent** | Yes | Partial | Partial | — | — | **Broken contract** | **BROKEN** |
| **AuditTemplatesComponent** | `/consultant/audit-templates` | Manage templates | CRUD | `/api/audits/templates*`, questions | Yes | Yes | Partial | Partial | — | — | Real | **PARTIAL** |
| **AuditRunComponent** | `/consultant/audit-run`, `:runId` | Run audit | Large flow | `/api/audits/runs*`, answers, evidence upload | Yes | Yes | Partial | Partial | — | — | Real | **PARTIAL** |
| **OfflineBannerComponent** | (in Layout) | Offline notice | Service worker / connectivity | Local | N/A | N/A | — | — | — | — | N/A | **WORKING** |
| **ToastComponent** | (in Layout) | Toasts | Inject service | N/A | N/A | N/A | — | — | — | — | N/A | **WORKING** |

**Layout — critical UX issues**

- Header uses **`MsalService` `activeAccount()` only** for “signed in” / display name. **Local JWT users** have no MSAL account → UI shows **“Sign in”** while they are already past `portalAuthGuard` — misleading.
- **`logout()`** clears tenant and calls **MSAL logout only** — **local JWT users are not cleared** via `AuthService.logout()` in this component.
- Sidebar link **`routerLink="/audits"`** has **no matching route** in `app.routes.ts` (only `/consultant/audit-*` and redirect). **Audits nav is broken** for tenant users.

---

## REPORT 2 — Forms audit

| Form name | Component | Fields | Validation | Submits to | Endpoint exists? | Success | Error | Status |
|-----------|-----------|--------|------------|------------|------------------|---------|-------|--------|
| Email login | Login | email, password | required, email | `POST /api/auth/login` | Yes | Navigate dashboard | Inline banner | OK |
| Signup step 1–3 | Signup | names, email, password, company, standards, plan | Angular validators | `POST /api/auth/register` | Yes | Success message | Inline | OK |
| Contact | Contact | name, company, email, message | required, lengths | `POST /api/public/contact` | Yes | `done` flag | Inline | OK |
| Forgot password | ForgotPassword | email | required, email | `POST /api/auth/forgot-password` | Yes | Message | Inline | OK |
| Reset password | ResetPassword | token, new password | required, strength | `POST /api/auth/reset-password` | Yes | Navigate login | Inline | OK |
| Verify email | VerifyEmail | (query token) | — | `POST /api/auth/verify-email` | Yes | Navigate | Inline | OK |
| Company setup | CompanySetup | profile, standards, invites | custom checks | `/api/onboarding/*` | Yes | Navigate | Inline | OK |
| User onboarding wizard | UserOnboardingPage | profile, org, standards, emails | step validation | `POST /api/tenant/onboarding/complete-wizard` | Yes | Step 5 / toast | Toast | OK |
| Tenant settings — general | TenantSettings | name, logo, color | validators | `PUT /api/tenant/settings` (+ load via tenants) | Yes | Toast / reload | Inline | OK |
| Tenant settings — SharePoint | TenantSettings | URL, client id, secret, library | `maxLength` | `PUT /api/tenant/sharepoint`, `POST .../test` | Yes | Messages | Inline | OK |
| Invite user | TenantSettings | email, role | basic | `POST /api/tenant/users/invite` | Yes | Reload directory | Inline | OK |
| M365 connection | M365Connection | client id/secret, tenant, SP ids | required | `POST /api/tenants/{id}/connect-m365` | Yes | Success string | Inline | OK |
| Document create/edit | DocumentForm | many | mixed | `/api/documents` CRUD + upload + workflow POSTs | Mostly yes | Navigation / toast | Mixed | PARTIAL (audit evidence) |
| NCR offline | NcrFormOffline | NCR fields | mixed | `POST /api/ncrs` (+ offline queue) | Yes | Navigate | Mixed | PARTIAL |
| NCR status | NcrStatusUpdate | status fields | — | `/api/ncrs/{id}/status` | Yes | — | — | PARTIAL |
| Risk form | RiskForm | risk fields | — | `/api/risks` | Yes | — | — | PARTIAL |
| Approve / reject access | AccessRequests | company name, plan / reason | basic | `/admin/v1/access-requests/{id}/approve|reject` | Yes | Toast + reload | Toast | OK |
| Consultant branding | ConsultantBranding | colors, URLs, files | loose | **Missing PUT/POST** | **No** | Client-side success | catch | **BROKEN** |
| Billing cancel | BillingInfo | confirm | — | **Stub only** (no API) | N/A | `alert` stub | — | **PARTIAL** |

---

## REPORT 3 — Navigation audit

### `routerLink` / sidebar / public header

| Where | Label | Route | Component exists? | Guard | Works? |
|-------|-------|-------|-------------------|-------|--------|
| Public header | Home | `/` | Yes | None | Yes |
| Public header | About | `/about` | Yes | None | Yes |
| Public header | Contact | `/contact` | Yes | None | Yes |
| Public header | **Request access** | `/signup` | Yes | None | **Label/copy mismatch** (signup vs “request access”) |
| Layout sidebar | Dashboard | `/dashboard` | Yes | portal + tenant + setup + onboarding | Yes |
| Layout sidebar | Documents | `/documents` | Yes | + module | Yes |
| Layout sidebar | Approvals | `/documents/approvals` | Yes | + module | Yes |
| Layout sidebar | NCRs | `/ncrs` | Yes | + module | Yes |
| Layout sidebar | Risks | `/risks` | Yes | + module | Yes |
| Layout sidebar | **Audits** | **`/audits`** | **No route** | N/A | **No — 404 / redirect to login** |
| Layout sidebar | Access requests | `/admin/access-requests` | Yes | portal + **platformAdminGuard** | Yes (if role) |
| Layout sidebar | Tenant settings | `/admin/tenant-settings` | Yes | portal + tenant + setup + onboarding | Yes |
| Layout sidebar | M365 | `/admin/m365-connection` | Yes | same | Yes |
| Layout sidebar | Billing | `/admin/billing-info` | Yes | same | Yes |
| Layout sidebar | Consultant * | `/consultant/*` | Yes | portal + tenant + setup + onboarding | Yes (role-dependent data) |
| Login | Forgot / Signup | `/forgot-password`, `/signup` | Yes | None | Yes |
| Catch-all | any unknown | → `/login` | — | — | Harsh for typos |

### Buttons that navigate (representative)

| Button label | Action | Destination | Works? |
|--------------|--------|-------------|--------|
| Dashboard shortcuts | `router.navigate` | `/documents`, `/ncrs/new`, `/risks`, audit run | Mostly yes; audit depends on module |
| Latest audit run | `navigateToAuditRun` | `/consultant/audit-run` | Yes if module; uses consultant path for **all** tenants with Audits |
| Document approvals shortcut | `navigateToDocumentApproval` | `/documents?workflowState=PendingApproval` | **Weak** — list does not read `workflowState` |
| POPIA widgets “View Report” | navigate | `/admin/popia-report` | Route ok; **widget data APIs missing** |
| Layout “Change Tenant” | `navigate` | `/tenant-selector` | Yes (non-consultant) |
| Billing “Cancel” / back | `navigate` | `/dashboard` | Yes |

---

## REPORT 4 — UI quality assessment

Per **page family** (not every duplicate route):

| Page / area | Visual design (1–10) | Mobile (1–10) | Loading | Error | Empty | A11y (basic) |
|-------------|------------------------|---------------|---------|-------|-------|--------------|
| Public (home, about, contact, signup) | 6 | 6 | Mixed | Mostly yes | N/A | **Fail** — skip links, focus rings, contrast not verified; forms lack consistent `aria-live` |
| Login | 6 | 6 | Yes | Yes | — | **Fail** — MSAL button only `data-testid` |
| Logged-in shell + dashboard | 6 | **4** | Good on dashboard | Mixed | Widget-driven | **Fail** — sidebar not responsive; semantic landmarks weak |
| Documents / NCR / Risks | 6 | 5 | Mixed | Often yes | Sometimes implicit empty | **Fail** |
| Admin tenant / M365 | 6 | 5 | Yes | Yes | — | **Fail** |
| POPIA / retention admin | 6 | 5 | Yes | Yes | Partial | **Fail** — tables + `alert()` for CSV |
| Consultant | 6 | 5 | Partial | Partial | — | **Fail** |

**Overall UI quality verdict**

- **Unpolished:** Mix of emoji icons, raw HTML controls, `alert()` for exports, placeholder consultant branding API, duplicated primary blues (`#1976d2` vs global `--primary-color: #007bff`), and **auth shell mismatch** for email users.
- **CSS / layout:** **No `@media` rules in `layout.scss`** — fixed sidebar + horizontal navbar likely **overflow** on small screens; **client switcher** `min-width: 220px` exacerbates this.
- **Broken / fragile:** **`/audits` nav**; **dashboard POPIA/retention widgets** (404); **records retention** page; **document audit evidence**; **consultant branding save/upload**; **documents list** ignoring `workflowState` query.
- **Unfinished interactions:** Billing cancellation stub; consultant GET branding returns **non-DTO placeholder JSON**; layout **Sign out** not wired to local JWT logout.

---

## REPORT 5 — Dead code

Safe deletion candidates (confirm in git before removal):

| Item | Reason |
|------|--------|
| `frontend/src/app/components/onboarding-wizard/*` | Selector never used in routes or templates; real flow is `user-onboarding-page`. |
| `frontend/src/app/guards/auth.guard.ts` | **MSAL-only** guard; routes use `portalAuthGuard`. |
| `frontend/src/app/features/ncrs/ncr-form/*` (**NcrFormComponent**) | **No route**; `ncr-form-offline` is the routed create flow. |
| `frontend/src/app/services/onboarding.service.ts` | Only imported by dead **onboarding-wizard** (`OnboardingService`); guards/components use `TenantService` / HTTP directly for `/api/onboarding/status`. |

**Not dead**

- `PopiaService` — used by `popia-report`.
- `DocumentsService.getDocumentsPastRetention` / `getDocumentAuditEvidence` — used, but **backend gaps** (fix API or remove UI).

**CSS “dead selectors”** — not exhaustively traced; onboarding-wizard SCSS is orphan with component.

**Pipes / directives** — none found under `frontend/src/app` (`@Pipe` / `@Directive` grep empty).

---

## REPORT 6 — PrimeNG suitability

**Finding:** `frontend/package.json` has **no `@angular/material`**. The portal uses **custom HTML + SCSS** (and MSAL). **`mat-*` usage: 0** (grep clean).

| Angular Material | Count in `frontend/src` | PrimeNG equivalent (for future work) |
|-------------------|-------------------------|--------------------------------------|
| (none) | **0** | N/A — adopt PrimeNG **fresh** (e.g. `p-table`, `p-dialog`, `p-button`, `p-toast`, `p-sidebar`, `p-fileupload`, `p-tabview`) |

**Migration effort interpretation:** This is **not** a Material→PrimeNG swap; it is **introducing a component library** + theming. Count replaced widgets ≈ all data tables, modals, file uploads, toasts (you already have a custom toast), and layout patterns.

---

## REPORT 7 — Theming gaps

**Files reviewed:** `frontend/src/styles.scss`, `frontend/src/app/shared/styles/public-brand.scss`, all `*.scss` under `frontend/src/app` (39 files). **No** `theme.scss` / Angular Material theme.

| Question | Finding |
|----------|---------|
| Hardcoded colours | Yes — e.g. layout `#1976d2`, `#ff9800`, dashboard/card SCSS, login; global `:root` defines `--primary-color: #007bff` but layout prefers `--maemo-primary-color` / Material-ish blue — **inconsistent**. |
| Spacing scale | **No** shared spacing tokens; ad hoc `rem`/`px`. |
| Conflicting styles | **Two primary colour concepts** (`--primary-color` vs `--maemo-primary-color` / hardcoded). |
| Dead CSS | Likely **onboarding-wizard** styles; otherwise not fully traced. |
| Material theme | **Not used** — default browser controls. |

---

## Closing lists

### PAGES TO REBUILD FROM SCRATCH

- **`/consultant/branding`** — backend contract missing; placeholder GET; save/upload nonfunctional.
- **`/admin/records-retention`** — depends on **non-existent** `GET /api/documents/past-retention` on main API.
- **Layout shell header auth** — should unify MSAL + `AuthService` (display name, sign-out, signed-in state).

### PAGES TO POLISH (minor / medium fixes)

- **Dashboard** — wire POPIA personal + retention widgets to real endpoints (or remove calls).
- **`/documents`** — honor `workflowState` query or change dashboard link to `/documents/approvals`.
- **`/admin/popia-report`** — same dashboard sub-APIs for inventory sections.
- **Document detail** — hide or fix audit evidence export until API exists.
- **Sidebar** — replace **`/audits`** with `/consultant/audit-run` or role-based target.
- **Public header** — relabel CTA (“Create account” vs “Request access”).
- **Billing** — remove or gate stub cancel UX.

### PAGES TO DELETE

- None mandatory **routes** to delete; consider removing **orphan components** (onboarding-wizard, ncr-form, auth.guard, unused OnboardingService) **after** team confirmation.

### ESTIMATED MIGRATION EFFORT TO PRIMENG

**4–8 weeks** (one experienced Angular dev), assuming: PrimeNG install + theme, refactor of 8–12 high-traffic screens (documents, NCR, risks, dashboard, admin tables), replace custom toasts/modals where beneficial, responsive shell rewrite, and QA. **Wider if** audit/consultant flows get full component coverage.

### RECOMMENDED PAGE REDESIGN PRIORITY ORDER

1. **App shell** — responsive layout, unified auth UX, fix `/audits` link, local JWT logout.
2. **Dashboard** — remove or implement POPIA/retention API alignment.
3. **Documents** — query-param filters + document form evidence feature vs API.
4. **Consultant branding** — implement API or remove UI until ready.
5. **Records retention** — API + UI or hide nav entry.
6. **PrimeNG pilot** — tables + dialogs on Documents + NCR list (highest ROI).

---

*End of Maemo UI audit (Prompt 2).*
