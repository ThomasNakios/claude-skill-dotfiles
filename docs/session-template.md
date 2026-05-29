---
schema_version: 1
session_id: {{SESSION_ID}}
written_at: {{ISO_TIMESTAMP}}
written_by: closeout {{SKILL_VERSION}}
project: {{PROJECT_NAME}}
branch: {{GIT_BRANCH}}
last_commit: {{GIT_COMMIT_SHORT}}
status: {{STATUS}}              # clean | warnings | blockers
checks:
  gate: {{GATE_STATUS}}     # pass | fail | skipped
  hygiene: {{HYGIENE_STATUS}}   # pass | warn | fail | skipped
  security: {{SECURITY_STATUS}} # pass | fail | skipped
counts:
  files_changed: {{FILES_CHANGED}}
  hygiene_warnings: {{HYGIENE_WARNINGS}}
  followups: {{FOLLOWUPS_COUNT}}
---

## Intent
{{INTENT}}

## Done
{{DONE}}

## In-flight
{{IN_FLIGHT}}

## Pickup
{{PICKUP}}

## Blockers
{{BLOCKERS}}

## Followups
{{FOLLOWUPS}}

## Decisions
{{DECISIONS}}
