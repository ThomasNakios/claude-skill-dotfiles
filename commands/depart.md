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

### Sync ~/.claude/ dotfiles repo

After the project's branches are pushed, also sync any local changes to the
global skill files so the next workstation gets them.

```bash
if [ -d ~/.claude/.git ]; then
  ( cd ~/.claude && git status --porcelain )
fi
```

- If `~/.claude/` is not a git repo: skip. (Workstation isn't using the dotfiles repo.)
- If clean: nothing to do.
- If dirty: list the changed files. Ask user "Commit + push these skill changes? [y/N/edit-message]".
  - On `y`: stage tracked changes (`git add -u`), commit with `chore(skill): <branch-or-timestamp>`, push to origin main. (Skip if `DRY_RUN`.)
  - On `edit-message`: prompt for message, then commit + push.
  - On `N`: skip; warn user the receiving machine will be on an older version.
- After push, report the new `~/.claude/VERSION` line.

### Sync vault (Obsidian-aware)

If `~/vault/` exists and is a git repo, sync it too — but only if Obsidian
isn't already managing it. Obsidian's Git plugin auto-commits every 5 min;
duplicate manual sync would race with it.

```bash
# Detect Obsidian
OBSIDIAN_RUNNING=false
if pgrep -i -x Obsidian >/dev/null 2>&1; then
  OBSIDIAN_RUNNING=true
fi
```

Branches:

- `~/vault/` does not exist OR is not a git repo: skip silently.
- Obsidian is running: report **"Vault: Obsidian active — auto-commit handles sync. Skipping."** and move on. Trust the Git plugin.
- Obsidian is NOT running:
  - Check `git -C ~/vault/ status --porcelain`.
  - If clean: report "Vault: clean."
  - If dirty: list changes, prompt **"Commit + push vault changes? [y/N/edit-message]"**.
    - On `y`: `cd ~/vault && git add -u && git commit -m "depart: <hostname> @ <timestamp>" && git push` (skip if `DRY_RUN`).
    - On `edit-message`: prompt for message.
    - On `N`: warn — the receiving machine won't see these vault edits.
  - Even if working tree was clean, if local branch is ahead of remote: push (unless `DRY_RUN`).

After this step, report whether vault was synced or skipped.

### Cross-machine handoff note (framing)

**The pushed git commits ARE the cross-machine handoff.** `session.md` is
same-machine working memory (gitignored) — it stays on THIS box and does not
travel. So the receiving machine's continuity comes from the commits you just
pushed, not from session.md.

- If the session produced meaningful work, ensure the commit messages carry the
  intent (they're what the next machine reads). If they're thin, consider an
  amend or a follow-up annotation commit before departing.
- If you did **vault** work this session, that's separate — update the vault's
  own `~/vault/05-system/operations/session-handoff.md` (the vault's canonical
  cross-machine doc) if you haven't. `/depart` does NOT auto-write project state
  into it.

### Final summary

```
depart summary:
  workstation: <hostname>
  branch:      <current>
  pushed:      [branch1, branch2]            ← the cross-machine handoff
  session.md:  written (same-machine only; stays here)

Ready. On the receiving machine: /arrive to pull the commits, then /resume
(it reconstructs from git log; session.md won't be there — that's expected).
```
