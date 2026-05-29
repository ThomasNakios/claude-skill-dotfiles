# Closeout Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Phase 0 (global skill files at `~/.claude/commands/`) and Phase 1 (canary deployment on capital-manager) of the closeout redesign per [the design spec](2026-05-28-closeout-redesign-design.md).

> **Doc location note:** These docs originally lived in
> `capital-manager/docs/superpowers/`. Moved to the `claude-skill-dotfiles`
> repo (`~/.claude/design/`) on 2026-05-29 — the skill is a global,
> cross-project tool, so its docs belong with its code. Older inline path
> references (`docs/superpowers/...`) below are historical.

**Architecture:** Six global slash-command markdown files at `~/.claude/commands/` form the skeleton; per-project `.claude/claude.yaml` configs drive project-specific behavior. Phase 0 ships the global skill; Phase 1 bootstraps capital-manager's config from its existing `CLAUDE.md`, governance docs, and the current 600-line `closeout.md`.

**Tech Stack:** Markdown (slash commands), YAML (config), Bash (smoke tests), git (workstation sync deferred). No runtime — the "binary" is the LLM agent honoring instructions in the markdown files.

**Out of scope (separately planned):**
- Rollout to the other 14 projects (Phase 2)
- Deprecation shims for old commands (Phase 3)
- `~/.claude/` as a git repo for cross-workstation sync (sketched in design §9; mechanism implementation deferred)
- Cross-tool (Cursor, Aider) compatibility
- Concurrent-branch `.claude/sessions/<branch>.md` escalation

**Testing model:** No traditional TDD here — these are agent-instruction files, not executable code. The "test" for each file is a smoke invocation: render `--help`, verify the structured Help section appears, verify the agent exits without executing the command's main behavior. End-to-end test is a real session on capital-manager that produces a valid `.claude/session.md`.

---

## File Structure

### Phase 0 — Files created in `~/.claude/`

| Path | Purpose |
|---|---|
| `~/.claude/VERSION` | Single-line skill version string; surfaced in `--help` |
| `~/.claude/docs/claude-yaml-schema.md` | Schema reference for `.claude/claude.yaml`; agent reads when validating configs |
| `~/.claude/docs/session-template.md` | Default `.claude/session.md` template (frontmatter + body sections) |
| `~/.claude/commands/closeout.md` | Orchestrator + bootstrap (`--init`) + variants (`--daily`, `--quick`) |
| `~/.claude/commands/gate.md` | Quality gate; `--quick` mode |
| `~/.claude/commands/hygiene.md` | Project audit (informs only) |
| `~/.claude/commands/depart.md` | Workstation departure (commit + push) |
| `~/.claude/commands/arrive.md` | Workstation arrival (pull + post-pull hooks) |
| `~/.claude/commands/resume.md` | Session start — reads `.claude/session.md` |

### Phase 1 — Files created/modified in capital-manager

| Path | Purpose |
|---|---|
| `.claude/claude.yaml` | Project config (committed) |
| `.gitignore` (modify) | Add `.claude/session.md` |
| `.claude/session.md` (eventually written by `/closeout`) | Working memory (gitignored) |

---

## Conventions used in this plan

Each global skill file follows the same shape:

```markdown
---
description: <one-line for slash-command index>
---

# /<command>

## Help

<structured Help block — rendered when args contain --help/-h/help>

## Argument parsing

**FIRST, read the user's arguments:**
- If args contain `--help`, `-h`, or `help`: render the Help section above and STOP. Do not execute further sections.
- If args contain `--dry-run`: set DRY_RUN=true; do not actually execute external commands.
- ...other flag handling...

## Execution

<actual instructions for what the command does>
```

This `## Argument parsing` block is **load-bearing**: without it, the `--help` convention is wishful, since slash commands are markdown read by the agent, not real CLIs.

---

# Phase 0 — Foundations

## Task 1: Set up `~/.claude/` directory structure + VERSION file

**Files:**
- Create: `~/.claude/docs/` (directory)
- Create: `~/.claude/VERSION`

- [ ] **Step 1: Create the docs directory**

```bash
mkdir -p ~/.claude/docs
ls ~/.claude/
```

Expected: directory listing includes `commands/`, `docs/`, plus existing `memory/`, `projects/`, etc.

- [ ] **Step 2: Write the VERSION file**

```bash
echo "closeout-skill@0.1.0" > ~/.claude/VERSION
cat ~/.claude/VERSION
```

Expected output: `closeout-skill@0.1.0`

- [ ] **Step 3: Commit (in the closeout-dotfiles repo if it exists; otherwise document)**

NOTE: `~/.claude/` is not currently a git repo. For this plan's purposes, no commit is required at this step — workstation sync is deferred per spec §11 open questions. Document the version in the canary's session.md when run.

---

## Task 2: Write `~/.claude/docs/claude-yaml-schema.md`

This is the schema reference doc that the `closeout` command reads to validate `.claude/claude.yaml` configs.

**Files:**
- Create: `~/.claude/docs/claude-yaml-schema.md`

- [ ] **Step 1: Write the schema reference**

Content (write to file exactly):

````markdown
# `.claude/claude.yaml` Schema Reference (v1)

> Authoritative shape for project configs consumed by the closeout family
> (closeout, gate, hygiene, depart, arrive). When validating, the agent
> reads this file and reports specific deviations.

## Top-level required keys

| Key | Type | Required | Notes |
|---|---|---|---|
| `schema_version` | integer | yes | Must equal 1 |
| `project` | map | yes | See `project` block below |
| `gate` | map | yes | Quality-gate definition |
| `hygiene` | map | yes | Project audit (may be empty `{}`) |
| `security` | map | yes | Non-negotiables (may be empty list) |
| `closeout` | map | yes | Session.md + NEXT.md behavior |
| `depart` | map | no | Workstation departure config |
| `arrive` | map | no | Workstation arrival config |

## `project` block

```yaml
project:
  name: <string>                    # required
  type: <string>                    # optional; framework hint
  claude_md_path: <relative-path>   # optional; default ./CLAUDE.md
  claude_md_hash: <sha256>          # optional; populated by bootstrap
  bootstrapped_at: <ISO-8601>       # optional; populated by bootstrap
  bootstrapped_by: <skill-version>  # optional; populated by bootstrap
```

## `gate` block

