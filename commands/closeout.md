---
description: Session closure — composes gate + hygiene + security, writes .claude/session.md.
---

# /closeout

## Help

Wrap up the current work session: run quality + hygiene + security checks, write `.claude/session.md` for the next session.

USAGE
  /closeout [--init] [--daily] [--quick] [--config <path>] [--dry-run] [--help]

OPTIONS
  --init             Bootstrap closeout config for this project (one-time setup).
                     With `--refresh`: re-bootstrap, preserving user edits where possible.
  --daily            Also generate the daily QA report.
  --quick            Skip gate; run hygiene + write session.md only.
  --config <path>    Use a custom config file (default: .claude/claude.yaml).
  --dry-run          Show what would happen without executing.
  --help, -h         Show this help and stop.

EXAMPLES
  /closeout                    # Standard end-of-session
  /closeout --daily            # Daily wrap-up with QA report
  /closeout --init             # One-time bootstrap
  /closeout --init --refresh   # Re-bootstrap after CLAUDE.md change
  /closeout --config alt.yaml  # Use alternate config

EXIT CODES
  0  All checks passed; session.md written
  1  gate failed (hard-fail)
  2  security audit failed (hard-fail)
  3  user aborted at confirmation gate

FAMILY
  /gate      Quality gate (run independently)
  /hygiene   Project audit (run independently)
  /depart    Workstation departure (git push + freshness check)
  /arrive    Workstation arrival
  /resume    Session start — reads .claude/session.md

## Argument parsing

**FIRST, read the user's arguments:**

1. If args contain `--help`, `-h`, or `help`: render the **Help** section above and STOP.
2. Parse flags:
   - `--init` → MODE=init
   - `--refresh` (only with --init) → REFRESH=true
   - `--daily` → DAILY=true
   - `--quick` → MODE=quick
   - `--config <path>` → CONFIG_PATH=<path>
   - `--dry-run` → DRY_RUN=true
3. Default `MODE=full` if no mode flag set.
4. Unknown flags: print "unknown flag: <flag>" and STOP.

## Execution

### Mode dispatch

- If `MODE=init`: go to **Bootstrap mode** below.
- Else: go to **Normal mode** below.

---

## Bootstrap mode (`--init`)

### Phase 1 — Mechanical scan

1. Read `package.json` if present. Extract scripts: `build`, `lint`, `test`, `test:e2e`, `verify:design`, `type-check`, `tsc`.
2. Detect framework:
   - `package.json` with `next` dep → `nextjs`
   - `supabase/` directory → append `-supabase`
   - `pyproject.toml` → `python`
   - `Cargo.toml` → `rust`
3. Find candidates for extraction:
   - `CLAUDE.md` (and `.claude/CLAUDE.md`) → for `security.rules`, `hygiene.file_structure`
   - `STANDARDS_*.md` at repo root → for `hygiene.file_structure`
   - `docs/governance/**/*.md` → for governance rules
   - `.claude/commands/{closeout,verify,handoff,project-hygiene}.md` (existing project-local) → for gate commands, hygiene patterns
4. Compute SHA256 of `CLAUDE.md` → store as `project.claude_md_hash`.

### Phase 2 — Agent extraction

Dispatch an `Explore` subagent with this prompt:

> Read the following files and extract a `.claude/claude.yaml` config per the schema at `~/.claude/docs/claude-yaml-schema.md`.
>
> Files to mine:
> - `<list-of-discovered-files>`
>
> Produce sections:
> - `security.rules` — each rule has a `source:` pointer to the doc that defines it. Include NON-NEGOTIABLES from CLAUDE.md as `grep-required` or `grep-forbidden` checks where feasible. For rules that can't be encoded as greps (architectural patterns), include them with `kind: manual-review`.
> - `hygiene.patterns` — stale-file globs, console.log/TODO scans, gitignore requirements
> - `hygiene.file_structure` — naming rules, forbidden filenames, location rules
> - `hygiene.governance` — doc headers, max lines, dir
> - `gate.commands` — from `package.json` scripts + mentions in existing `closeout.md`
> - `closeout.session_md`, `closeout.next_md`, `closeout.daily_report`
>
> Output: valid YAML matching schema_version 1.

