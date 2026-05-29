---
description: List the closeout skill family with version, project context, and quick reference. Discoverability for the global commands.
---

# /family

## Help

Discoverability for the global closeout-family commands. Lists all 6 commands
with one-liners, current `~/.claude/VERSION`, and (if a `.claude/claude.yaml`
config exists in the current directory) the project-specific view of what
each command will run.

USAGE
  /family [--help]

OPTIONS
  --help, -h    Show this help and stop.

EXAMPLES
  /family                      # See the family + project context
  /family --help               # Show this help

FAMILY
  /closeout  Session closure (composes gate + hygiene + security; writes session.md)
  /gate      Quality gate (build, lint, types, design)
  /hygiene   Project audit (stale files, naming, governance)
  /depart    Workstation departure (push + Obsidian-aware vault sync)
  /arrive    Workstation arrival (pull + Obsidian-aware vault sync)
  /resume    Session start (reads .claude/session.md)

## Argument parsing

**FIRST, read the user's arguments:**

1. If args contain `--help`, `-h`, or `help`: render the **Help** section above and STOP.
2. (No other flags.)

## Execution

### Step 1 — Header block

Render this block first:

```
closeout-skill family  •  <VERSION-from-~/.claude/VERSION>
repo:  <output of: git -C ~/.claude/ remote get-url origin 2>/dev/null>
                  (or "(local-only; not synced)" if not a git repo)
```

### Step 2 — Project context (only if relevant)

If `./.claude/claude.yaml` exists:

```
project:   <project.name from config>
config:    .claude/claude.yaml (schema v<schema_version>, bootstrapped <bootstrapped_at>)
status:    <CLAUDE.md hash match?>
              "✓ CLAUDE.md unchanged since bootstrap"   if hashes match
              "⚠ CLAUDE.md changed — consider /closeout --init --refresh"   if hashes differ
```

If `./.claude/claude.yaml` does NOT exist:

```
project:   <basename of cwd>  (generic mode — no .claude/claude.yaml)
hint:      Run /closeout --init to bootstrap a project-aware config.
```

### Step 3 — Command list with project-aware details

For each command, render:

```
COMMAND       PURPOSE                                                    WILL RUN (if configured)
─────────────────────────────────────────────────────────────────────────────────────────────
/gate         Quality gate — blocks on failure                           <N> commands: <names>
/hygiene      Project audit — informs                                    <N> patterns + structure + governance
/closeout     Session closure — orchestrates the above + session.md      writes <closeout.session_md.path>
/depart       Workstation departure (Obsidian-aware vault sync)          push to <depart.remote>; vault: <state>
/arrive       Workstation arrival (Obsidian-aware vault sync)            <arrive.pull_strategy>; vault: <state>
/resume       Session start — reads session.md                           reads <closeout.session_md.path>
```

If in generic mode (no config), show "(generic)" in the WILL RUN column for the commands that read config.

### Step 4 — Cross-references

End with a hint line:

```
For per-command detail, run: /<command> --help
For sync status:             ~/.claude/sync.sh
For full design:             docs/superpowers/specs/2026-05-28-closeout-redesign-design.md
                              (in your canary project; not synced to ~/.claude/)
```