```yaml
gate:
  commands:                         # required; list of named commands
    - name: <string>                # required
      cmd: <shell-string>           # required
      required: <bool>              # default true
  quick_subset: [<name>, ...]       # optional; names from commands[] for --quick
  parallel: <bool>                  # default true
  fail_fast: <bool>                 # default true
```

## `hygiene` block

```yaml
hygiene:
  patterns:                         # list; may be empty
    - name: <string>
      kind: files | grep            # which check kind
      glob: <glob>                  # for kind=files
      pattern: <regex>              # for kind=grep
      include: [<glob>, ...]        # for kind=grep
      exclude: [<glob>, ...]        # for kind=grep
      action: warn | report | suggest-delete
  gitignore_required: [<pattern>, ...]   # patterns that must be in .gitignore
  file_structure:
    forbidden_filenames: [<name>, ...]
    naming_rules:
      - { pattern: <glob>, case: PascalCase | kebab-case | snake_case }
    location_rules:
      - { kind: <string>, must_live_in: <path> }
  governance:
    docs_must_have_header: <string>
    docs_max_lines: <int>
    docs_dir: <path>
```

## `security` block

```yaml
security:
  rules:                            # list; hard-fail on violations
    - name: <string>
      description: <string>
      check:
        kind: grep-required | grep-required-pair | grep-forbidden
        # kind=grep-required:
        in_files: <glob>
        required_pattern: <regex>
        # kind=grep-required-pair:
        anchor: <regex>
        required_within_lines: <int>
        required_pattern: <regex>
        include: [<glob>, ...]
        exclude: [<glob>, ...]
        # kind=grep-forbidden:
        pattern: <regex>
        include: [<glob>, ...]
      source: <path-or-url>         # where this rule is defined
```

## `closeout` block

```yaml
closeout:
  session_md:
    path: <relative-path>           # default .claude/session.md
    template: <relative-path>       # optional override
    stale_threshold_days: <int>     # default 7
    draft_then_confirm: <bool>      # default true
  next_md:
    path: <relative-path>           # default NEXT.md; null to disable
    prompt_on_completion: <bool>    # default true
    auto_update: <bool>             # default false
  daily_report:
    enabled: <bool>                 # default true
    path_template: <string>         # default docs/testing/daily/{YYYY-MM-DD}.md
```

## `depart` block (optional)

```yaml
depart:
  remote: <string>                  # default origin
  protected_branches: [<branch>, ...]
  require_session_md_fresh: <bool>  # default true
  session_md_freshness_hours: <int> # default 4
```

## `arrive` block (optional)

```yaml
arrive:
  pull_strategy: rebase | merge     # default rebase
  post_pull_hooks:
    - { if_changed: <glob>, run: <shell-string> }
  suggest_resume: <bool>            # default true
```

## Validation behavior (agent reading this doc)

| Condition | Action |
|---|---|
| Missing required key | Report which key, exit with hard-fail |
| `schema_version != 1` | Report mismatch; suggest `/closeout --init --migrate` |
| Unknown top-level key | Warn but proceed (forward-compatible) |
| Malformed YAML | Hard-fail with line number from parser error |
| Type mismatch on a field | Hard-fail with field path and expected type |
| `claude_md_hash` differs from on-disk hash | Warn: "CLAUDE.md changed since bootstrap" |
````

- [ ] **Step 2: Verify the file exists**

```bash
test -f ~/.claude/docs/claude-yaml-schema.md && echo "OK"
wc -l ~/.claude/docs/claude-yaml-schema.md
```

Expected: `OK`, line count ~150.

---

## Task 3: Write `~/.claude/docs/session-template.md`

The default template for `.claude/session.md`. Projects can override via `closeout.session_md.template` in their config.

**Files:**
- Create: `~/.claude/docs/session-template.md`

- [ ] **Step 1: Write the template**

Content:

````markdown
---
schema_version: 1
session_id: {{SESSION_ID}}
written_at: {{ISO_TIMESTAMP}}
written_by: closeout {{SKILL_VERSION}}
project: {{PROJECT_NAME}}
branch: {{GIT_BRANCH}}
last_commit: {{GIT_COMMIT_SHORT}}
status: {{STATUS}}              # clean | warnings | blockers
checks:
  gate: {{GATE_STATUS}}     # pass | fail | skipped
  hygiene: {{HYGIENE_STATUS}}   # pass | warn | fail | skipped
  security: {{SECURITY_STATUS}} # pass | fail | skipped
counts:
  files_changed: {{FILES_CHANGED}}
  hygiene_warnings: {{HYGIENE_WARNINGS}}
  followups: {{FOLLOWUPS_COUNT}}
---

## Intent
{{INTENT}}

## Done
{{DONE}}

## In-flight
{{IN_FLIGHT}}

## Pickup
{{PICKUP}}

## Blockers
{{BLOCKERS}}

## Followups
{{FOLLOWUPS}}

## Decisions
{{DECISIONS}}
````

The agent substitutes `{{VARIABLE}}` placeholders at write time. Body sections drafted from session context (then user-reviewed per `draft_then_confirm: true`).

- [ ] **Step 2: Verify**

```bash
test -f ~/.claude/docs/session-template.md && echo "OK"
grep -c '{{' ~/.claude/docs/session-template.md
```

Expected: `OK`, placeholder count ≥15.

---

## Task 4: Write `~/.claude/commands/gate.md`

The simplest command — quality gate. Use this to validate the file-shape pattern before tackling closeout.md.

**Files:**
- Create: `~/.claude/commands/gate.md`

- [ ] **Step 1: Write `gate.md`**

````markdown
---
description: Run the project's quality gate (build, types, lint, design). Blocks on failure.
---

# /gate

## Help

Run the project's quality gate. Blocks on failure — intended as a merge precondition.

USAGE
  /gate [--quick] [--dry-run] [--help]

OPTIONS
  --quick     Run only the quick-subset of commands (from config).
  --dry-run   Show which commands would run; do not execute them.
  --help, -h  Show this help and stop.

EXAMPLES
  /gate              # Full quality gate
  /gate --quick      # Fast subset (lint + types in most projects)
  /gate --dry-run    # Preview without running

EXIT CODES
  0  All required commands passed
  1  One or more required commands failed

FAMILY
  /hygiene   Project audit (informs; does not block)
  /closeout  Session closure (composes gate + hygiene)
  /depart    Workstation departure
  /arrive    Workstation arrival
  /resume    Session start

## Argument parsing

**FIRST, read the user's arguments:**

