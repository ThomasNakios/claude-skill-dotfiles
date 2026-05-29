# Closeout Canary Findings

**Canary project:** capital-manager
**Canary start:** 2026-05-29
**Status:** Active battle-test
**Skill version on canary start:** `closeout-skill@0.1.5`
**Config commit:** `d251136a`

> Working notes for the closeout-skill canary on capital-manager. Captures gaps,
> tweaks, false positives, and learnings. After ~5 real `/closeout` sessions
> with no blocker-level issues, declare canary stable and move to Phase 2
> (rollout to other 14 projects).

---

## Known gaps to watch

These were identified during bootstrap and deferred. If any bites during the
canary week, escalate to "fix during canary" status.

### G1 — Soft-delete filter check (NON-NEGOTIABLE in CLAUDE.md, not encoded)

**CLAUDE.md §4:** "All queries must filter `.eq('is_deleted', false)`. Never use `.delete()`."

**Why deferred:** Not all tables have `is_deleted`. A naive `grep-required-pair` anchored on `\.from\(` with `required_pattern: is_deleted` would generate massive false positives for tables that don't have soft-delete (lookup tables, audit tables, etc.).

**Options if it bites:**
1. Build an `audit:soft-delete` project script that knows which tables have `is_deleted` (would query the schema or maintain an allowlist)
2. Encode as `manual-review` rule (requires schema extension)
3. Rely on PR review discipline

**Suggested:** Option 1 if a real bug is missed during canary.

### G2 — `audit:naming` script not wired in

Capital-manager has `npm run audit:naming` (`scripts/audit-naming-conventions.ts`). The config encodes naming rules statically in `hygiene.file_structure.naming_rules`. The shell-based audit would be more accurate (knows about project-specific exceptions).

**Suggested fix during canary:** Add to `hygiene.patterns` as a `kind: shell` warn-level check. Wait for static rules to misfire first.

### G3 — `audit:full` not wired in

`npm run audit:full` runs the whole project audit suite. Likely too slow for every `/closeout`, but valuable as a periodic deep check.

**Suggested:** Add to a future `/closeout --deep` flag or a separate cron-scheduled run.

### G4 — Testing rules from CLAUDE.md aren't enforceable

CLAUDE.md says "Every new Page/Component must have a corresponding page-object created in e2e/page-objects" and "Every Server Action modification requires a corresponding integration test in `__tests__/actions`." These are workflow rules, not file-presence rules — hard to encode without knowing "what's new."

**Suggested:** Leave as documentation. Maybe add `test:check-drift` (which exists in package.json) to hygiene as a warn-level check.

---

## Workstation bootstrap checklist

### ⭐ THE COMMAND — run this on EVERY machine

Copy-paste this exact line into the terminal on any workstation (NYC Mac Studio,
NYC Home, NYC Work, Charleston Home, Charleston Work, Laptop). Idempotent —
safe to run the first time AND every time after.

```bash
curl -fsSL https://raw.githubusercontent.com/ThomasNakios/claude-skill-dotfiles/main/sync.sh | bash
```

That's the only command you need. It will:
1. Install (fresh machine) or update (already set up) the global Claude skills in `~/.claude/`
2. Preserve all per-machine state (memory, sessions, settings)
3. Run the workstation environment check (Obsidian, vault, Git plugin, iCloud CLAUDE.md, projects)
4. Report what's correct and suggest fixes for anything that isn't

If `~/.claude/sync.sh` already exists on the machine, you can also just run:

```bash
~/.claude/sync.sh
```