### Phase 3 — Review gate

1. Write the agent's output to `.claude/claude.yaml.proposed`.
2. Print a diff-style summary:
   ```
   Extracted from:
     - CLAUDE.md (8.4 KB, hash 9e633b1e...)
     - .claude/commands/closeout.md (24 KB)
     - STANDARDS_FILE_STRUCTURE.md (12 KB)
     - docs/governance/standards/naming-conventions.md (3.2 KB)
     - docs/governance/standards/auth-patterns.md (5.1 KB)
     - package.json (scripts: build, lint, test, type-check, verify:design)

   Config drafted to: .claude/claude.yaml.proposed

   Section counts:
     security.rules:        4 (tenant-isolation, no-dark-prefix, require-tenant-auth, soft-delete-filter)
     hygiene.patterns:      7
     hygiene.file_structure: 4 naming + 4 forbidden + 3 locations
     hygiene.governance:    1 (Last Updated header, 250-line cap)
     gate.commands:       5 (build, lint, types, design, test)
   ```
3. Tell the user:
   > Review the proposed config:
   > ```
   > cat .claude/claude.yaml.proposed
   > diff .claude/claude.yaml.proposed .claude/claude.yaml  # if existing
   > ```
   >
   > When ready, accept:
   > ```
   > mv .claude/claude.yaml.proposed .claude/claude.yaml
   > echo '.claude/session.md' >> .gitignore  # if not already
   > git add .claude/claude.yaml .gitignore
   > git commit -m "feat(claude): bootstrap closeout config"
   > ```
4. STOP. Do not auto-move.

### `--init --refresh` semantics