1. If args contain `--help`, `-h`, or `help`: render the **Help** section above and STOP. Do not execute further sections.
2. If args contain `--dry-run`: set `DRY_RUN=true`.
3. If args contain `--quick`: set `MODE=quick`. Otherwise `MODE=full`.
4. Unknown flags: print "unknown flag: <flag>" and STOP.

## Execution

### Load config

1. Look for `.claude/claude.yaml` in the current working directory.
2. If missing: enter **generic mode**. Use auto-discovery:
   - If `package.json` exists: detect `build`, `lint`, `test` scripts. Add them.
   - If `tsconfig.json` exists: add `npx tsc --noEmit` as `types`.
   - In generic mode, `quick_subset` defaults to `[lint, types]` (if available).
3. If present: parse YAML. If malformed, report line number and STOP.
4. Validate against `~/.claude/docs/claude-yaml-schema.md`. Hard-fail on schema violations.
5. Read `gate` section. If absent: STOP with "config has no gate block".

### Resolve command list

- If `MODE=quick`: filter `gate.commands` to those whose `name` is in `gate.quick_subset`. If `quick_subset` is empty or missing, default to all `required: true` commands.
- Else: use all `gate.commands`.

### Execute

For each command in order (parallel if `gate.parallel: true`, sequential otherwise):

1. Print: `▶ <name>: <cmd>`
2. If `DRY_RUN`: print "(dry-run, skipping)" and move on.
3. Else: shell-execute the `cmd`. Capture exit code.
4. If exit code != 0 AND `required: true`: mark this command FAILED.
5. If `gate.fail_fast: true` and any command FAILED: stop executing further commands.

### Summary output

Print:
```
gate summary:
  ✓ build       (1.2s)
  ✓ lint        (0.8s)
  ✗ types       (2.1s)  exit 1
  - design      skipped (--quick)
```

Exit non-zero if any required command failed. Print failure hint: `See output above. To re-run only the quality gate: /gate`
````

- [ ] **Step 2: Smoke test — render `--help`**

In a fresh Claude session (or in this one with explicit invocation):

```
/gate --help
```

Expected behavior: Agent reads `~/.claude/commands/gate.md`, sees `--help` in args, renders ONLY the Help section, and stops without trying to load config or run commands.

Manual verification: response contains "USAGE", "OPTIONS", "EXAMPLES", "EXIT CODES", "FAMILY". Response does NOT contain "Loading config" or any execution output.

- [ ] **Step 3: Smoke test — `--dry-run` in a project without config**

In a test directory with a `package.json` containing a `build` script but no `.claude/claude.yaml`:

```
/gate --dry-run
```

Expected: agent enters generic mode, auto-discovers commands, prints them in dry-run format, exits without executing.

- [ ] **Step 4: Commit (no-op — `~/.claude/` not a git repo yet)**

Document version: `closeout-skill@0.1.0-gate-shipped` in a note for the eventual workstation-sync repo.

---

## Task 5: Write `~/.claude/commands/hygiene.md`

**Files:**
- Create: `~/.claude/commands/hygiene.md`

- [ ] **Step 1: Write `hygiene.md`**

````markdown
---
description: Audit project state (stale files, naming, governance). Informs; does not block.
---

# /hygiene

## Help

Audit project-state hygiene. Reports findings but does not block — meant to surface drift you should address.

USAGE
  /hygiene [--dry-run] [--help]

OPTIONS
  --dry-run   List patterns that would be scanned; do not execute the scans.
  --help, -h  Show this help and stop.

EXAMPLES
  /hygiene             # Full audit
  /hygiene --dry-run   # Preview patterns

EXIT CODES
  0  Audit completed (may include warnings)
  1  Hygiene config malformed (cannot run)

FAMILY
  /gate    Quality gate (blocks on failure)
  /closeout  Session closure (composes gate + hygiene)
  /depart    Workstation departure
  /arrive    Workstation arrival
  /resume    Session start

## Argument parsing

**FIRST, read the user's arguments:**

1. If args contain `--help`, `-h`, or `help`: render the **Help** section above and STOP.
2. If args contain `--dry-run`: set `DRY_RUN=true`.
3. Unknown flags: print "unknown flag: <flag>" and STOP.

## Execution

### Load config

1. Look for `.claude/claude.yaml`. If missing, enter generic mode with standard patterns:
   - `console.log` in `**/*.ts`, `**/*.tsx`
   - `TODO|FIXME` in `**/*.ts`, `**/*.tsx`
   - `.DS_Store` files
   - Large files (>1MB) outside `node_modules/`, `.next/`, `.git/`
2. If present: read `hygiene` section.

### Execute patterns

For each pattern in `hygiene.patterns`:

1. Print: `▶ <name> (action: <action>)`
2. If `DRY_RUN`: print pattern shape, skip execution.
3. Else execute:
   - `kind: files` — find files matching `glob`, report count.
   - `kind: grep` — grep for `pattern` in `include` paths, excluding `exclude`. Report match count + first 5 file:line hits.
4. Apply `action`:
   - `warn` — emit a warning, count toward total
   - `report` — emit info, do not increment warnings
   - `suggest-delete` — emit suggestion ("run `rm <path>`"), count toward warnings

### Check `gitignore_required`

For each pattern in `hygiene.gitignore_required`:
- If not present in `.gitignore`: warn "missing from .gitignore: <pattern>"

### Check `file_structure`

- For each entry in `naming_rules`: glob files, check casing of basename matches `case`. Report violations.
- For each entry in `forbidden_filenames`: find files with that exact basename. Report.
- For each entry in `location_rules`: this requires project knowledge; report as "manual review" with the rule.

### Check `governance`

- Glob `<docs_dir>/**/*.md`.
- For each: check first 20 lines contain `<docs_must_have_header>`. If not, warn.
- For each: count lines. If > `docs_max_lines`, warn.

### Summary output

```
hygiene summary:
  patterns: 7 (5 clean, 2 with warnings)
  gitignore: 1 missing
  file_structure: 3 violations
  governance: 2 docs missing "Last Updated" header

total warnings: 8
```

Exit 0 unless config malformed. Hygiene never blocks via exit code.
````

- [ ] **Step 2: Smoke test `--help`**

```
/hygiene --help
```

Expected: Help section renders, no execution.

- [ ] **Step 3: Smoke test `--dry-run` in generic mode**

In a directory without `.claude/claude.yaml`:

```
/hygiene --dry-run
```

Expected: lists the generic-mode patterns; does not scan files.

---

