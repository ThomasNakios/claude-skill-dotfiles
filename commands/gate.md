---
description: Run the project's quality gate (build, types, lint, design). Blocks on failure.
---

# /gate

## Help

Run the project's quality gate. Blocks on failure — intended as a merge precondition.

USAGE
  /gate [--quick] [--dry-run] [--help]

OPTIONS
  --quick     Run only the quick-subset of commands (from config).
  --dry-run   Show which commands would run; do not execute them.
  --help, -h  Show this help and stop.

EXAMPLES
  /gate              # Full quality gate
  /gate --quick      # Fast subset (lint + types in most projects)
  /gate --dry-run    # Preview without running

EXIT CODES
  0  All required commands passed
  1  One or more required commands failed

FAMILY
  /hygiene   Project audit (informs; does not block)
  /closeout  Session closure (composes gate + hygiene)
  /depart    Workstation departure
  /arrive    Workstation arrival
  /resume    Session start

## Argument parsing

**FIRST, read the user's arguments:**

1. If args contain `--help`, `-h`, or `help`: render the **Help** section above and STOP. Do not execute further sections.
2. If args contain `--dry-run`: set `DRY_RUN=true`.
3. If args contain `--quick`: set `MODE=quick`. Otherwise `MODE=full`.
4. Unknown flags: print "unknown flag: <flag>" and STOP.

## Execution

### Load config

1. Look for `.claude/claude.yaml` in the current working directory.
2. If missing: enter **generic mode**. Use auto-discovery:
   - If `package.json` exists: detect `build`, `lint`, `test` scripts. Add them.
   - If `tsconfig.json` exists: add `npx tsc --noEmit` as `types`.
   - In generic mode, `quick_subset` defaults to `[lint, types]` (if available).
3. If present: parse YAML. If malformed, report line number and STOP.
4. Validate against `~/.claude/docs/claude-yaml-schema.md`. Hard-fail on schema violations.
5. Read `gate` section. If absent: STOP with "config has no gate block".

### Resolve command list

- If `MODE=quick`: filter `gate.commands` to those whose `name` is in `gate.quick_subset`. If `quick_subset` is empty or missing, default to all `required: true` commands.
- Else: use all `gate.commands`.

### Execute

For each command in order (parallel if `gate.parallel: true`, sequential otherwise):

1. Print: `▶ <name>: <cmd>`
2. If `DRY_RUN`: print "(dry-run, skipping)" and move on.
3. Else: shell-execute the `cmd`. Capture exit code.
4. If exit code != 0 AND `required: true`: mark this command FAILED.
5. If `gate.fail_fast: true` and any command FAILED: stop executing further commands.

### Summary output

Print:
```
gate summary:
  ✓ build       (1.2s)
  ✓ lint        (0.8s)
  ✗ types       (2.1s)  exit 1
  - design      skipped (--quick)
```

Exit non-zero if any required command failed. Print failure hint: `See output above. To re-run only the quality gate: /gate`