If `REFRESH=true` and `.claude/claude.yaml` already exists:
1. Read existing config. Stash user-edited regions (anything not in the original extraction's known patterns).
2. Re-run Phase 1 + Phase 2.
3. Phase 3 writes a 3-way diff: original-extraction | current-on-disk | new-extraction.
4. User merges manually.

---

## Normal mode (default, `--daily`, `--quick`)

### Step 1 — Load config

1. Path from `CONFIG_PATH` if set, else `.claude/claude.yaml`.
2. If missing: enter **generic mode** (gate auto-discovery, hygiene standard patterns, no security rules, session.md at `.claude/session.md`). Print: "No config — running in generic mode. Run /closeout --init for project-aware checks."
3. Else: parse YAML. Validate against `~/.claude/docs/claude-yaml-schema.md`.
4. Check `project.claude_md_hash` against current SHA256 of `project.claude_md_path` (default `CLAUDE.md`). If different: warn "CLAUDE.md changed since bootstrap — consider `/closeout --init --refresh`".

### Step 2 — Git pre-flight

```bash
git status
git branch --show-current
git rev-parse --short HEAD
```

Stash these for the session.md frontmatter.

### Step 3 — Run gate (skip if `--quick`)

Invoke gate logic: same as `~/.claude/commands/gate.md` (or shell out to `/gate` if invocation is supported).

If gate FAILS: HARD-FAIL.
1. Print "gate failed — closeout aborted. Fix above issues and re-run."
2. Do NOT write session.md.
3. Exit code 1.

### Step 4 — Run security audit

For each rule in `security.rules`:
1. Execute the `check` per its `kind`:
   - `grep-required`: for each file matching `in_files`, ensure `required_pattern` appears at least once. If not, FAIL.
   - `grep-required-pair`: find each match of `anchor`. Within `required_within_lines` lines after, look for `required_pattern`. If missing, FAIL.
   - `grep-forbidden`: find any match of `pattern` in `include`. If found, FAIL.
2. On FAIL: collect the file:line and source-doc pointer.

If any security rule FAILED: HARD-FAIL.
1. Print findings with `source:` pointer for each.
2. Do NOT write session.md.
3. Exit code 2.

### Step 5 — Run hygiene (soft-fail)

Invoke hygiene logic (same as `~/.claude/commands/hygiene.md`).

Hygiene findings are warnings — they do NOT block. Collect:
- Total warning count.
- File:line of top findings.

### Step 6 — Draft session.md

Read `~/.claude/docs/session-template.md` (or the project override at `closeout.session_md.template`).

Substitute placeholders:

| Placeholder | Source |
|---|---|
| `{{SESSION_ID}}` | Current UTC timestamp `YYYY-MM-DD-HHMM` |
| `{{ISO_TIMESTAMP}}` | Current ISO-8601 with timezone |
| `{{SKILL_VERSION}}` | Contents of `~/.claude/VERSION` |
| `{{PROJECT_NAME}}` | `project.name` from config (or repo dir name) |
| `{{GIT_BRANCH}}` | `git branch --show-current` |
| `{{GIT_COMMIT_SHORT}}` | `git rev-parse --short HEAD` |
| `{{STATUS}}` | `clean` if all pass; `warnings` if hygiene warns; `blockers` if any hard-fail (won't reach here on blockers) |
| `{{GATE_STATUS}}`, `{{HYGIENE_STATUS}}`, `{{SECURITY_STATUS}}` | per-check outcome |
| `{{FILES_CHANGED}}` | `git diff --name-only HEAD HEAD~1 | wc -l` (or session-diff if tracked) |
| `{{HYGIENE_WARNINGS}}` | warning count from hygiene |
| `{{FOLLOWUPS_COUNT}}` | length of Followups section after drafting |

For body sections, **DRAFT from session context**:
- `{{INTENT}}` — one-sentence summary of what this conversation/session was about
- `{{DONE}}` — bulleted list of work completed, with commit shas where relevant
- `{{IN_FLIGHT}}` — bulleted list of WIP items with file:line where known
- `{{PICKUP}}` — concrete next-session guidance
- `{{BLOCKERS}}` — anything preventing progress
- `{{FOLLOWUPS}}` — TODOs surfaced but not addressed
- `{{DECISIONS}}` — choices the user made that future-you should know about

### Step 7 — Draft-then-confirm (default true)

If `closeout.session_md.draft_then_confirm: true`:

1. Print drafted content section-by-section.
2. Ask user per section: "Accept? [y/n/edit]"
3. On `edit`: prompt for replacement text, substitute.
4. On `n`: leave section empty or with TODO.
5. After all sections confirmed: write to `closeout.session_md.path`.

If `false`: write directly.

### Step 8 — `--daily` extension

If `DAILY=true` and `closeout.daily_report.enabled`:

1. Compute today's date: `YYYY-MM-DD`.
2. Resolve `closeout.daily_report.path_template` → e.g., `docs/testing/daily/2026-05-28.md`.
3. Write a daily report containing:
   - Frontmatter from session.md (status, checks, counts)
   - The body sections from session.md (Intent, Done, etc.)
   - Additional: enumerate today's commits (`git log --since=midnight --pretty=format:"%h %s"`)
4. This file IS committed (not gitignored) — it's the QA handover trail.

### Step 9 — NEXT.md prompt

If `closeout.next_md.path` is set and `closeout.next_md.prompt_on_completion: true`:

1. Ask user: "Any items in `<path>` to mark as done, or new items to add?"
2. If yes: prompt for edits, open editor or apply user's text.
3. NEVER auto-write to NEXT.md (`auto_update: false` enforced).

### Step 10 — Final summary

```
closeout summary  •  closeout-skill@0.1.0
─────────────────────────────────────────
project:     capital-manager
branch:      production
last_commit: 11ec164a
config:      .claude/claude.yaml (schema v1)

✓ gate       (build, lint, types, design — 4.3s)
✓ security     (4 rules, all clean)
⚠ hygiene      (7 patterns, 4 warnings)
✓ session.md   written (.claude/session.md)

Next: /depart to push and switch machines, or continue this session.
```

If hygiene produced warnings, include their summary lines in the output (not just count).
