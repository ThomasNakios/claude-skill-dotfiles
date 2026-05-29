---
description: Pre-create meeting stubs from Google Calendar for the next N days (primary calendar only, fund-token safety)
argument-hint: [days-ahead, default 7]
---

# /meeting-stubs — pre-create meeting notes from Google Calendar

You are pre-creating `01-raw/<domain>/meetings/<YYYY-MM-DD>-<slug>.md` stubs from the user's **Google Calendar primary calendar only** for upcoming meetings. This is Phase 3D observational tooling per the Phase 1/2/3 build plan.

## Critical constraints

These are non-negotiable per the user's explicit instructions:

1. **Primary calendar only.** Do NOT pull events from shared / subscribed / secondary calendars. Use `calendarId: "primary"` exclusively. If the MCP returns events from other calendars (it shouldn't if you scope correctly), filter them out by checking the `organizer.self == true` field or that the calendar id matches the primary calendar id from `list_calendars` where `primary: true`.
2. **Google as sole source.** The user's Outlook calendar replicates to/from Google. NEVER query Outlook. If you encounter an Outlook MCP, do not use it for this command. Querying both would create duplicate stubs.
3. **Fund-context safety.** Apply the §6.3 pre-pass: if attendees indicate a fund (cng / tng / roundtree), tag the meeting with that context. If attendees mix fund contexts (e.g., CNG and TNG people on the same invite), the meeting goes to `00-inbox/_review/` with a `PROPOSED quarantine` note for human triage — do NOT auto-place into a fund's meetings dir.

## Input

User argument: `$ARGUMENTS` — number of days to look ahead (default 7 if empty or unparseable).

## What to do

1. **Use the Google Calendar MCP** (tools named `mcp__2f5acb9e-5fa0-487a-a2b8-1b58dd47bbe7__*`):
   - First call `list_calendars` and identify the primary calendar (`primary: true`). Note its id.
   - Call `list_events` scoped to that calendar id only. Time range: now → now + N days.
2. **Filter the event list:**
   - Skip events where the user is not on the attendee list AND not the organizer (random calendar noise)
   - Skip declined events (`responseStatus: "declined"` for the user)
   - Skip all-day events (those are usually OOO / holidays, not meetings)
   - Skip events with no other attendees (solo focus blocks)
3. **For each remaining event**, classify by attendee domain & known entities:
   - Build a set of attendee email domains and names
   - Cross-reference against `02-wiki/people/` and `02-wiki/<domain>/firms/` — use Glob + Grep to find matches by email or name
   - **Context inference** by attendee match:
     - Any attendee tagged `context: cng` → `cng`
     - Any attendee tagged `context: tng` → `tng`
     - Any attendee tagged `context: roundtree` → `roundtree`
     - Any attendee from `fashion/` domain → `lp` or `fashion-ops`
     - Family member → `personal` or `family-office` depending on email-domain hint
     - Multiple fund-context matches → QUARANTINE (do not route)
4. **Create the stub** at the appropriate path:
   - Clean single-context: `~/vault/01-raw/<domain>/meetings/<YYYY-MM-DD>-<slug>.md`
   - Mixed-context (quarantine): `~/vault/00-inbox/_review/<YYYY-MM-DD>-meeting-<slug>.md`
   - Unknown context (no attendee matches): `~/vault/00-inbox/<YYYY-MM-DD>-meeting-<slug>.md` (for `/synthesize` or manual placement later)
5. **Stub content:**

   ```markdown
   ---
   type: meeting
   source: claude-scheduled:meeting-stubs
   created: <YYYY-MM-DD>
   schema_version: 1
   context: <inferred-or-omit>
   meeting_date: <YYYY-MM-DD>
   meeting_time: <HH:MM>
   attendees:
     - "[[Name1]]"  # or email if unmatched
     - "[[Name2]]"
   subject: "<event summary from calendar>"
   confidentiality: working  # default; user upgrades if needed
   ttl: 365d
   ---

   # <event summary>

   <meeting_date> <meeting_time> — <duration>

   ## Attendees

   - [[Name1]] (<email>)
   - [[Name2]] (<email>)

   ## Agenda

   <calendar description, verbatim, if present; otherwise "(none provided)">

   ## Notes

   _(to fill during/after meeting)_

   ## Outcomes

   _(decisions, follow-ups, next steps)_
   ```

6. **Idempotency check.** Before writing, Glob the target path. If the file already exists (you already ran `/meeting-stubs` earlier for this day), SKIP — don't clobber. Report skipped count.
7. **Report:**

   ```
   meeting-stubs for next <N> days (google primary calendar)
   =========================================================
   queried: <count> events on primary calendar
   filtered out: <count> (declined / solo / no-attendees / all-day)
   created: <count>
     01-raw/real-estate/cng/meetings/2026-05-23-ross-1730-ms-walkthrough.md (context: cng)
     01-raw/fashion/meetings/2026-05-24-pauline-fall-preview.md (context: lp)
   quarantined (mixed-context): <count>
     00-inbox/_review/2026-05-25-meeting-cross-deal-debrief.md
   no-context (unknown attendees): <count>
     00-inbox/2026-05-26-meeting-external-vendor.md
   skipped (already existed): <count>
   ```

## Hard rules

- **Primary calendar only.** Verify the calendar id every time. Never trust a cached calendar id from a previous run.
- **No Outlook query.** Period.
- **No deduping across calendars** — single source, so there's nothing to dedupe against. If you see duplicate events from the same primary calendar (rare), prefer the one with more attendees / a description.
- **Source enum.** Use `source: claude-scheduled:meeting-stubs` — this is a scheduled-style invocation even though it's user-triggered. Document if challenged; the source enum allows it (claude-scheduled:<job>).
- **Mixed-context quarantine is silent-safe.** Don't try to be clever and infer which fund "wins" — that's the cross-context bleed risk §6.3 was written to prevent.
- **schema_version: 1 on every file written.**
- **Pre-write hook will validate** — fix and retry on rejection.
- **Personal calendar entries** (family, medical, school) — DO write a stub but mark `context: personal` and `confidentiality: restricted`. Per §6.9 personal sensitivity discipline.
- **Cancelled events** (status: "cancelled") — skip.
- **Recurring events** — create only the next instance; do not bulk-create the whole series.

## Calibration

A typical run over 7 days produces maybe 5-15 stubs depending on the user's calendar density. If you're producing 30+ stubs, something is wrong — likely you're pulling from a shared calendar or the filter is too loose. STOP and ask the user before writing.
