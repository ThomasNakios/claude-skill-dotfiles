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

# Expected workstation environment (Phase 2 validation)
VAULT_DIR="$HOME/vault"
VAULT_REMOTE_EXPECTED="https://github.com/ThomasNakios/KnockersNoggin.git"
OBSIDIAN_APP="/Applications/Obsidian.app"
OBSIDIAN_GIT_PLUGIN="$VAULT_DIR/.obsidian/plugins/obsidian-git"
ICLOUD_CLAUDE_MD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/CLAUDE.md"

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
    # Use -L (symlink test) OR -e (target exists) so we preserve the
    # symlink even when its target (e.g. iCloud Drive) is momentarily
    # unreachable. Critical for CLAUDE.md → iCloud symlink on Mac Studio.
    if [ -L "$backup/$f" ] || [ -e "$backup/$f" ]; then
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

# ─────────────────────────────────────────────────────────────
# Phase 2 — Workstation environment validation (read-only)
# ─────────────────────────────────────────────────────────────
# Reports on Obsidian + vault + iCloud CLAUDE.md + project landscape.
# Never modifies anything; suggests fixes for any gaps it finds.

validate_workstation() {
  echo
  info "Workstation environment check (read-only):"
  local issues=0

  # 1. Obsidian app
  if [ -d "$OBSIDIAN_APP" ]; then
    ok "Obsidian:  installed at $OBSIDIAN_APP"
  else
    warn "Obsidian:  NOT found at $OBSIDIAN_APP"
    echo "             → Install from https://obsidian.md (or from the App Store / brew)"
    issues=$((issues + 1))
  fi

  # 2. Vault directory
  if [ ! -d "$VAULT_DIR" ]; then
    warn "Vault:     ~/vault/ does NOT exist"
    echo "             → Clone the vault repo: git clone $VAULT_REMOTE_EXPECTED $VAULT_DIR"
    issues=$((issues + 1))
  elif [ ! -d "$VAULT_DIR/.git" ]; then
    warn "Vault:     ~/vault/ exists but is NOT a git repo"
    echo "             → Initialize as git or re-clone from $VAULT_REMOTE_EXPECTED"
    issues=$((issues + 1))
  else
    ok "Vault:     ~/vault/ exists and is a git repo"

    # 2b. Vault remote
    local actual_remote
    actual_remote=$(git -C "$VAULT_DIR" remote get-url origin 2>/dev/null || echo "")
    if [ "$actual_remote" = "$VAULT_REMOTE_EXPECTED" ]; then
      ok "Vault rem: origin → $actual_remote"
    else
      warn "Vault rem: origin → $actual_remote"
      echo "             → Expected: $VAULT_REMOTE_EXPECTED"
      echo "             → Investigate manually; refusing to change remotes automatically."
      issues=$((issues + 1))
    fi

    # 2c. Obsidian Git plugin
    if [ -d "$OBSIDIAN_GIT_PLUGIN" ]; then
      ok "Git plug:  obsidian-git installed in vault"
    else
      warn "Git plug:  obsidian-git NOT found at $OBSIDIAN_GIT_PLUGIN"
      echo "             → In Obsidian: Settings → Community plugins → Browse → 'Obsidian Git' → Install + Enable"
      issues=$((issues + 1))
    fi
  fi

  # 3. iCloud-backed CLAUDE.md symlink
  if [ -L "$CLAUDE_DIR/CLAUDE.md" ]; then
    local target
    target=$(readlink "$CLAUDE_DIR/CLAUDE.md")
    if [ "$target" = "$ICLOUD_CLAUDE_MD" ]; then
      if [ -e "$ICLOUD_CLAUDE_MD" ]; then
        ok "CLAUDE.md: symlink → iCloud Drive (target reachable)"
      else
        warn "CLAUDE.md: symlink → iCloud Drive (target NOT reachable right now)"
        echo "             → Check iCloud Drive is signed in + has finished syncing"
      fi
    else
      warn "CLAUDE.md: symlink → $target (not the expected iCloud path)"
      echo "             → Expected: $ICLOUD_CLAUDE_MD"
    fi
  elif [ -e "$CLAUDE_DIR/CLAUDE.md" ]; then
    warn "CLAUDE.md: exists but is NOT a symlink to iCloud Drive"
    echo "             → On your other workstations CLAUDE.md is symlinked to:"
    echo "                  $ICLOUD_CLAUDE_MD"
    echo "             → To match: rm ~/.claude/CLAUDE.md && ln -s '$ICLOUD_CLAUDE_MD' ~/.claude/CLAUDE.md"
  else
    warn "CLAUDE.md: missing"
    echo "             → If iCloud has it: ln -s '$ICLOUD_CLAUDE_MD' ~/.claude/CLAUDE.md"
  fi

  # 4. Project landscape under ~/Workspaces/
  if [ -d "$HOME/Workspaces" ]; then
    local total bootstrapped
    total=$(find "$HOME/Workspaces" -maxdepth 2 -type d -name ".claude" 2>/dev/null | wc -l | tr -d ' ')
    bootstrapped=$(find "$HOME/Workspaces" -maxdepth 3 -type f -name "claude.yaml" -path "*/.claude/*" 2>/dev/null | wc -l | tr -d ' ')
    info "Projects:  ~/Workspaces/ — $total with .claude/, $bootstrapped bootstrapped with claude.yaml"
    if [ "$total" -gt "$bootstrapped" ]; then
      echo "             → Projects without claude.yaml can be bootstrapped via /closeout --init from inside the project."
    fi
  else
    info "Projects:  ~/Workspaces/ not found (skipping project scan)"
  fi

  # 5. Summary
  echo
  if [ "$issues" -eq 0 ]; then
    ok "Workstation correctly configured for closeout family."
  else
    warn "Workstation environment: $issues issue(s) flagged above. Skill files still synced; fix issues to enable the full closeout/depart/arrive flow."
  fi
}

main() {
  info "Detecting state of $CLAUDE_DIR ..."
  local state
  state=$(detect_state)
  info "State: $state"
  echo

  local sync_rc=0
  case "$state" in
    fresh)        handle_fresh        || sync_rc=$? ;;
    migrate)      handle_migrate      || sync_rc=$? ;;
    synced-clean) handle_synced_clean || sync_rc=$? ;;
    synced-dirty) handle_synced_dirty || sync_rc=$? ;;
    wrong-remote) handle_wrong_remote || sync_rc=$? ;;
    *)            err "Unknown state: $state"; exit 2 ;;
  esac

  # Always run the workstation validation, even if sync had issues —
  # the user still benefits from knowing what else is mis-configured.
  validate_workstation

  return $sync_rc
}

main "$@"