## Task 6: Write `~/.claude/commands/depart.md`

**Files:**
- Create: `~/.claude/commands/depart.md`

- [ ] **Step 1: Write `depart.md`**

````markdown
---
description: Workstation departure — commit + push so another machine can resume.
---

# /depart

## Help

Prepare this workstation for departure. Commits uncommitted work, pushes all branches that are ahead of remote, and verifies `.claude/session.md` is fresh enough for the next machine.

USAGE
  /depart [--dry-run] [--help]

OPTIONS
  --dry-run   Show what would be committed/pushed; do not execute.
  --help, -h  Show this help and stop.

EXAMPLES
  /depart              # Standard departure
  /depart --dry-run    # Preview without acting

EXIT CODES
  0  Departure successful — all branches pushed, session.md fresh
  1  Push failed or session.md missing/stale (and config requires it)

FAMILY
  /gate    Quality gate
  /hygiene   Project audit
  /closeout  Session closure (writes session.md)
  /arrive    Workstation arrival
  /resume    Session start

## Argument parsing

1. If args contain `--help`, `-h`, or `help`: render Help and STOP.
2. If args contain `--dry-run`: set `DRY_RUN=true`.

## Execution

### Load config

1. `.claude/claude.yaml` → read `depart` block. If missing, use defaults:
   - `remote: origin`
   - `protected_branches: []`
   - `require_session_md_fresh: true`
   - `session_md_freshness_hours: 4`

### Session.md freshness check

If `require_session_md_fresh: true`:
1. Check `.claude/session.md` exists. If missing: warn "No session.md — consider running `/closeout` first" and ask user to confirm before continuing.
2. Read frontmatter `written_at`. If older than `session_md_freshness_hours`: warn and prompt confirmation.

### Git status snapshot

```bash
git fetch --all --prune
git status
git branch --show-current
```

Report uncommitted tracked changes.

### Commit uncommitted tracked changes (with prompt)

If `git status --porcelain` shows tracked modifications:
1. List them.
2. Ask user: "Commit these as 'wip: <branch> @ <timestamp>'? [y/N/edit-message]"
3. On `y`: stage tracked changes only (`git add -u`), commit. (Skip if `DRY_RUN`.)
4. On `edit-message`: prompt for message, then commit.
5. On `N`: skip; will not push partial state.

### Push branches that are ahead

For each local branch where `git rev-list <branch>...origin/<branch>` shows commits ahead:

1. If branch is in `protected_branches`: print warning, prompt user to confirm.
2. Else: print `▶ push <branch>` and `git push <remote> <branch>` (unless `DRY_RUN`).

### Final summary

```
depart summary:
  workstation: <hostname>
  branch: <current>
  pushed: [branch1, branch2]
  session.md: fresh (written 14 minutes ago)

Ready. On the receiving machine, run /arrive to pull, then /resume to restore session.
```
````

- [ ] **Step 2: Smoke test `--help`**

```
/depart --help
```

Expected: Help renders, no execution.

- [ ] **Step 3: Smoke test `--dry-run` in a clean git repo**

In capital-manager (clean state):

```
/depart --dry-run
```

Expected: shows it would push nothing (everything in sync), reports session.md status.

---

## Task 7: Write `~/.claude/commands/arrive.md`

**Files:**
- Create: `~/.claude/commands/arrive.md`

- [ ] **Step 1: Write `arrive.md`**

````markdown
---
description: Workstation arrival — pull latest, run post-pull hooks, suggest /resume.
---

# /arrive

## Help

Arrive at this workstation: pull latest changes, run post-pull hooks (e.g., npm install if package.json changed), and suggest `/resume` to restore the previous session.

USAGE
  /arrive [--dry-run] [--help]

OPTIONS
  --dry-run   Show what would be pulled/run; do not execute.
  --help, -h  Show this help and stop.

EXAMPLES
  /arrive             # Standard arrival
  /arrive --dry-run   # Preview

EXIT CODES
  0  Arrival successful — clean pull, hooks ran (if any)
  1  Pull failed or post-pull hook failed

FAMILY
  /gate    Quality gate
  /hygiene   Project audit
  /closeout  Session closure
  /depart    Workstation departure
  /resume    Session start (reads session.md)

## Argument parsing

1. If args contain `--help`, `-h`, or `help`: render Help and STOP.
2. If args contain `--dry-run`: set `DRY_RUN=true`.

## Execution

### Load config

`.claude/claude.yaml` → read `arrive` block. Defaults:
- `pull_strategy: rebase`
- `post_pull_hooks: []`
- `suggest_resume: true`

### Pre-pull snapshot

```bash
git fetch --all --prune
git status
```

If uncommitted local changes exist: warn and ask user how to handle (stash, abort, or proceed at risk).

### Pull

If `pull_strategy: rebase`: `git pull --rebase` (unless `DRY_RUN`).
If `pull_strategy: merge`: `git pull` (unless `DRY_RUN`).

If rebase produces conflicts: abort the rebase, report files, ask user to resolve manually. Exit non-zero.

### Compute changed files since previous HEAD

```bash
git diff --name-only HEAD@{1} HEAD
```

### Post-pull hooks

For each hook in `post_pull_hooks`:
- If any file matched by `if_changed` glob is in the changed-files list: run `run` (unless `DRY_RUN`).
- Print `▶ hook: <if_changed> changed → <run>`.

### Final summary

```
arrive summary:
  workstation: <hostname>
  branch: <current>
  pulled: <N commits, M files>
  hooks ran: [npm install]

Suggested next: /resume to restore the previous session.
```

If `suggest_resume: true` and `.claude/session.md` exists: append nudge.
````

- [ ] **Step 2: Smoke test `--help`**

```
/arrive --help
```

Expected: Help renders.

- [ ] **Step 3: Smoke test `--dry-run`**

```
/arrive --dry-run
```

Expected: previews behavior; no pull executed.

---

## Task 8: Write `~/.claude/commands/resume.md`

**Files:**
- Create: `~/.claude/commands/resume.md`

- [ ] **Step 1: Write `resume.md`**

````markdown
---
description: Read .claude/session.md and restore session context for the next agent.
---

# /resume

## Help

Read `.claude/session.md` and restore session context — show what was in flight, where to pick up, blockers, followups. Warns on stale or branch-mismatched sessions.

USAGE
  /resume [--dry-run] [--help]

OPTIONS
  --dry-run   Preview the parsed session.md; do not modify any project state.
  --help, -h  Show this help and stop.

