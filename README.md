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

## Bootstrap a new workstation

```bash
# Backup any existing per-machine state
mv ~/.claude ~/.claude.local-backup 2>/dev/null

# Clone shared skill config into ~/.claude/
git clone https://github.com/ThomasNakios/claude-skill-dotfiles.git ~/.claude

# Restore per-machine state from backup
for d in memory projects sessions session-env shell-snapshots file-history \
         backups cache debug downloads tasks plans ide hooks bin skills \
         plugins paste-cache; do
  [ -d ~/.claude.local-backup/"$d" ] && cp -r ~/.claude.local-backup/"$d" ~/.claude/
done

# Restore individual per-machine files
for f in CLAUDE.md settings.json history.jsonl mcp-needs-auth-cache.json \
         stats-cache.json .last-cleanup .last-update-result.json; do
  [ -e ~/.claude.local-backup/"$f" ] && cp -P ~/.claude.local-backup/"$f" ~/.claude/
done

# Verify
ls ~/.claude/commands/ ~/.claude/docs/ ~/.claude/VERSION
```

After verification, you can `rm -rf ~/.claude.local-backup`.

## Sync discipline

Sync is integrated into the workflow commands `/depart` (push) and `/arrive`
(pull) — see those commands' execution sections. Behavior:

- `/depart` — if `~/.claude/` is dirty, prompts to commit + push before leaving.
- `/arrive` — pulls latest before resuming. Warns on conflicts.

Manual sync if needed:

```bash
cd ~/.claude && git pull        # before starting work
cd ~/.claude && git add -u && git commit -m "..." && git push   # before leaving
```

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
