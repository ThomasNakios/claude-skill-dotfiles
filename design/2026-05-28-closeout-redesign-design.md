# Closeout Redesign — Design Spec

**Status:** Approved (brainstorming complete; ready for implementation plan)
**Author:** Thomas Nakios (with Claude)
**Date:** 2026-05-28
**Scope:** Capital Manager (canary) + 14 other projects on Thomas's 6 workstations

---

## 1. Summary

Rationalize the end-of-session command family into 5 global, project-aware slash commands. Replace the current ~8 overlapping commands (`closeout`, `gate`, `handoff`, `endofday`, `daily-end`, `checkpoint`, `project-hygiene`, `end-work`) with a tight set:

- **`/gate`** — quality gate (build, lint, types, design) — blocks on failure
- **`/hygiene`** — project audit (stale files, naming, governance) — informs
- **`/closeout`** — session closure, composes gate + hygiene, writes `.claude/session.md`
- **`/depart`** — workstation departure (git push + session.md freshness check)
- **`/arrive`** — workstation arrival (git pull + post-pull hooks)

A counterpart `/resume` reads `.claude/session.md` to restore session context.

The skills live globally at `~/.claude/commands/`. Project-specific behavior is driven by `.claude/claude.yaml` in each repo. A bootstrap flow (`/closeout --init`) extracts the config from existing project knowledge (`CLAUDE.md`, governance docs, the current closeout checklist).

## 2. Motivation

### Current pain points (capital-manager, observed)

- **Overlapping commands:** `closeout`, `endofday`, `daily-end`, `end-work`, `checkpoint`, `project-hygiene`, `gate` all do partially overlapping work. Mental model is unclear; users don't know which to invoke when.
- **Project-local checklists don't travel:** Capital-manager's 600-line `closeout.md` lives only in this repo. Other 14 projects don't get the benefit.
- **Hygiene + standards aren't enforced together:** Standards docs (`STANDARDS_FILE_STRUCTURE.md`, `naming-conventions.md`) aren't checked by `closeout`; only `project-hygiene` covers part of it.
- **Session continuity is ad-hoc:** No persistent "where did I leave off" artifact for the next session.
- **`NEXT.md` has grown to 63KB** because there's no separation between session-level notes and durable roadmap.
- **No cross-workstation discipline:** 6 workstations × 15 projects = ad-hoc behavior across machines.

### Goals

- **One central command per intent:** `closeout` = "I'm done"; `depart` = "leaving this machine"; `gate` = "is this mergeable?"
- **Global but project-aware:** Skills live in `~/.claude/`; configs live in each repo.
- **Preserve existing project knowledge:** Bootstrap mines `CLAUDE.md`, governance docs, existing checklists into the config.
- **Symmetric pairs:** `closeout`/`resume` for session boundaries; `depart`/`arrive` for workstation boundaries.
- **Schema-versioned + drift-aware:** Configs can evolve; CLAUDE.md drift becomes visible, not silent.

### Non-goals

- Reinventing `.cursorrules`, `.aider.conf`, or general AI-assistant config.
- Auto-fixing standards violations (warn/report only; fixes are human-driven).
- Cross-machine session sync (each machine has its own `.claude/session.md`).
- Real-time multi-user collaboration (`session.md` is single-user, single-machine).

## 3. Architecture

### Global skeleton + project config

```
~/.claude/commands/                  # Global skill (syncs across workstations via git)
  ├─ closeout.md
  ├─ gate.md
  ├─ hygiene.md
  ├─ depart.md
  ├─ arrive.md
  └─ resume.md
~/.claude/VERSION                    # Current skill version (synced)

<each project repo>/.claude/
  ├─ claude.yaml                     # Project config (committed to git)
  ├─ session.md                      # Working memory (gitignored)
  └─ session.template.md             # Optional override of default template
```

### Behavior

