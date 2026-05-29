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
  /gate      Quality gate
  /hygiene   Project audit
  /closeout  Session closure
  /depart    Workstation departure
  /resume    Session start (reads session.md)

## Argument parsing

1. If args contain `--help`, `-h`, or `help`: render Help and STOP.
2. If args contain `--dry-run`: set `DRY_RUN=true`.

## Execution

### Step 0 — Sync ~/.claude/ from the dotfiles repo (best-effort)

Before pulling the project, refresh the global skill files so this workstation
runs the latest gate/hygiene/closeout/etc.

```bash
if [ -d ~/.claude/.git ]; then
  ( cd ~/.claude && git fetch -q && git status --porcelain )
fi
```

- If `~/.claude/` has uncommitted changes: warn the user and skip the auto-pull.
  They probably mean to commit those locally first (via `/depart`).
- If clean: `cd ~/.claude && git pull --ff-only -q origin main` (unless `DRY_RUN`).
  If fast-forward fails (divergent history): report and ask user to resolve manually.
- If `~/.claude/` is not a git repo: skip silently. (Workstation hasn't been bootstrapped.)

After pull, report the new `~/.claude/VERSION` line.

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