(Same behavior — the curl form is for the very first run when the script isn't on disk yet.)

### Verify after running

```bash
ls ~/.claude/commands/        # closeout.md, gate.md, hygiene.md, depart.md, arrive.md, resume.md, family.md
cat ~/.claude/VERSION         # closeout-skill@0.1.7 (or newer)
```

### Per-workstation log

6 workstations total across 2 cities + a laptop. Check off as each is bootstrapped.

**NYC:**
- [ ] **Mac Studio** (vault-canonical per global CLAUDE.md; runs Obsidian most actively)
- [ ] **NYC Home** Mac
- [x] **NYC Work** Mac — bootstrapped via `sync.sh`

**Charleston:**
- [ ] **Charleston Home** Mac
- [ ] **Charleston Work** Mac

**Portable:**
- [x] **Laptop** — canary origin; pushed `closeout-skill@0.1.5` initial commits to `claude-skill-dotfiles` on 2026-05-28

**Status: 2 of 6 done. 4 remaining.**

One-liner for each remaining machine:

```bash
curl -fsSL https://raw.githubusercontent.com/ThomasNakios/claude-skill-dotfiles/main/sync.sh | bash
```

> **Note on Mac Studio:** sync.sh is idempotent and doesn't touch `~/vault/` — the Mac Studio's role as vault-canonical is irrelevant to the script. `/depart` and `/arrive` are Obsidian-aware, so vault sync defers to the Git plugin whenever Obsidian is running (which on the Mac Studio is most of the time). See [decision D2](#d2--removed-npx-supabase-db-reset-from-arrivepost_pull_hooks) and the spec §3 for why these are decoupled.

---

## Findings log

Add an entry after each `/closeout` session, even if uneventful. The point is
seeing patterns. After 5+ uneventful sessions, canary is stable.

### Session template

```markdown
### YYYY-MM-DD — [one-line session summary]

- **Branch:** <branch>
- **/closeout result:** clean | warnings (N) | blockers (N)
- **Time on closeout:** <approx minutes>
- **What worked well:** <list>
- **What didn't:** <list>
- **Action items:** <list>
```

---

### Session log entries

<!-- New entries go BELOW this line in reverse-chronological order (newest first) -->

### 2026-05-29 — Canary launch session (bootstrap, not a real /closeout run)

- **Branch:** production
- **/closeout result:** N/A — bootstrap only
- **What worked well:**
  - Global skill files (`~/.claude/commands/`) installed and sync via `sync.sh`
  - Bootstrap correctly mined existing project knowledge into `.claude/claude.yaml`
  - Critical fixes caught before accept: destructive `db reset` hook removed, parallel-gate disabled, role-string + API-auth coverage added
- **What didn't:**
  - Initial bootstrap subagent timed out at 20 min — had to drive manually. Suggests Phase 1 bootstrap workflow needs a tighter prompt/scope for future projects.
- **Action items:**
  - Use `/closeout` at end of every real session for a week
  - Watch for false positives in the new role-strings grep (could trip on legitimate constants)
  - Confirm `audit:tenant-isolation` and other shell-based security checks actually exit non-zero on violations (some project audits are report-only by default)

---

## Decisions made during canary

Record judgment calls so future-you knows why.

### D1 — `gate.parallel: false`
Capital-manager's gate commands each set `NODE_OPTIONS='--max-old-space-size=4096'`. 4 in parallel = 16GB peak; exceeds RAM on 16GB-class Macs. Will revisit if a higher-RAM machine is used or if commands are made memory-efficient.

### D2 — Removed `npx supabase db reset` from `arrive.post_pull_hooks`
Destructive (wipes local seed/test data). User decides per-migration whether to `db push` or `db reset`. May add a `notify_on_changed` schema extension later for soft alerts.

### D3 — Soft-delete check deferred (G1)
False-positive risk too high without per-table awareness. Accepting risk for canary.

---

## Stability declaration

When this section reads "Canary stable as of YYYY-MM-DD after N sessions, no blockers," Phase 2 (other 14 projects) can begin.

**Current state:** In progress. 0 real sessions logged.

---

## Cross-references

- **Design spec:** [2026-05-28-closeout-redesign-design.md](2026-05-28-closeout-redesign-design.md)
- **Implementation plan:** [2026-05-28-closeout-redesign-implementation.md](2026-05-28-closeout-redesign-implementation.md)
- **Canary project config:** `capital-manager/.claude/claude.yaml` (lives in the capital-manager repo, not here)
- **Skill repo (this doc's home):** https://github.com/ThomasNakios/claude-skill-dotfiles
- **Global VERSION:** `~/.claude/VERSION`

> **Doc location note:** These design docs moved from
> `capital-manager/docs/superpowers/` to the `claude-skill-dotfiles` repo
> (`~/.claude/design/`) on 2026-05-29. The skill is a global tool; capital-manager
> is just the canary. The project's own `.claude/claude.yaml` stays in capital-manager.
