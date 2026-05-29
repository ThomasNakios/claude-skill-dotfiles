---
description: Review the current session and propose vault writes (decisions, lessons, touches, entity stubs) to 00-inbox/
argument-hint: [optional focus hint, e.g. "just decisions"]
---

# /synthesize — propose vault writes from the current session

You are reviewing the **entire conversation up to this point** in this Claude Code session and proposing structured writes to the KnockersNoggin vault. This is a **Level 2** action per AGENTS.md §7 — you propose; the user accepts/edits/rejects before anything lands in `02-wiki/`.

## Input

User argument: `$ARGUMENTS` (optional focus hint — may be empty)

If `$ARGUMENTS` mentions a category (e.g. "just decisions", "lessons only", "entity stubs"), narrow to that. Otherwise scan all five categories below.

## What to look for

Review the conversation for these signals:

1. **Decisions** — moments where the user (or you, with the user's go-ahead) chose between alternatives, locked an approach, or said "let's do X not Y." → `02-wiki/concepts/decisions/<YYYY-MM-DD>-<slug>.md` with sections `## Context`, `## Decision`, `## Consequences`.
2. **Lessons** — corrections from the user, mistakes you made that have a generalizable rule, "next time, do X" moments. → `02-wiki/concepts/lessons/<slug>.md`.
3. **Touches** — entities (people, firms, places) the user mentioned engaging with (calls, meetings, emails, decisions about). → propose `/touch <Name> — <note>` invocations (don't run them; show them as a copy-paste block).
4. **Entity stubs** — people, firms, or places mentioned that don't yet exist in the vault. Use Glob to check. → propose new stubs at the correct §4 path.
5. **Operational changes** — new scripts, configs, processes that should land in `05-system/operations/` (rare in a single session but possible).

## What to do

1. **Scan the conversation.** Identify candidates for each category. Be conservative — only propose things that have clear value beyond ephemeral. A passing mention of CNG isn't a touchpoint; "I called Ross about CNG-1730-MS" is.
2. **Check existence.** For every proposed `02-wiki/` write, Glob to verify the file doesn't already exist. If it does, propose an Edit rather than a new write.
3. **Stage proposals in `00-inbox/`** — DO NOT write to `02-wiki/` directly:
   - Decision proposals: `00-inbox/<YYYY-MM-DD>-decision-<slug>.md` with `type: decision`, full sections, `source: claude-interactive`. The user reviews and either moves to `02-wiki/concepts/decisions/` or rejects.
   - Lesson proposals: `00-inbox/<YYYY-MM-DD>-lesson-<slug>.md`, `type: lesson`.
   - Entity stub proposals: `00-inbox/<YYYY-MM-DD>-stub-<slug>.md`, `type: <person|firm|place>`, with a comment line `<!-- PROPOSED destination: 02-wiki/<domain>/<subdir>/<slug>.md -->` near the top.
   - Touch proposals: do NOT write a file; print as a runnable command list at the end.
4. **For each proposed write**, the frontmatter MUST include all four universal keys (`type`, `source: claude-interactive`, `created: <today>`, `schema_version: 1`) plus any per-type required keys per AGENTS.md §4. The pre-write hook will block on schema violations.
5. **Fund-context safety.** If a proposal touches a fund context (cng / tng / roundtree), set `context:` and verify the body doesn't slug-mention an opposite-context deal. If it does, split into two proposals.
6. **Quantity discipline.** A single session should produce at most ~5 proposals. If you have more candidates than that, rank by load-bearing-ness and present the top 5 in inbox files + the rest as a summary list ("also considered but not proposed: ...").

## Output

Print a single summary block:

```
synthesis from this session
===========================

decisions proposed (2):
  00-inbox/2026-05-22-decision-phase-1-observational-foundation.md
  00-inbox/2026-05-22-decision-google-calendar-source-of-truth.md

lessons proposed (1):
  00-inbox/2026-05-22-lesson-outlook-google-replication.md

entity stubs proposed (0):
  (none)

touches recommended:
  /touch Ross Cowan — Phase 1 review call
  /touch [[Pauline Nakios]] — LP fall preview discussion

also considered but not proposed:
  - Brief mention of Sokol Company LLC (insufficient new content to update stub)
  - Reference to Phase ε.7 closeout (already documented in commit message)
```

End with a one-line nudge: `review the inbox proposals → mv to 02-wiki/ to accept, rm to reject.`

## Hard rules

- NEVER write directly to `02-wiki/` from this command — always stage in `00-inbox/` first.
- NEVER write `source: human` — you're Claude-interactive.
- NEVER touch `04-archive/`.
- If a proposal would cross fund contexts, split it.
- If you're unsure whether something rises to "proposable," err toward NOT proposing — false positives clutter the inbox more than missing real entries.
- All proposed files carry `schema_version: 1`.
- The pre-write hook will block on schema violations — fix and retry, don't bypass.

## Calibration

A good `/synthesize` run produces 1-3 high-signal proposals from a substantive working session. Zero proposals is a fine outcome for a short or low-content session ("synthesis: nothing rises to a vault write today"). Five+ proposals is a red flag — re-read with stricter filtering.
