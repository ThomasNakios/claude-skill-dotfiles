---
description: Record a touchpoint with a person/firm — updates last_contact and appends to <context>-touchpoints.md
argument-hint: <name or wikilink> [— note]
---

# /touch — record a touchpoint

You are recording a contact event for the user with one or more entities (people, firms, places) in the KnockersNoggin vault. This is a **Level 2 mechanization** of AGENTS.md §6.2 (auto-touch / last-contact tracking).

## Input

The user's arguments: `$ARGUMENTS`

Examples the user might type:
- `/touch Ross Cowan — call about CNG-1730-MS underwrite`
- `/touch [[Pauline Nakios]] — coffee, Lilla P fall preview discussion`
- `/touch Lilla P LLC, Pauline Nakios — review of Q3 numbers`

Multiple entities can be listed comma-separated before the em-dash. After the em-dash is the optional context note.

## What to do

1. **Parse arguments.** Extract entity names (strip `[[...]]` wrapping if present). Split on `,`. Everything after ` — ` (or ` -- `, or ` -- `) is the note. If no separator, no note.
2. **Locate each entity** under `~/vault/02-wiki/`:
   - People: `02-wiki/people/<Name>/<Name>.md`
   - Firms: `02-wiki/<domain>/firms/<slug>.md` or `02-wiki/family-office/estate/<slug>.md` etc.
   - Use Glob/Grep to find the matching file by name. If multiple matches, ask the user which one (use AskUserQuestion).
   - If no match, ask the user whether to create a stub or skip.
3. **Determine context** of each entity by reading the file's `context:` frontmatter. (Personal entities may have no `context:`.)
4. **Update each entity's `last_contact:`** field to today's date (`2026-05-22` or whatever `date +%Y-%m-%d` returns on this machine). If the field is missing, add it after `created:`. Use Edit, not Write — preserve the rest of the file.
5. **Append a touchpoint line** to the matching log file:
   - For business contexts (`cng`, `tng`, `roundtree`, `lp`, `fashion-ops`): `~/vault/05-system/operations/<context>/<YYYY-MM>.md` (the existing convention — same place inbox-processor writes proposals)
   - For `family-office` / `personal`: `~/vault/05-system/operations/<context>/<YYYY-MM>.md`
   - For multi-domain entries (entities span domains): append once to **each** relevant context log
   - Line format: `- <YYYY-MM-DD> touch: [[Entity Name]] — <note or "(no note)">`
   - If the monthly log file doesn't exist, create it with `type: log`, `source: claude-interactive`, `created: <YYYY-MM-01>`, `schema_version: 1`, `context: <context>`, `ttl: 365d`.
6. **Confirm to the user** what you did: list each entity touched + the log file appended to. Use plain text, no markdown headers.

## Hard rules

- Never write `source: human` — this is a `claude-interactive` action (you are Claude updating files on the user's behalf).
- Never cross fund contexts in a single log entry — if entities span `cng` and `tng`, write to BOTH `cng/<YYYY-MM>.md` AND `tng/<YYYY-MM>.md`, never merge.
- Never touch `04-archive/`.
- Never modify any field besides `last_contact:` on the entity file.
- If you can't find an entity, ask — don't guess from partial matches that might be wrong.
- All new files carry `schema_version: 1`.
- The pre-write hook will validate frontmatter on any Write you do — if it rejects, fix the frontmatter, don't bypass.

## Output

Report concisely:

```
touched:
  [[Ross Cowan]] (context: cng) — last_contact: 2026-05-22
  [[Pauline Nakios]] (context: personal) — last_contact: 2026-05-22
appended:
  05-system/operations/cng/2026-05.md
  05-system/operations/personal/2026-05.md
```

No commit — Obsidian Git's 5-min auto-commit (or the next manual commit) will sweep it up. If Obsidian isn't running on this host, mention that the user may want to `cd ~/vault && git add -A && git commit -m "touch: <names>"`.
