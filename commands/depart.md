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
  /gate      Quality gate
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
