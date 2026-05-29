#!/usr/bin/env bash
#
# sync.sh — idempotent sync of ~/.claude/ to the claude-skill-dotfiles repo.
# Safe to run anytime on any workstation. Installs on a fresh machine,
# updates on a synced one.
#
# Detects the workstation's current state and does the right thing:
#
#   fresh         ~/.claude/ doesn't exist
#                 → clone the repo
#
#   migrate       ~/.claude/ exists but is not a git repo
#                 → back up per-machine state, clone, restore state
#
#   synced-clean  ~/.claude/ is the repo, no local changes
#                 → fetch + fast-forward pull
#
#   synced-dirty  ~/.claude/ is the repo, but has uncommitted changes
#                 → warn user (run /depart to commit first, then re-run)
#
#   wrong-remote  ~/.claude/ is a git repo but pointed elsewhere
#                 → error, ask user to investigate
#
# Usage:
#   # First-time on a new workstation (or anytime, anywhere — it's idempotent):
#   curl -fsSL https://raw.githubusercontent.com/ThomasNakios/claude-skill-dotfiles/main/sync.sh | bash
#
#   # Already cloned (the normal case):
#   ~/.claude/sync.sh

set -euo pipefail

REPO_URL="https://github.com/ThomasNakios/claude-skill-dotfiles.git"
CLAUDE_DIR="$HOME/.claude"

# Per-machine state that must survive a fresh clone
PER_MACHINE_DIRS=(
  memory projects sessions session-env shell-snapshots file-history
  backups cache debug downloads tasks plans ide hooks bin skills
  plugins paste-cache
)
PER_MACHINE_FILES=(
  CLAUDE.md settings.json history.jsonl mcp-needs-auth-cache.json
  stats-cache.json .last-cleanup .last-update-result.json
)

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info()  { color '36' "→ $1"; }
ok()    { color '32' "✓ $1"; }
warn()  { color '33' "⚠ $1"; }
err()   { color '31' "✗ $1"; }

detect_state() {
  if [ ! -d "$CLAUDE_DIR" ]; then
    echo fresh
  elif [ ! -d "$CLAUDE_DIR/.git" ]; then
    echo migrate
  else
    local actual
    actual=$(git -C "$CLAUDE_DIR" remote get-url origin 2>/dev/null || echo "")
    if [ "$actual" != "$REPO_URL" ]; then
      echo wrong-remote
    elif [ -n "$(git -C "$CLAUDE_DIR" status --porcelain)" ]; then
      echo synced-dirty
    else
      echo synced-clean
    fi
  fi
}

handle_fresh() {
  info "No ~/.claude/ found — fresh clone."
  git clone "$REPO_URL" "$CLAUDE_DIR"
  ok "Cloned into $CLAUDE_DIR"
  ok "Version: $(cat "$CLAUDE_DIR/VERSION" 2>/dev/null || echo unknown)"
}

handle_migrate() {
  local backup="$HOME/.claude.bootstrap-backup.$(date +%Y%m%d-%H%M%S)"
  info "~/.claude/ exists but is not a git repo. Migrating."
  info "  Backup: $backup"
  mv "$CLAUDE_DIR" "$backup"

  info "  Cloning $REPO_URL → $CLAUDE_DIR"
  git clone "$REPO_URL" "$CLAUDE_DIR"

  info "  Restoring per-machine state from backup."
  for d in "${PER_MACHINE_DIRS[@]}"; do
    if [ -d "$backup/$d" ]; then
      cp -R "$backup/$d" "$CLAUDE_DIR/"
      printf '    + %s/\n' "$d"
    fi
  done
  for f in "${PER_MACHINE_FILES[@]}"; do
    if [ -e "$backup/$f" ]; then
      cp -P "$backup/$f" "$CLAUDE_DIR/"
      printf '    + %s\n' "$f"
    fi
  done

  ok "Migration complete. Backup preserved at: $backup"
  warn "Once you've verified everything works, you can remove the backup:"
  echo "    rm -rf '$backup'"
  ok "Version: $(cat "$CLAUDE_DIR/VERSION" 2>/dev/null || echo unknown)"
}

handle_synced_clean() {
  info "~/.claude/ already synced. Fetching latest."
  local before after
  before=$(cat "$CLAUDE_DIR/VERSION" 2>/dev/null || echo "")
  git -C "$CLAUDE_DIR" fetch --quiet origin

  if [ -z "$(git -C "$CLAUDE_DIR" rev-list HEAD..origin/main)" ]; then
    ok "Already at origin/main. Nothing to do. (Version: $before)"
    return 0
  fi

  if ! git -C "$CLAUDE_DIR" merge --ff-only origin/main --quiet; then
    err "Fast-forward failed. Local main has diverged from origin/main."
    err "Resolve manually:"
    echo "    cd $CLAUDE_DIR && git status"
    return 1
  fi
  after=$(cat "$CLAUDE_DIR/VERSION" 2>/dev/null || echo "")
  ok "Pulled. Version: $before → $after"
}

handle_synced_dirty() {
  warn "~/.claude/ has uncommitted local changes:"
  git -C "$CLAUDE_DIR" status --short
  echo
  warn "Pull skipped to avoid clobbering. Resolve by either:"
  echo "    1. Run /depart from a Claude session (will prompt to commit + push)"
  echo "    2. Manual:  cd $CLAUDE_DIR && git add -u && git commit -m '...' && git push"
  echo "    3. Discard: cd $CLAUDE_DIR && git checkout ."
  echo "  Then re-run this script."
  return 1
}

handle_wrong_remote() {
  err "~/.claude/ is a git repo but points to a different remote."
  err "  Expected: $REPO_URL"
  err "  Actual:   $(git -C "$CLAUDE_DIR" remote get-url origin 2>/dev/null || echo '<none>')"
  err "Investigate before continuing — refusing to overwrite."
  return 1
}

main() {
  info "Detecting state of $CLAUDE_DIR ..."
  local state
  state=$(detect_state)
  info "State: $state"
  echo

  case "$state" in
    fresh)        handle_fresh        ;;
    migrate)      handle_migrate      ;;
    synced-clean) handle_synced_clean ;;
    synced-dirty) handle_synced_dirty ;;
    wrong-remote) handle_wrong_remote ;;
    *)            err "Unknown state: $state"; exit 2 ;;
  esac
}

main "$@"
