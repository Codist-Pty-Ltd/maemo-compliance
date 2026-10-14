# CODIST CONTEXT SYNC v2 — May 2026

_Paste at the start of any new Claude/Cursor agent chat when you want studio-wide context._

```
CODIST CONTEXT SYNC v2 — May 2026

Founder: Ntokozo Banda, Johannesburg, South Africa
Studio: Codist (Pty) Ltd
Stack: .NET 8, Angular, TypeScript, PostgreSQL,
       Flutter, Next.js, NestJS, Python, Docker

════ SERVERS ════

billable (65.109.7.45)
  SSH: ssh -i ~/.ssh/billable_hetzner billable@65.109.7.45
  Apps: Billable SaaS, War Room
  
codist2 (162.55.188.252)
  SSH: ssh root@162.55.188.252
  Apps: The Record, EngineIQ

════ LIVE PRODUCTS ════

Billable        app.mybillable.co.za
  .NET 8 + Angular + Flutter + PostgreSQL
  .env: /home/billable/billable/deploy/.env
  Payments: Paystack (primary), PayFast legacy only
  PaymentsController NOT registered in Program.cs
  Public invoice pay: POST /api/public/invoices/{token}/pay

War Room        warroom.codist.co.za
  React + Node.js + SQLite
  .env: /opt/warroom/server/.env

The Record      therecord.co.za
  Next.js 15 + NestJS + FastAPI + PostgreSQL
  .env: /opt/therecord/app/.env
  DATABASE_URL: # must be encoded as %23
  Seeds: node dist/database/seeds/index.js
  Migrations: node dist/database/run-migrations.js

EngineIQ        engineiq.co.za
  .NET 8 + Next.js + RabbitMQ + PostgreSQL + Redis
  .env: /opt/engineiq/.env
  GitHub App: engineiq-co-za (ID 3614392)
  Installation: 129947711 (ntokyb personal)
  Tenant: Codist (technical@codist.co.za)
  Deploy: docker compose --profile platform up -d
  Migrations: docker compose --profile migration run --rm engineiq-migrator
  Worker needs manual restart after boot (RabbitMQ race)

════ CRITICAL RULES ════

NEVER use docker restart — does not reload .env
ALWAYS use docker compose down && up -d for .env changes
Passwords with # → encode as %23 in connection strings
Production containers have dist/ only, not src/
Never suggest AWS/GCP — Hetzner only
Never suggest Tailwind or component libraries
Read .cursorrules before every change
Check which server before any infra suggestion

════ CURRENT PRIORITIES ════

Billable:
  Paystack go-live (switch to live keys)
  Overdue invoice reminders (Day 1/6/11/15)
  Rate limiting on /api/auth/login
  Fix Unsullied + VerticalSyml trial access
  Statement of Account PDF
  Meta WhatsApp verification in progress

EngineIQ:
  UI build in progress (4 portals)
  Marketing, Client Portal, Admin, Support
  RabbitMQ depends_on fix needed in docker-compose

Codist website:
  codist-website Node.js/EJS app for cPanel
  5 pages: /, /work, /services, /about, /contact
```

## Cursor / VS Code snippet (optional)

1. **Command Palette** → “Snippets: Configure User Snippets” → e.g. `markdown.json` or `plaintext`.
2. Add a prefix such as `codistctx` and paste the block above as the body.
3. Or bind **“Insert Snippet”** to a key in Keyboard Shortcuts.

This file lives in-repo for copy-paste; keep the repo private if it contains sensitive infra details.