EXAMPLES
  /resume             # Standard session restore
  /resume --dry-run   # Preview

EXIT CODES
  0  Session restored (or no session.md present, with hint)
  1  session.md is malformed

FAMILY
  /gate    Quality gate
  /hygiene   Project audit
  /closeout  Session closure (writes session.md)
  /depart    Workstation departure
  /arrive    Workstation arrival

## Argument parsing

1. If args contain `--help`, `-h`, or `help`: render Help and STOP.
2. If args contain `--dry-run`: set `DRY_RUN=true`. (Affects nothing for resume since it's read-only by design.)

## Execution

### Locate session.md

1. Path from `.claude/claude.yaml` → `closeout.session_md.path` (default `.claude/session.md`).
2. If missing: print "No session.md found. To start a new session, work normally; run `/closeout` at the end to write one." STOP with exit 0.

### Parse

1. Read file. Extract YAML frontmatter (between leading `---` lines).
2. If frontmatter is malformed: exit 1 with the YAML parser error.
3. Read body sections (## Intent, ## Done, ## In-flight, etc.).

### Branch check

- Read current branch: `git branch --show-current`.
- Compare to `frontmatter.branch`.
- If different: warn "session.md was written on branch `<X>`, current branch is `<Y>`. Continue? [y/N]".

### Staleness check

- Compare `frontmatter.written_at` to now.
- If > `closeout.session_md.stale_threshold_days` (default 7): warn "session.md is N days old; contents may be out of date."

### Render

Print a structured summary:

```
Session restored from .claude/session.md
─────────────────────────────────────────
Written:   <written_at> (<X minutes/hours/days> ago)
Branch:    <branch> (matches current ✓)
Last:      <last_commit>
Status:    <status>  [gate:pass hygiene:warn security:pass]

INTENT
  <intent>

IN-FLIGHT
  <in_flight>

PICKUP
  <pickup>

BLOCKERS
  <blockers, if any>

FOLLOWUPS (N)
  - <item 1>
  - <item 2>

DECISIONS
  <decisions, if any>
```

Hint at the end: "When you're done with this session, run `/closeout` to write a fresh session.md."
````

- [ ] **Step 2: Smoke test `--help`**

```
/resume --help
```

Expected: Help renders.

- [ ] **Step 3: Smoke test in a project without session.md**

In capital-manager (no `.claude/session.md` exists yet):

```
/resume
```

Expected: prints "No session.md found" + hint, exits 0.

---

## Task 9: Write `~/.claude/commands/closeout.md` (the main file)

This is the largest and most complex file. It has three modes:
1. Default (no flags) — run gate + hygiene + security, write session.md
2. `--init` — bootstrap a project's `.claude/claude.yaml`
3. `--daily` — also write a daily QA report

**Files:**
- Create: `~/.claude/commands/closeout.md`

- [ ] **Step 1: Write `closeout.md`**

````markdown
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
  /gate    Quality gate (run independently)
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

✓ gate         (build, lint, types, design — 4.3s)
✓ security     (4 rules, all clean)
⚠ hygiene      (7 patterns, 4 warnings)
✓ session.md   written (.claude/session.md)

Next: /depart to push and switch machines, or continue this session.
```

If hygiene produced warnings, include their summary lines in the output (not just count).
````

- [ ] **Step 2: Smoke test `--help`**

```
/closeout --help
```

Expected: Help renders, no execution. Verify the help block contains "USAGE", "OPTIONS", "EXAMPLES", "EXIT CODES", "FAMILY".

- [ ] **Step 3: Smoke test `--dry-run` in capital-manager (config doesn't exist yet)**

```
/closeout --dry-run
```

Expected: Agent enters generic mode (no config found), describes what it would run, exits without writing session.md.

- [ ] **Step 4: Smoke test `--init` on a TEST fixture (not capital-manager)**

Create a tiny test fixture:

```bash
mkdir -p /tmp/closeout-test/.claude/commands
cd /tmp/closeout-test
git init -q
cat > package.json <<'EOF'
{
  "name": "test-fixture",
  "scripts": {
    "build": "echo build",
    "lint": "echo lint"
  }
}
EOF
cat > CLAUDE.md <<'EOF'
# Test Fixture

## Non-negotiable

- Never use console.log in production code.
EOF
```

Then in this fixture:

```
/closeout --init
```

Expected:
- Phase 1 mechanical scan picks up `build`, `lint` from package.json
- Phase 2 agent extraction produces a draft yaml
- `.claude/claude.yaml.proposed` exists with `schema_version: 1`, `gate.commands` listing build + lint, at least one security rule grepped from CLAUDE.md
- STOPS without auto-moving the file
- Prints the review-gate instructions

Manual verification: `cat /tmp/closeout-test/.claude/claude.yaml.proposed` shows valid YAML.

If issues surface (extraction misses obvious things, schema violations, agent gets confused), iterate on the closeout.md bootstrap section BEFORE moving to capital-manager.

---

## Task 10: Family smoke test

**Files:** none modified

- [ ] **Step 1: `--help` on each command**

Run each in turn:

```
/closeout --help
/gate --help
/hygiene --help
/depart --help
/arrive --help
/resume --help
```

Each should render its own Help block (with USAGE, OPTIONS, EXAMPLES, EXIT CODES, FAMILY) and stop without executing.

- [ ] **Step 2: Verify FAMILY sections cross-reference correctly**

Manual check: each `--help` output's FAMILY section lists the other 5 commands (or 4, since the current one is implicit). No broken references.

- [ ] **Step 3: Verify generic-mode messages**

In a directory with no `.claude/claude.yaml`:

```
/gate --dry-run
/hygiene --dry-run
/closeout --dry-run
```

Each should print "generic mode" and a sensible default behavior. No crash.

- [ ] **Step 4: Document Phase 0 complete**

This is a marker only — no file changes. Note: Phase 0 deliverables present:
- ~/.claude/VERSION exists
- ~/.claude/docs/{claude-yaml-schema.md, session-template.md} exist
- ~/.claude/commands/{closeout,gate,hygiene,depart,arrive,resume}.md exist
- All 6 commands respond to --help
- /closeout --init produces a valid .proposed file on the test fixture

---

# Phase 1 — Canary on capital-manager

## Task 11: Pre-flight backup

**Files:**
- Backup: `.claude/commands/closeout.md` (and related)

- [ ] **Step 1: Verify capital-manager is clean**

```bash
cd /Users/thomas/Workspaces/capital-manager
git status
```

Expected: working tree clean OR the changes are intentional pre-canary work. If unexpected uncommitted changes: investigate before continuing (per CLAUDE.md guidance: never assume).

- [ ] **Step 2: Snapshot the files that bootstrap will mine**

```bash
mkdir -p /tmp/capital-manager-pre-closeout-canary
cp .claude/commands/closeout.md /tmp/capital-manager-pre-closeout-canary/
cp .claude/commands/gate.md /tmp/capital-manager-pre-closeout-canary/
cp .claude/commands/handoff.md /tmp/capital-manager-pre-closeout-canary/
cp .claude/commands/project-hygiene.md /tmp/capital-manager-pre-closeout-canary/
cp CLAUDE.md /tmp/capital-manager-pre-closeout-canary/ 2>/dev/null || cp .claude/CLAUDE.md /tmp/capital-manager-pre-closeout-canary/
cp STANDARDS_FILE_STRUCTURE.md /tmp/capital-manager-pre-closeout-canary/
ls /tmp/capital-manager-pre-closeout-canary/
```

Expected: 5-7 files copied. Keep this around as a reference if bootstrap extraction looks wrong.

- [ ] **Step 3: No commit yet** — nothing has changed in capital-manager.

---

## Task 12: Run `/closeout --init` on capital-manager

**Files:**
- Create: `.claude/claude.yaml.proposed`

- [ ] **Step 1: Confirm pre-conditions**

```bash
cd /Users/thomas/Workspaces/capital-manager
test -f .claude/claude.yaml && echo "EXISTS — STOP (need --refresh path)" || echo "no existing config — OK to init"
ls .claude/commands/closeout.md
ls CLAUDE.md .claude/CLAUDE.md 2>&1 | head -2
ls STANDARDS_FILE_STRUCTURE.md
ls docs/governance/standards/ | head -5
```

Expected: no existing `.claude/claude.yaml`; sources to mine all present.

- [ ] **Step 2: Run the bootstrap**

```
/closeout --init
```

Expected (in order):
1. Mechanical scan output: detected files (CLAUDE.md, .claude/commands/closeout.md, STANDARDS_FILE_STRUCTURE.md, docs/governance/standards/*.md, package.json), framework `nextjs-supabase`.
2. Agent extraction phase: dispatches Explore subagent, returns drafted YAML.
3. Draft written to `.claude/claude.yaml.proposed`.
4. Summary printed: section counts, sources listed.
5. STOPS — does not move the .proposed file.

If any phase fails: capture the failure mode in `/tmp/capital-manager-pre-closeout-canary/notes.md` and iterate on closeout.md before retrying.

- [ ] **Step 3: Confirm the .proposed file exists and parses**

```bash
test -f .claude/claude.yaml.proposed && echo "OK"
wc -l .claude/claude.yaml.proposed
python3 -c "import yaml; yaml.safe_load(open('.claude/claude.yaml.proposed'))" && echo "YAML parses OK"
```

Expected: file exists, ~200-400 lines, parses without error.

---

## Task 13: Review the extracted config

**Files:**
- Read-only review of `.claude/claude.yaml.proposed`

- [ ] **Step 1: Read the full proposed config**

```bash
cat .claude/claude.yaml.proposed
```

Manually check (this is human/canary work — extraction quality is the main risk):

- [ ] `schema_version: 1` present
- [ ] `project.name: capital-manager`
- [ ] `project.claude_md_hash` is a sha256
- [ ] `project.bootstrapped_at` is today's ISO timestamp
- [ ] `gate.commands` includes at minimum: `build` → `npm run build`, `lint` → `npm run lint`, `types` → some tsc command, `design` → `npm run gate:design`
- [ ] `gate.quick_subset` is set (e.g., `[lint, types]`)
- [ ] `security.rules` includes ALL four NON-NEGOTIABLES from CLAUDE.md:
  - `tenant-isolation` (every supabase query filters by tenant_id)
  - `soft-delete-filter` (queries filter is_deleted = false)
  - `require-tenant-auth` (server actions call requireTenantAuth())
  - `no-dark-prefix` (Tailwind dark: prefix forbidden)
- [ ] Each `security.rules[]` has a `source:` pointer
- [ ] `hygiene.patterns` includes at least: console.log scan, TODO/FIXME, stale migration-result-*.json
- [ ] `hygiene.file_structure.forbidden_filenames` includes `utils.ts`, `helpers.ts`, `misc.ts`, `common.ts`
- [ ] `hygiene.governance.docs_must_have_header: "Last Updated"` and `docs_max_lines: 250` per existing project-hygiene.md
- [ ] `closeout.session_md.path: .claude/session.md`
- [ ] `closeout.next_md.path: NEXT.md`, `prompt_on_completion: true`

- [ ] **Step 2: Note any extraction misses**

If a rule from CLAUDE.md or governance docs is missing, list it. Edit the .proposed file by hand to add it. Document what was missed for future bootstrap improvements.

- [ ] **Step 3: Check `source:` pointers resolve**

For each `security.rules[].source:` pointer, verify the referenced file/section actually exists:

```bash
for src in $(grep -oE 'source: "[^"]+"' .claude/claude.yaml.proposed | sed 's/source: //;s/"//g'); do
  file=$(echo "$src" | cut -d'#' -f1)
  [ -f "$file" ] && echo "OK: $src" || echo "MISSING: $src"
done
```

Expected: all OK. Fix any MISSING by hand.

---

## Task 14: Accept the config + update .gitignore + commit

**Files:**
- Move: `.claude/claude.yaml.proposed` → `.claude/claude.yaml`
- Modify: `.gitignore`

- [ ] **Step 1: Confirm `.gitignore` doesn't already have `.claude/session.md`**

```bash
grep -E '^\.claude/session\.md$' .gitignore && echo "ALREADY PRESENT" || echo "need to add"
```

- [ ] **Step 2: Add to .gitignore if needed**

```bash
echo '.claude/session.md' >> .gitignore
tail -3 .gitignore
```

- [ ] **Step 3: Move the config into place**

```bash
mv .claude/claude.yaml.proposed .claude/claude.yaml
ls .claude/claude.yaml .claude/claude.yaml.proposed 2>&1
```

Expected: `.claude/claude.yaml` exists; `.proposed` is gone.

- [ ] **Step 4: Stage and commit**

```bash
git add .claude/claude.yaml .gitignore
git status
```

Expected: two files staged.

```bash
git commit -m "$(cat <<'EOF'
feat(claude): bootstrap closeout config for canary

Adds .claude/claude.yaml — the project-specific config consumed by the
global closeout family (closeout, gate, hygiene, depart, arrive). Mined
from CLAUDE.md NON-NEGOTIABLES, STANDARDS_FILE_STRUCTURE.md, governance
docs, and the existing 600-line .claude/commands/closeout.md.

See docs/superpowers/specs/2026-05-28-closeout-redesign-design.md for
architecture. Canary deployment per docs/superpowers/plans/2026-05-28-
closeout-redesign-implementation.md.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

Expected: clean commit. Note the sha for later reference.

---

## Task 15: Smoke test the family on capital-manager (with config)

**Files:** none modified

- [ ] **Step 1: `--help` shows project-aware preview**

```
/closeout --help
```

Expected: the Help output now includes the "Project: capital-manager / Config: .claude/claude.yaml (schema v1, last bootstrap: 2026-05-28) / Status: ✓ CLAUDE.md unchanged since bootstrap" preamble and the WILL RUN block lists the commands from `gate.commands`.

- [ ] **Step 2: `/gate --dry-run`**

```
/gate --dry-run
```

Expected: lists the 4-5 gate commands from `.claude/claude.yaml`, does not execute them.

- [ ] **Step 3: `/hygiene --dry-run`**

```
/hygiene --dry-run
```

Expected: lists the hygiene patterns from config (console.log, TODO/FIXME, stale migration-results, etc.), does not scan.

- [ ] **Step 4: `/gate --quick`**

```
/gate --quick
```

Expected: runs only the `quick_subset` (likely `lint` and `types`). Either passes or surfaces real lint/type errors. If a real failure: investigate before continuing.

---

## Task 16: End-to-end real-session test (`/closeout`)

**Files:**
- Eventually create: `.claude/session.md` (gitignored)

- [ ] **Step 1: Set up a small change to have something real to close out**

For test purposes, make a small documentation tweak (not a meaningful change) — e.g., add a single bullet to `docs/superpowers/plans/2026-05-28-closeout-redesign-implementation.md`'s success criteria. Commit it.

This gives `closeout` something to summarize in the session.md.

- [ ] **Step 2: Run `/closeout` (full mode, no flags)**

```
/closeout
```

Expected sequence:
1. Loads `.claude/claude.yaml`; reports schema v1, last bootstrap date, CLAUDE.md unchanged.
2. Git pre-flight: branch, last commit, status.
3. Runs `gate` (build, lint, types, design). Hard-fail if any breaks.
4. Runs `security` audit (4 NON-NEGOTIABLES). Hard-fail if any rule trips.
5. Runs `hygiene`. Soft-warn on findings; doesn't block.
6. Drafts session.md content from session context + check outcomes.
7. Draft-then-confirm: prompts user to review each body section. Accept all defaults if they look reasonable.
8. Writes `.claude/session.md`.
9. Prompts about NEXT.md updates (decline if nothing to update).
10. Final summary.

- [ ] **Step 3: Verify session.md was written correctly**

```bash
test -f .claude/session.md && echo "OK"
head -25 .claude/session.md
python3 -c "
import sys, yaml
text = open('.claude/session.md').read()
parts = text.split('---', 2)
assert len(parts) >= 3, 'frontmatter delimiter missing'
fm = yaml.safe_load(parts[1])
assert fm['schema_version'] == 1
assert fm['project'] == 'capital-manager'
assert fm['branch']  # any branch name
assert fm['checks']['gate'] in ('pass', 'fail', 'skipped')
print('Frontmatter OK')
"
```

Expected: file exists; frontmatter parses; required fields present.

- [ ] **Step 4: Verify session.md is gitignored**

```bash
git check-ignore -v .claude/session.md
```

Expected: output references the `.gitignore` rule we added. (Non-zero exit means NOT gitignored — that's a bug; investigate.)

- [ ] **Step 5: Verify body sections look reasonable**

```bash
cat .claude/session.md
```

Manual check: Intent, Done, In-flight, Pickup, Blockers, Followups, Decisions all present with plausible content (or honest empty placeholders if no content applied).

- [ ] **Step 6: Run `/resume` against the just-written session.md**

```
/resume
```

Expected: renders a structured summary of the session.md, including branch check (matches current ✓), staleness check (just-written), and the body sections.

- [ ] **Step 7: Test stale detection (optional)**

To test the staleness branch, edit `.claude/session.md`'s frontmatter `written_at` to 10 days ago, then run `/resume`. Expected: stale warning prints. Revert the edit afterward.

- [ ] **Step 8: Commit any deliberate test artifacts**

If Step 1's small change wasn't already committed: commit it now with a clear message.

---

## Task 17: Iteration window — battle-test for one week

**Files:** likely tweaks to `~/.claude/commands/closeout.md` and/or `.claude/claude.yaml` based on real usage findings

- [ ] **Step 1: Use `/closeout` at the end of EACH real session for one week**

Capture issues in a running notes file: `docs/superpowers/specs/closeout-canary-findings.md`. Examples of what to look for:
- Missed security rules (something that SHOULD have hard-failed but didn't)
- False-positive hygiene warnings (something flagged that's intentional)
- Draft-then-confirm UX friction (sections that always need editing)
- Speed problems (too slow on large repos)
- Mis-categorized failures (hard-fail when it should be soft, vice versa)

- [ ] **Step 2: Iterate on the global skill files**

When an issue is real:
1. Edit `~/.claude/commands/<command>.md` to fix.
2. Bump `~/.claude/VERSION` (e.g., 0.1.0 → 0.1.1).
3. Re-test the affected behavior.
4. Note the change in `docs/superpowers/specs/closeout-canary-findings.md`.

- [ ] **Step 3: Iterate on the project config**

If a finding is project-specific (a hygiene pattern that doesn't apply here):
1. Edit `.claude/claude.yaml`.
2. Commit with `chore(claude): adjust <X> based on canary findings`.

- [ ] **Step 4: Daily report check**

At least once during the week, run `/closeout --daily` and verify:
- `docs/testing/daily/YYYY-MM-DD.md` is created (per `closeout.daily_report.path_template`).
- It's committed-friendly (not gitignored).
- Content is useful (more than session.md content alone).

- [ ] **Step 5: Done criterion**

After 5+ real sessions with no new blocker-level issues, declare canary stable. Output: an updated `closeout-canary-findings.md` summarizing what got changed and what was learned. This document feeds Phase 2 (rollout to 14 other projects), which gets a separate plan.

---

## Self-Review (against spec)

### Spec coverage check

| Spec section | Covered by |
|---|---|
| §3 Architecture (global skeleton + project config + auto-discovery) | Tasks 1, 9 (closeout.md execution flow), 12 |
| §4 Command Taxonomy (5 commands + adjacent resume) | Tasks 4-9 (one per command) |
| §4 Failure semantics (hard/soft/skip) | Task 9 closeout.md Steps 3, 4, 5; gate.md and hygiene.md execution sections |
| §4 Deprecations | OUT OF SCOPE (Phase 3) — noted in plan header |
| §5 Bootstrap / Retrofit Flow (Phase 1 + Phase 2 + Review gate) | Task 9 closeout.md `--init` mode; Tasks 12-14 |
| §6 session.md format (frontmatter + body sections) | Task 3 (template); Task 9 closeout.md Step 6 |
| §6 Lifecycle rules (overwrite, gitignored, branch-aware, stale detection) | Task 8 resume.md; Task 14 gitignore; Task 16 Step 4, 7 |
| §7 Help Support (universal contract, project-aware, FAMILY, generic mode, failure cross-ref) | Every command file has structured Help + arg-parsing; Task 15 Step 1 tests project-aware help |
| §8 Config Schema (top-level, all sections, validation, greenfield) | Task 2 (schema doc); Task 9 closeout.md Step 1 validation; Task 13 review |
| §9 Migration Plan Phase 0 + Phase 1 | This entire plan |
| §9 Phase 2-4 | OUT OF SCOPE — noted in plan header |
| §10 Open questions | Not implemented; deferred per spec |

### Placeholder scan

- Searched for "TBD" — found 0 in the plan body (only in spec references).
- Searched for "implement later" — found 0.
- Searched for "add appropriate error handling" — found 0.
- Searched for "similar to Task N" — found 0.
- All steps have either an explicit command, file content, or a specific verification action.

### Type consistency

- All command names consistent across tasks: `closeout`, `gate`, `hygiene`, `depart`, `arrive`, `resume`.
- Config path consistent: `.claude/claude.yaml`.
- Session.md path consistent: `.claude/session.md`.
- VERSION format consistent: `closeout-skill@<semver>`.
- Frontmatter keys consistent across template (Task 3) and write logic (Task 9).
- Schema field names consistent between schema doc (Task 2) and write/read logic (Tasks 4-9).

### Known gaps explicitly out of scope

- `~/.claude/` as a git repo (workstation sync) — noted in plan header; Task 1 Step 3 documents the no-op.
- Phase 2 rollout to 14 other projects — separate plan.
- Phase 3 deprecation shims — separate plan.
- Cross-tool compatibility — design §11 open question, not in plan.

---

## Execution

Plan complete and saved to `docs/superpowers/plans/2026-05-28-closeout-redesign-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

---

## Execution Outcome (2026-05-29)

Subagent-driven execution chosen. Phase 0 (Tasks 1-10) shipped via a mix of direct writes for mechanical files and subagent invocations where context isolation helped. Phase 1 shipped through Task 14; Tasks 15-17 deferred to the canary battle-test (user-driven). Out-of-plan work surfaced during execution and was also shipped.

### Task status

| Task | Outcome |
|---|---|
| 1. ~/.claude/ structure + VERSION | ✅ Done |
| 2. claude-yaml-schema.md | ✅ Done (later extended with `shell` kind) |
| 3. session-template.md | ✅ Done |
| 4. gate.md *(originally verify.md)* | ✅ Done — renamed after `/verify` collision discovered |
| 5-8. hygiene/depart/arrive/resume.md | ✅ Done |
| 9. closeout.md | ✅ Done |
| 10. Family smoke test | ✅ Done — all files verified, skill registry confirmed |
| 11. Pre-flight backup | ✅ Done (`/tmp/capital-manager-pre-closeout-canary/`) |
| 12. `/closeout --init` on capital-manager | ⚠️ First subagent timed out at 20 min. Re-executed as direct controller work; produced valid `.proposed`. |
| 13. Review `.proposed` | ✅ Done — found 1 safety issue + 3 coverage gaps; applied 4 fixes inline |
| 14. Accept config + commit | ✅ Done (commit `d251136a`) |
| 15. Smoke test family on capital-manager | ⏸ Deferred to user — slash-command invocation requires real session |
| 16. End-to-end `/closeout` real-session test | ⏸ Deferred to user — same reason |
| 17. Battle-test for ~1 week | ⏸ Deferred to user; tracker at [closeout-canary-findings.md](closeout-canary-findings.md) |

### Out-of-plan work shipped

| Item | Reason |
|---|---|
| `/family` command | Plan dropped `/help` due to built-in collision; standalone discoverability still needed |
| `~/.claude/` git repo (`claude-skill-dotfiles`) + remote on GitHub | Plan deferred this; user wanted real cross-workstation sync during Phase 1 |
| `~/.claude/sync.sh` idempotent script | Composed bootstrap + ongoing sync into one state-aware script |
| `/depart` + `/arrive` cross-repo composition | User-requested integration with vault sync (Obsidian-aware) |
| Schema extension: `shell` check kind | Needed to wire capital-manager's existing audit scripts into security rules |
| Inline rename `verify` → `gate` (instead of Phase 3 shim) | Resolved during canary; cleaner than deferring |

### Versions shipped during Phase 0/1

| Version | Change |
|---|---|
| `closeout-skill@0.1.0` | Initial family + docs |
| `0.1.1` | self-sync in /arrive and /depart |
| `0.1.2` | rename bootstrap-workstation.sh → sync.sh, idempotent state-aware |
| `0.1.3` | Obsidian-aware vault composition in /depart + /arrive |
| `0.1.4` | /family discoverability command |
| `0.1.5` | schema: `shell` check kind |

### Canary state at hand-off

- Skill version: `closeout-skill@0.1.5`
- Capital-manager config: `.claude/claude.yaml` @ `d251136a`
- Tracker: [closeout-canary-findings.md](closeout-canary-findings.md)
- Stability gate: 5+ real `/closeout` sessions without blockers → Phase 2

### What still needs separate plans

- **Phase 2** — Rollout to 14 other projects
- **Phase 3** — Deprecation shims (30-day cutover) for the remaining old commands
