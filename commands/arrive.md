---
description: Workstation arrival — pull latest, run post-pull hooks, suggest /resume.
---

# /arrive

## Help

Arrive at this workstation: pull latest changes, run post-pull hooks (e.g., npm install if package.json changed), self-heal missing dependencies (fresh clone with no node_modules), and suggest `/resume` to restore the previous session.

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

### Step 0a — Sync ~/.claude/ from the dotfiles repo (best-effort)

Before pulling the project, refresh the global skill files so this workstation
runs the latest gate/hygiene/closeout/etc. Delegate to the idempotent sync
script:

```bash
if [ -x ~/.claude/sync.sh ]; then
  ~/.claude/sync.sh           # unless DRY_RUN; the script is state-aware
fi
```

The script handles all cases (clean pull, dirty warning, divergent history,
non-bootstrapped workstation). Read its reported state and surface to the user
as part of `/arrive`'s output.

- If the script reports `synced-dirty`: don't block — continue with project pull,
  but tell the user their skill changes are still uncommitted and suggest
  `/depart` later to push them.
- If `wrong-remote`: surface the error; don't continue. User must investigate.
- If the script isn't present at all (`~/.claude/sync.sh` missing): skip silently
  and continue. (Older workstation; can be bootstrapped later with the curl
  one-liner from the repo README.)

### Step 0b — Sync vault (Obsidian-aware)

If `~/vault/` exists and is a git repo, refresh it so personal notes from the
previous workstation are visible — but only if Obsidian isn't already managing
the sync.

```bash
OBSIDIAN_RUNNING=false
if pgrep -i -x Obsidian >/dev/null 2>&1; then
  OBSIDIAN_RUNNING=true
fi
```

Branches:

