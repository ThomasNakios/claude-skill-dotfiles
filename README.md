# claude-skill-dotfiles

Global Claude Code skill files synced across Thomas's 6 workstations.

## What lives here

- `commands/` — global slash-command markdown files (read by Claude Code agents)
- `docs/` — reference documents the commands consume (schema, templates)
- `VERSION` — current skill version (single line, e.g. `closeout-skill@0.1.0`)

## What does NOT live here

Everything else under `~/.claude/` is per-machine state (memory, projects,
sessions, cache, history, plugins, settings, etc.) and stays local. See
`.gitignore` for the whitelist.

## Sync — one script, any workstation, anytime

`sync.sh` is the universal entry point. It's idempotent: safe to run on a
fresh workstation (clones), on a migration target (backs up per-machine state
then clones then restores), or on an already-synced workstation (fast-forward
pulls). It auto-detects which case you're in.

**First time on a new workstation** (or any time you want a clean re-sync from
a non-bootstrapped state):

```bash
curl -fsSL https://raw.githubusercontent.com/ThomasNakios/claude-skill-dotfiles/main/sync.sh | bash
```

**Already bootstrapped** — pull latest skill updates:

```bash
~/.claude/sync.sh
```

The script reports its detected state up front:

| State | Action |
|---|---|
| `fresh` | `~/.claude/` doesn't exist → clones the repo |
| `migrate` | `~/.claude/` exists but isn't a git repo → backs up per-machine state, clones, restores state. Backup preserved at `~/.claude.bootstrap-backup.<timestamp>/` until you remove it. |
| `synced-clean` | Already a git repo, no local changes → fast-forward pull |
| `synced-dirty` | Already a git repo, has local changes → refuses to pull. Tells you how to resolve (`/depart` to commit first, or discard) |
| `wrong-remote` | Already a git repo but points elsewhere → refuses to proceed. Investigate manually. |

Per-machine state preserved across `migrate` runs:

- Dirs: `memory/`, `projects/`, `sessions/`, `session-env/`, `shell-snapshots/`,
  `file-history/`, `backups/`, `cache/`, `debug/`, `downloads/`, `tasks/`,
  `plans/`, `ide/`, `hooks/`, `bin/`, `skills/`, `plugins/`, `paste-cache/`
- Files: `CLAUDE.md`, `settings.json`, `history.jsonl`,
  `mcp-needs-auth-cache.json`, `stats-cache.json`, `.last-cleanup`,
  `.last-update-result.json`

(`CLAUDE.md` is typically a symlink to iCloud Drive — symlinks are preserved.)

## Sync discipline

`sync.sh` is also called automatically by the workflow commands:

- `/arrive` — runs `sync.sh` (synced-clean / synced-dirty path) before pulling the project. You start work on the latest skill files.
- `/depart` — checks if `~/.claude/` has uncommitted changes; prompts to commit + push before leaving.

You don't need to invoke `sync.sh` manually in day-to-day use — `/arrive` and
`/depart` handle it. Direct invocation is useful for: bootstrapping new
workstations, recovering from a `wrong-remote` or `synced-dirty` state, or
forcing a sync between `/arrive`/`/depart` invocations.

## Cross-repo composition

At each workstation boundary, three repos may need syncing:

| Repo | Owner | Sync mechanism |
|---|---|---|
| Current project (cwd) | `/arrive` / `/depart` | git pull/push |
| `~/.claude/` (this repo) | `/arrive` calls `sync.sh`; `/depart` prompts to push | git pull/push via `sync.sh` |
| `~/vault/` (KnockersNoggin) | Obsidian Git plugin (auto-commit every 5 min) when running; `/arrive` / `/depart` when Obsidian is quit | Obsidian-aware fallback |

**Obsidian-aware vault integration:**

- `/depart` and `/arrive` detect whether Obsidian is running via `pgrep -i -x Obsidian`.
- **Obsidian running:** Skip vault sync. Trust the Git plugin's 5-min auto-commit timer.
- **Obsidian not running:** Treat vault like any other git repo — fetch on arrival, prompt to commit + push on departure.

This prevents the workflow commands from racing with Obsidian's auto-commit while still covering the CLI-edits-with-Obsidian-quit case noted in your global CLAUDE.md.

## Versioning

When changing any global command or doc, bump `VERSION` (e.g. `0.1.0` →
`0.1.1`) so downstream workstations can tell at a glance whether they're
running the latest. The current version is surfaced in `/closeout --help`'s
status preamble.

## Family

Slash commands shipped from here:

| Command | Purpose |
|---|---|
| `/closeout` | Session closure — composes gate + hygiene + security, writes `.claude/session.md` |
| `/gate` | Quality gate — build, lint, types, design |
| `/hygiene` | Project audit — stale files, naming, governance |
| `/depart` | Workstation departure — commit + push |
| `/arrive` | Workstation arrival — pull + post-pull hooks |
| `/resume` | Session start — reads `.claude/session.md` |

See the design spec in `capital-manager` (canary project):
`docs/superpowers/specs/2026-05-28-closeout-redesign-design.md`
