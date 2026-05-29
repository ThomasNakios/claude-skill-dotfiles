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
  /gate      Quality gate
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
2. If missing: this is the normal case after arriving on a DIFFERENT machine
   (session.md is gitignored, same-machine-only — it didn't travel). Fall back
   to **git-log reconstruction** (see below) instead of stopping. Only print
   "no session to restore" if git also yields nothing.

### Cross-machine fallback — reconstruct from git

When there's no local session.md (e.g., you just `/arrive`d on another
workstation), the handoff is the pushed commits. Reconstruct context:

```bash
git fetch --quiet 2>/dev/null
git log --oneline -15
git log --since="2 days ago" --pretty=format:'%h %s' 2>/dev/null
git diff --stat "@{u}"...HEAD 2>/dev/null   # if upstream tracking exists
```

Summarize: recent commits, what changed, current branch, and where work
appears to stand. Tell the user "No local session.md (it's same-machine);
reconstructed from git." Then offer to continue.

If a local session.md DOES exist (same machine you closed out on), use it —
it's richer. Parse it per below.

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