1. Global `closeout` is invoked from any project directory.
2. It looks for `.claude/claude.yaml`. If missing → auto-discovery mode (greenfield).
3. Executes the tier: `gate` → `hygiene` → security audit → write `.claude/session.md` → prompt `NEXT.md` updates.
4. Higher-tier commands compose lower-tier ones (closeout calls gate + hygiene; doesn't re-implement them).
5. Output is structured: ✓/✗ per check, blockers explicit, plus written `session.md`.

### Why this wins for multi-workstation × multi-project

| Concern | This design |
|---|---|
| Works on every workstation | ✅ `~/.claude/` syncs via git |
| Works on every project | ✅ `claude.yaml` travels with repo |
| Project rules respected | ✅ Config is explicit |
| New workstation: zero setup | ✅ Skill arrives with `~/.claude/` sync |
| New project: low setup | ✅ One `/closeout --init` |
| Failure debug-ability | ✅ Config is grep-able |

## 4. Command Taxonomy (final, post-consolidation)

| Tier | Command | Owns | Composes |
|---|---|---|---|
| **Quality gate** | `gate` (+ `--quick`) | Build, types, lint, design verification | — |
| **Project audit** | `hygiene` | Stale files, gitignore, naming, governance, deprecated imports | — |
| **Session closure** | **`closeout`** (+ `--init`, `--daily`, `--config`, `--quick`) | Orchestrate gate + hygiene + security; write `session.md` | gate + hygiene |
| **Workstation depart** | `depart` | Git commit + push; check session.md freshness | — |
| **Workstation arrive** | `arrive` | Git pull + post-pull hooks; suggest resume | — |
| **Session start** | `resume` (adjacent) | Read `session.md`, restore context | — |

### Failure semantics

- **Hard-fail (blocks):** gate failure, security audit failure, unpushed git in `depart` → exit non-zero, no session.md written.
- **Soft-fail (warns, continues):** hygiene findings, standards violations → session.md written with `blockers` / `followups` section listing warnings.
- **Skip:** any check can be disabled per-project via `skip:` in the config.

### Deprecations

| Command | Replacement | Cutover |
|---|---|---|
| `end-work` | `gate` | Already done |
| `checkpoint` | `gate --quick` | 30-day shim with deprecation notice |
| `project-hygiene` | `hygiene` | 30-day shim |
| `endofday` | `closeout --daily` | 30-day shim |
| `daily-end` | `closeout --daily` | 30-day shim |
| `handoff` | `depart` | 30-day shim |
| `sync-workstation` | `arrive` | 30-day shim |
| Project-local `.claude/commands/closeout.md` | Shim → global; eventually delete | After 30-day grace |

## 5. Bootstrap / Retrofit Flow

**Entry point:** `/closeout --init` (also auto-triggered if `/closeout` runs in a project with no config — prompts before doing anything).

### Two-phase extraction

**Phase 1 — Mechanical scan (no LLM):**

- Read `package.json` → discover scripts: build, lint, test, test:e2e, verify:design
- Detect framework: Next.js, Supabase, Python, etc.
- Find `STANDARDS_*.md`, `docs/governance/**/*.md`, `CLAUDE.md` → list as "standards docs"
- Find existing `.claude/commands/{closeout,verify,handoff,project-hygiene}.md` → mark for extraction

**Phase 2 — Agent extraction (LLM, via Explore subagent):**

Prompt the agent to read the marked files and produce a draft config with sections for:

- `security_rules` — NON-NEGOTIABLES from `CLAUDE.md` with `source:` pointers
- `hygiene.patterns` — stale-file patterns from existing `project-hygiene.md`
- `hygiene.file_structure` — naming/structure rules from `STANDARDS_FILE_STRUCTURE.md`
- `gate.commands` — quality-gate commands from existing `closeout.md` + `package.json`
- `closeout.session_md` — template / paths

### Review gate (HARD)

1. Bootstrap writes draft to `.claude/claude.yaml.proposed` (not the real path).
2. Presents diff + summary: "Extracted N security rules, M standards docs, K hygiene patterns from these sources: …"
3. User reviews, edits, then `mv .proposed → real path` (or rejects and re-runs).
4. Commit the config to the repo so it travels.

### For capital-manager specifically

| Source | Extracted into |
|---|---|
| `.claude/commands/closeout.md` (current 600-line checklist) | `gate.commands`, `security.rules`, `hygiene.patterns` |
| `STANDARDS_FILE_STRUCTURE.md` | `hygiene.file_structure` |
| `docs/governance/standards/naming-conventions.md` | `hygiene.file_structure.naming_rules` |
| `docs/governance/standards/auth-patterns.md` | `security.rules` (linked, not duplicated) |
| `CLAUDE.md` (dark mode, tenant isolation, role checking) | `security.rules`, `hygiene.file_structure` |
| `package.json` scripts | `gate.commands` |
| `.claude/commands/project-hygiene.md` | `hygiene.patterns` |
| `.claude/commands/handoff.md` | Reference (kept as separate `/depart` command) |

## 6. `.claude/session.md` Format

```markdown
---
schema_version: 1
session_id: 2026-05-28-1432
written_at: 2026-05-28T14:32:11-05:00
written_by: closeout v0.1.0
project: capital-manager
branch: production
last_commit: 11ec164a
status: clean              # clean | warnings | blockers
checks:
  gate: pass
  hygiene: warn            # pass | warn | fail | skipped
  security: pass
counts:
  files_changed: 23
  hygiene_warnings: 4
  followups: 2
---

## Intent
What this session was about, in one or two sentences.

## Done
- Specific things completed (link commits when relevant: 11ec164a)

## In-flight
- Work started but not finished. Be specific about WHERE — file:line if applicable.

## Pickup
Concrete next-session guidance. Read this first when resuming.

## Blockers
Things preventing progress (if any).

## Followups
TODOs surfaced this session, not addressed.

## Decisions
Choices made that future-you should know about.
```

### Lifecycle rules

- **One file at a time.** Overwritten each closeout. No log history — git provides that.
- **Gitignored.** Working memory, not project metadata.
- **Same-machine only (resolved 2026-05-29, finding F5).** session.md does NOT
  travel to other workstations. It answers "where was I on THIS box." The
  **cross-machine handoff is the pushed git commits** — `/depart` ensures they're
  pushed; `/resume` on a different machine reconstructs from `git log` and uses a
  local session.md only if one exists. The vault's own
  `session-handoff.md` remains the canonical cross-machine doc for *vault* work;
  the closeout family does not auto-write project state into it. This split (a)
  fixes the original conflation, (b) avoids committing working-notes churn to
  project branches, (c) sidesteps the Obsidian-quit gating on vault writes, and
  (d) scales to all 15 projects with zero new machinery.
- **Branch-aware warning:** if `branch` in existing session.md differs from current branch, `resume` warns.
- **Stale detection:** if `written_at` is >7 days old, `resume` flags it.
- **Draft-then-confirm:** closeout drafts body sections from session context; user reviews/edits before write.

## 7. Help Support

Every command supports the same conventions:

| Flag | Behavior |
|---|---|
| `--help`, `-h`, `help` | Print structured help; do not execute |
| (no args) | Run with project defaults |
| `--dry-run` | Show what would execute without doing it |
| `--config <path>` | Use a non-default config file (closeout only) |

### Format (standardized)

Every command's `.md` opens with a structured `## Help` section. First instruction in the file: *"If args contain `--help`, `-h`, or `help`, render the Help section and stop."* Without this explicit instruction, agent-honored arg parsing is wishful.

```
$ /closeout --help

Project:   capital-manager
Config:    .claude/claude.yaml (schema v1, last bootstrap: 2026-05-28)
Status:    ✓ CLAUDE.md unchanged since bootstrap

WILL RUN
  gate    npm run build · npm run lint · npm run type-check · npm run gate:design
  hygiene  7 patterns (stale files, gitignore gaps, console.log, TODO scans, ...)
  security 4 non-negotiables (tenant_id, soft-delete, dark: prefix, requireTenantAuth)
  artifact .claude/session.md  (gitignored)

USAGE
  /closeout                    Run all checks above
  /closeout --daily            Also write docs/testing/daily/2026-05-28.md
  /closeout --init --refresh   Re-bootstrap from CLAUDE.md
  /closeout --quick            Skip gate; hygiene + session.md only
  /closeout --config X         Use custom config path
  /closeout --dry-run          Show what would happen

FAMILY
  /gate   Quality gate
  /hygiene  Project audit
  /depart   Workstation departure
  /arrive   Workstation arrival
  /resume   Session start (reads session.md)
```

### Generic mode (no config)

```
Project: <name>  (no config — generic mode)

This project has no .claude/claude.yaml. Closeout will run in generic mode
using auto-discovery. For project-specific checks, run:

    /closeout --init

[rest of help...]
```

### Failure → help cross-reference

When a command fails, output includes a pointer ("See `/gate --help` for details"). Hints are owned by the global skill, not per-project config — ensures consistency across all 15 projects.

## 8. Config Schema (`.claude/claude.yaml`)

### Top-level structure

```yaml
schema_version: 1                  # required; bumps on breaking changes

project:
  name: capital-manager
  type: nextjs-supabase
  claude_md_path: ./CLAUDE.md
  claude_md_hash: <sha256>         # written at bootstrap; checked each run
  bootstrapped_at: 2026-05-28T14:32:00Z
  bootstrapped_by: closeout v0.1.0

gate: { ... }                    # quality gate (hard-fail)
hygiene: { ... }                   # project audit (soft-fail)
security: { ... }                  # non-negotiables (hard-fail)
closeout: { ... }                  # session.md, NEXT.md prompts
depart: { ... }                    # workstation departure
arrive: { ... }                    # workstation arrival
```

### `gate` section

```yaml
gate:
  commands:
    - { name: build,   cmd: "npm run build",         required: true }
    - { name: lint,    cmd: "npm run lint",          required: true }
    - { name: types,   cmd: "npx tsc --noEmit",      required: true }
    - { name: design,  cmd: "npm run gate:design", required: true }
    - { name: test,    cmd: "npm test",              required: false }
  quick_subset: [lint, types]      # what `--quick` runs
  parallel: true
  fail_fast: true
```

### `hygiene` section

```yaml
hygiene:
  patterns:
    - name: stale-migration-results
      kind: files
      glob: "migration-result-*.json"
      action: suggest-delete

    - name: console-log
      kind: grep
      pattern: 'console\.log'
      include: ["**/*.ts", "**/*.tsx"]
      exclude: ["node_modules/**", ".next/**", "__tests__/**"]
      action: warn

    - name: todo-fixme
      kind: grep
      pattern: 'TODO|FIXME'
      include: ["**/*.ts", "**/*.tsx"]
      action: report

  gitignore_required:
    - "*.tsbuildinfo"
    - ".env.production"
    - "migration-result-*.json"

  file_structure:
    forbidden_filenames: ["utils.ts", "helpers.ts", "misc.ts", "common.ts"]
    naming_rules:
      - { pattern: "components/**/*.tsx", case: "PascalCase" }
      - { pattern: "lib/**/*.ts",         case: "kebab-case" }
      - { pattern: "lib/hooks/use-*.ts",  case: "kebab-case" }
    location_rules:
      - { kind: server-action, must_live_in: "app/actions/" }
      - { kind: api-route,     must_live_in: "app/api/" }

  governance:
    docs_must_have_header: "Last Updated"
    docs_max_lines: 250
    docs_dir: "docs/governance/"
```

### `security` section

```yaml
security:
  rules:
    - name: tenant-isolation
      description: "Every supabase query must filter by tenant_id"
      check:
        kind: grep-required-pair
        anchor: '\.from\([^)]+\)'
        required_within_lines: 5
        required_pattern: 'eq\([\'"]tenant_id[\'"]'
        include: ["app/**/*.ts", "lib/**/*.ts"]
        exclude: ["app/api/health/**", "**/*.types.ts"]
      source: "CLAUDE.md#tenant-isolation"

    - name: no-dark-prefix
      description: "Tailwind dark: prefix forbidden — use semantic tokens"
      check:
        kind: grep-forbidden
        pattern: '\sdark:'
        include: ["**/*.tsx", "**/*.css"]
      source: "CLAUDE.md#dark-mode-rules"

    - name: require-tenant-auth
      description: "Server actions must call requireTenantAuth()"
      check:
        kind: grep-required
        in_files: "app/actions/**/*.ts"
        required_pattern: 'requireTenantAuth\('
      source: "docs/governance/standards/auth-patterns.md"

    - name: soft-delete-filter
      description: "Queries must filter is_deleted = false"
      check:
        kind: grep-required-pair
        anchor: '\.from\([^)]+\)'
        required_within_lines: 10
        required_pattern: 'is_deleted'
      source: "CLAUDE.md#soft-deletes"
```

Each rule has a `source:` pointer back to the doc that defines it.

### `closeout` section

```yaml
closeout:
  session_md:
    path: ".claude/session.md"
    template: ".claude/session.template.md"   # optional override
    stale_threshold_days: 7
    draft_then_confirm: true

  next_md:
    path: "NEXT.md"
    prompt_on_completion: true
    auto_update: false

  daily_report:
    enabled: true
    path_template: "docs/testing/daily/{YYYY-MM-DD}.md"
```

### `depart` and `arrive` sections

```yaml
depart:
  remote: origin
  protected_branches: ["production", "staging"]
  require_session_md_fresh: true
  session_md_freshness_hours: 4

arrive:
  pull_strategy: rebase
  post_pull_hooks:
    - { if_changed: "package.json",         run: "npm install" }
    - { if_changed: "supabase/migrations/", run: "npx supabase db reset" }
  suggest_resume: true
```

### Schema validation behavior

| Condition | Behavior |
|---|---|
| Missing file | Auto-discovery mode; suggest `/closeout --init` |
| Malformed YAML | Hard-fail with line number + error |
| `schema_version` missing | Treat as v0; suggest migration to v1 |
| `schema_version` newer than skill | Hard-fail: "skill out of date; update `~/.claude/`" |
| `schema_version` older than skill | Warn + offer migration: `/closeout --init --migrate` |
| `claude_md_hash` mismatch (drift) | Warn in `--help` and at run start |
| Unknown keys | Warn but proceed; forward-compatible |

### Greenfield defaults (auto-discovery)

When `.claude/claude.yaml` doesn't exist, build an in-memory config:

- `gate.commands`: detected from `package.json` scripts + `tsc` if `tsconfig.json` exists
- `hygiene.patterns`: standard set (console.log, TODO/FIXME, .DS_Store, large files)
- `security.rules`: empty + warning: "no security rules configured — bootstrap with `/closeout --init`"
- `closeout.session_md.path`: `.claude/session.md` (always)

Greenfield mode is honestly labeled in `--help`. No silent guessing.

## 9. Migration Plan

### Phased rollout

```
Phase 0 — Foundations (once)
  ├─ Write global skill files: ~/.claude/commands/{closeout,gate,hygiene,depart,arrive,resume}.md
  ├─ Build schema validator
  ├─ Build bootstrap logic (closeout --init)
  ├─ Stamp ~/.claude/VERSION
  └─ Document workstation sync mechanism

Phase 1 — Canary on capital-manager (week 1)
  ├─ /closeout --init on capital-manager
  ├─ Review extracted .claude/claude.yaml.proposed
  ├─ Accept; commit
  ├─ Battle-test for ~1 week
  └─ Iterate on global skill

Phase 2 — Rollout to 14 other projects (weeks 2-4)
  ├─ Per-project /closeout --init
  ├─ Cross-project patterns inform greenfield defaults
  └─ Each project commits its own .claude/claude.yaml

Phase 3 — Deprecation (week 5+)
  ├─ Project-local closeout.md → shim
  ├─ Old commands → shims (checkpoint, project-hygiene, endofday, daily-end)
  ├─ Rename handoff → depart, sync-workstation → arrive
  └─ After 30 days: delete all shims

Phase 4 — Sustaining
  ├─ ~/.claude/VERSION bumps on each global-skill change
  ├─ /closeout flags drift (schema vs current skill)
  └─ /closeout --init --refresh on CLAUDE.md change
```

### Per-project migration checklist

```
□ Backup current .claude/commands/closeout.md and related files
□ Run /closeout --init
□ Review .claude/claude.yaml.proposed:
    - All build/lint/test commands captured?
    - All security non-negotiables extracted from CLAUDE.md?
    - Hygiene patterns match existing project-hygiene.md?
    - source: pointers trace back to correct docs?
□ Accept: mv .proposed → .claude/claude.yaml
□ Add .claude/session.md to .gitignore
□ Commit .claude/claude.yaml
□ Replace old commands with shims (with deprecation notices):
    closeout.md → "Use global /closeout"
    checkpoint.md → "Use /gate --quick"
    project-hygiene.md → "Use /hygiene"
    endofday.md → "Use /closeout --daily"
    daily-end.md → "Use /closeout --daily"
    handoff.md → "Use /depart"
    sync-workstation.md → "Use /arrive"
□ For projects with sync:ai pattern: update docs/ai/commands/ sources + npm run sync:ai
□ Smoke test: /closeout --help, /gate --quick, /hygiene
□ Full test: /closeout on a real session, verify .claude/session.md is written
□ Commit
```

### Workstation sync (6-machine problem)

Recommended mechanism: `~/.claude/` as a git repo.

```
~/.claude/  →  git repo ("claude-dotfiles")
  ├─ commands/         # synced
  ├─ skills/           # synced
  ├─ CLAUDE.md         # synced
  ├─ VERSION           # synced
  ├─ memory/           # gitignored (per-machine)
  ├─ projects/         # gitignored (per-machine state)
  └─ shell-snapshots/  # gitignored
```

Why git over rsync/cloud:
- Version history (rollback if a skill change breaks)
- Conflict detection (catches divergent edits)
- Same pattern as KnockersNoggin vault
- Works offline; resyncs on next push

### Risk mitigation

| Risk | Mitigation |
|---|---|
| Bootstrap extracts wrong rules | Review gate (`.proposed` file); user reviews diff |
| Global skill breaks workflow | `~/.claude/VERSION` lets you pin; rollback via `git revert` |
| Config drift from CLAUDE.md | `claude_md_hash` check warns at every run |
| Workstation desync | `VERSION` check in `/closeout --help` flags it |
| Project lacks rich existing knowledge | Greenfield defaults + warning |
| Schema evolution breaks old configs | `schema_version` + `--init --migrate` flow |

### Success criteria

- [ ] All 5 commands work on capital-manager via global skill
- [ ] `.claude/claude.yaml` validates against schema_version 1
- [ ] Every security rule traces back to its source doc via `source:`
- [ ] `/closeout --help` shows project-aware preview
- [ ] `.claude/session.md` is gitignored and being written on real sessions
- [ ] `~/.claude/` synced to all 6 workstations via git
- [ ] Old commands deprecated with clear migration paths
- [ ] 15 projects each have their own `.claude/claude.yaml`

## 10. Open Questions

- **Sync mechanism for `~/.claude/`** — git repo recommended, but exact repo location (GitHub private repo? Local-only synced via vault?) is TBD.
- **`/closeout --init --refresh` semantics** — when re-bootstrapping after CLAUDE.md change, do we preserve human edits to `claude.yaml` or fully regenerate? Probably 3-way merge with user confirmation. Detailed mechanism TBD.
- **Concurrent branches** — single `.claude/session.md` works for one-feature-branch-at-a-time. If concurrent branches become common, escalate to `.claude/sessions/<branch>.md`. Trigger TBD.
- **Cross-tool integration** — `.claude/session.md` as a standard handoff artifact for Cursor/Aider compatibility is a future opportunity, not in scope now.

## 11. References

- Current `closeout.md`: `.claude/commands/closeout.md` (will be replaced)
- Source doc: `docs/guides/closeout-checklist.md`
- Standards: `STANDARDS_FILE_STRUCTURE.md`, `docs/governance/standards/naming-conventions.md`
- Security: `docs/governance/standards/auth-patterns.md`, `CLAUDE.md` (NON-NEGOTIABLES)
- Existing commands being deprecated:
  - `.claude/commands/end-work.md` (already deprecated)
  - `.claude/commands/checkpoint.md`, `endofday.md`, `daily-end.md`
  - `.claude/commands/project-hygiene.md`
  - `.claude/commands/handoff.md`, `sync-workstation.md`
- Related: `NEXT.md` (roadmap, stays as-is; closeout prompts updates)

---

*Brainstorming validated through 7 sections with explicit user approval at each. Ready for `writing-plans` to produce an implementation plan.*

---

## 12. Implementation Outcome (2026-05-29 update)

Phase 0 + Phase 1 (canary) shipped. Canary battle-test phase now active.

### What's shipped

| Component | Status | Notes |
|---|---|---|
| Global skill files in `~/.claude/commands/` | ✅ Shipped (7 commands) | `closeout`, `gate` *(renamed from `verify`)*, `hygiene`, `depart`, `arrive`, `resume`, `family` |
| Discoverability help command | ✅ Shipped (`/family`) | Added post-design after `/help` collision found |
| `~/.claude/docs/claude-yaml-schema.md` | ✅ Shipped | Includes `shell` check kind added during canary |
| `~/.claude/docs/session-template.md` | ✅ Shipped | YAML frontmatter + 7 body sections |
| Workstation sync via git | ✅ Shipped | https://github.com/ThomasNakios/claude-skill-dotfiles |
| Idempotent sync script | ✅ Shipped (`~/.claude/sync.sh`) | State-aware: fresh / migrate / synced-clean / synced-dirty / wrong-remote |
| `/depart` + `/arrive` cross-repo composition | ✅ Shipped | Obsidian-aware vault sync (process detection) |
| Canary config for capital-manager | ✅ Accepted | `.claude/claude.yaml` (commit `d251136a`) |

### Changes from design during implementation

| Change | Reason |
|---|---|
| `/verify` → `/gate` | Collision with built-in Claude Code `/verify` skill discovered during Phase 0 |
| Added `/family` command | Standalone discoverability after dropping `/help` (built-in collision) |
| Added `shell` check kind to schema | Capital-manager has rich existing audit scripts; reusing them beats reinventing with greps |
| Canary config: `gate.parallel: false` | 4 commands × 4GB heap = 16GB peak; exceeds 16GB-class Mac RAM |
| Canary config: no destructive `db reset` in arrive hooks | Safety — would wipe local seed/test data on migration pull |
| Added: cross-repo composition with vault sync (Obsidian-aware) | Workstation boundary cleanly syncs project + `~/.claude/` + vault |

### Open questions resolved during canary

| Question (§11) | Resolution |
|---|---|
| Sync mechanism for `~/.claude/` | GitHub private repo (`claude-skill-dotfiles`); `sync.sh` handles all states idempotently |
| `/closeout --init --refresh` semantics | Specified in closeout.md: 3-way merge with user confirmation. Implementation deferred until needed. |

### Open questions still deferred

| Question | Why deferred |
|---|---|
| Concurrent branches → `.claude/sessions/<branch>.md` | Wait for the single-file model to fail in practice |
| Cross-tool integration (Cursor, Aider) | Future opportunity; not blocking |

### Acknowledged gaps in canary config

Tracked in [closeout-canary-findings.md](closeout-canary-findings.md):

- **G1** — Soft-delete filter check not encoded (false-positive risk without per-table awareness)
- **G2** — `audit:naming` shell-check not wired in (waiting for static rules to misfire first)
- **G3** — `audit:full` not wired in (reserved for future `/closeout --deep`)
- **G4** — Testing-rule enforcement not encoded (workflow-specific, not file-presence rules)

### Phases not yet shipped (per §9)

- **Phase 2** — Rollout to 14 other projects (separate plan after canary stable)
- **Phase 3** — Deprecation shims for `/handoff`, `/sync-workstation`, `/endofday`, `/daily-end`, `/checkpoint`, `/project-hygiene` (30-day cutover after canary stable)
- **Phase 4** — VERSION pre-commit hook, ongoing maintenance

### Stability criterion

Per [closeout-canary-findings.md](closeout-canary-findings.md): **5+ real `/closeout` sessions on capital-manager with no blocker-level findings** → canary stable → green-light Phase 2.

### Skill version snapshot at canary launch

`closeout-skill@0.1.5` (~/.claude/VERSION) — dotfiles repo commit `7244a58`. Capital-manager config commit `d251136a`.