- `~/vault/` does not exist OR is not a git repo: skip silently.
- Obsidian is running: report **"Vault: Obsidian active — it'll pull on its own. Skipping."** Don't fight the Git plugin.
- Obsidian is NOT running:
  - `git -C ~/vault fetch --quiet`
  - If `git -C ~/vault status --porcelain` shows uncommitted local changes: warn
    and skip pull (don't clobber). Tell user to resolve via `/depart` or manually.
  - Else: `git -C ~/vault pull --ff-only --quiet origin <main-branch>` (unless `DRY_RUN`).
    On fast-forward failure: warn about divergent history; user resolves manually.

Report what happened to the vault (synced, skipped, or warned).

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
# HEAD@{1} doesn't exist on a fresh clone (reflog has 1 entry). Guard it,
# otherwise the diff errors and the changed-files list is undefined.
if git rev-parse --verify --quiet 'HEAD@{1}' >/dev/null; then
  git diff --name-only 'HEAD@{1}' HEAD
else
  : # fresh clone — no previous HEAD, changed-files list is empty
fi
```

### Post-pull hooks

For each hook in `post_pull_hooks`:
- If any file matched by `if_changed` glob is in the changed-files list: run `run` (unless `DRY_RUN`).
- Print `▶ hook: <if_changed> changed → <run>`.

If any hook ran a dependency install this invocation (its `run` contains
`install`, `ci`, `pnpm i`, `yarn`, `bun install`, etc.), set `DEPS_HANDLED=true`
so the self-heal step below doesn't double-install.

### Dependency self-heal (zero-config safety net)

`post_pull_hooks` only fire when a watched file appears in the changed-files
list — so they never fire on a **fresh clone** (no previous HEAD → empty diff),
which is exactly when dependencies have *never* been installed. This step is
the safety net that makes a clone self-heal, and it needs no `claude.yaml`.

Skip entirely if `DEPS_HANDLED=true` (a hook already installed this run).

Detect the JS package manager from the lockfile at the repo root and whether an
install is actually needed:

```bash
ROOT=$(git rev-parse --show-toplevel)
NEED_INSTALL=false
PM=""; INSTALL_ARGS=""

if [ -f "$ROOT/package.json" ]; then
  # Pick package manager by lockfile (most specific wins).
  if   [ -f "$ROOT/pnpm-lock.yaml" ];     then PM=pnpm; INSTALL_ARGS="install --frozen-lockfile"
  elif [ -f "$ROOT/yarn.lock" ];          then PM=yarn; INSTALL_ARGS="install --immutable"
  elif [ -f "$ROOT/bun.lockb" ] || [ -f "$ROOT/bun.lock" ]; then PM=bun; INSTALL_ARGS="install --frozen-lockfile"
  elif [ -f "$ROOT/package-lock.json" ];  then PM=npm;  INSTALL_ARGS="ci"
  else                                         PM=npm;  INSTALL_ARGS="install"   # no lockfile
  fi

  # Resolve HOW to invoke the package manager. A repo may pin one via the
  # "packageManager" field (e.g. "pnpm@9.0.0") without that binary being on
  # PATH. corepack (ships with Node ≥16.9) shims the pinned version, so prefer
  # `corepack <pm>` whenever the bare binary is missing but corepack exists.
  if command -v "$PM" >/dev/null 2>&1; then
    PM_RUN="$PM"
  elif command -v corepack >/dev/null 2>&1; then
    PM_RUN="corepack $PM"   # honors the pinned packageManager version
  else
    PM_RUN=""               # neither available — can't install
  fi
  INSTALL_CMD="${PM_RUN:+$PM_RUN }$INSTALL_ARGS"

  # Trigger when deps are absent (fresh clone) OR a lockfile/manifest changed
  # in this pull but no hook covered it.
  if [ ! -d "$ROOT/node_modules" ]; then
    NEED_INSTALL=true; REASON="node_modules missing (fresh clone or never installed)"
  elif git diff --name-only 'HEAD@{1}' HEAD 2>/dev/null | grep -Eq '(^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lock(b)?)$'; then
    NEED_INSTALL=true; REASON="lockfile/manifest changed in this pull"
  fi
fi

if [ "$NEED_INSTALL" = true ]; then
  if [ -z "$PM_RUN" ]; then
    echo "⚠ deps: $REASON, but '$PM' is not on PATH and corepack is unavailable — skipping. Install $PM (or enable corepack) and re-run /arrive."
  else
    echo "▶ deps: $REASON → $INSTALL_CMD"
    # run $INSTALL_CMD here unless DRY_RUN
  fi
fi
```

Notes:
- If a lockfile exists, the install uses the **frozen/immutable** form (`npm ci`,
  `pnpm install --frozen-lockfile`, `yarn install --immutable`,
  `bun install --frozen-lockfile`) — reproducible, matches the lockfile exactly.
  Only the lockfile-less fallback uses a plain `install`.
- **Corepack fallback:** if the chosen package manager isn't on PATH but the
  repo pins it via `packageManager` (common with pnpm/yarn), the install is run
  as `corepack <pm> …`, which shims the pinned version. If neither the bare
  binary nor corepack is available, the step prints a `⚠ deps:` warning and
  skips rather than failing the whole arrival — the user installs the PM (or
  enables corepack) and re-runs `/arrive`.
- If `DRY_RUN`: print the `▶ deps:` line but do **not** run the install.
- If the install command fails (e.g. frozen lockfile out of sync with
  `package.json`): report the failure and exit non-zero (exit code 1), same as a
  failed post-pull hook. Suggest the user reconcile the lockfile.
- Non-JS projects (no `package.json`): this step is a silent no-op. Other
  ecosystems (Python venvs, etc.) are out of scope here; add a per-project
  `post_pull_hook` if needed.

### Final summary

```
arrive summary:
  workstation: <hostname>
  branch:      <current>
  pulled:      <N commits, M files>          ← the cross-machine handoff
  hooks ran:   [npm install]
  deps:        [npm ci — node_modules was missing] | up to date | n/a

Suggested next: /resume — it reads the pulled git log to reconstruct where
work stands. (A local .claude/session.md from the previous machine won't be
here; it's same-machine-only. /resume handles that.)
```

If `suggest_resume: true`: always suggest `/resume` (it reconstructs from git
even when no local session.md exists). If a local session.md happens to be
present (you'd been on this box before), `/resume` uses it as the richer source.
