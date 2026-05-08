<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **workspace** (2394 symbols, 4178 relationships, 93 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/workspace/context` | Codebase overview, check index freshness |
| `gitnexus://repo/workspace/clusters` | All functional areas |
| `gitnexus://repo/workspace/processes` | All execution flows |
| `gitnexus://repo/workspace/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

---

# Project: Salon Noon Management System

A monorepo with **2 Next.js apps** + automation layer for a premium salon business.

## Architecture

```
saloooon/                          ← workspace root (this repo)
├── saloon-mostafa/                ← CRM Admin Dashboard (Next.js)
│   ├── src/app/api/               ← 25+ API routes (all auth-guarded)
│   ├── src/lib/auth.ts            ← Centralized auth: getAuthUser()
│   ├── src/lib/supabase.ts        ← Centralized DB: getServiceRoleClient()
│   └── src/components/            ← Dashboard UI components
├── gardenia-website/              ← Public Storefront (Next.js)
│   ├── src/app/                   ← Customer-facing pages
│   └── src/app/api/               ← Public API routes
├── n8n-workflow.json              ← WhatsApp bot automation
├── n8n-system-prompt.md           ← AI booking assistant prompt
└── .gitnexus/wiki/                ← 📖 Auto-generated documentation
```

## Git Repos (2 separate repos)

| Project | Branch | Remote |
|---------|--------|--------|
| `saloon-mostafa/` (CRM) | `main` | `drjimmy1990/saloon-mostafa.git` |
| `gardenia-website/` (Storefront) | `master` → `website` | same repo, `website` branch |

## 📖 Wiki — Read BEFORE Making Changes

AI-generated documentation lives in `.gitnexus/wiki/`. **Read the relevant page before modifying any module.**

| When working on... | Read this wiki page |
|---------------------|---------------------|
| CRM API routes | [admin-api-layer.md](.gitnexus/wiki/admin-api-layer.md) |
| CRM dashboard UI | [admin-dashboard-frontend.md](.gitnexus/wiki/admin-dashboard-frontend.md) |
| CRM components | [admin-dashboard-components.md](.gitnexus/wiki/admin-dashboard-components.md) |
| Storefront pages | [customer-website-frontend.md](.gitnexus/wiki/customer-website-frontend.md) |
| Storefront components | [customer-website-components.md](.gitnexus/wiki/customer-website-components.md) |
| Storefront API | [customer-api-layer.md](.gitnexus/wiki/customer-api-layer.md) |
| Auth, Supabase, shared libs | [shared-infrastructure-libs.md](.gitnexus/wiki/shared-infrastructure-libs.md) |
| Database schema | [database-migrations.md](.gitnexus/wiki/database-migrations.md) |
| n8n / WhatsApp bot | [automation-workflows.md](.gitnexus/wiki/automation-workflows.md) |
| Full overview | [overview.md](.gitnexus/wiki/overview.md) |

## Security Rules

- **ALL CRM API routes** use `getAuthUser()` from `src/lib/auth.ts` — never bypass this
- **Admin-only routes** (`users/[id]`, `clients/export`, `settings POST`) check `user.role === 'admin'`
- **Settings GET** is intentionally public (consumed by the storefront)
- **Never use inline `createClient()`** — always use `getServiceRoleClient()` from `src/lib/supabase.ts`

## Regenerate Wiki After Code Changes

```powershell
# 1. Re-index the codebase
docker exec gitnexus-server node /app/gitnexus/dist/cli/index.js analyze /workspace

# 2. Regenerate wiki (incremental)
docker exec gitnexus-server node /app/gitnexus/dist/cli/index.js wiki /workspace --base-url http://host.docker.internal:11434/v1 --model gemma4:31b-cloud --api-key ollama
```
