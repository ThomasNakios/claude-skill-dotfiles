---
description: Audit project state (stale files, naming, governance). Informs; does not block.
---

# /hygiene

## Help

Audit project-state hygiene. Reports findings but does not block — meant to surface drift you should address.

USAGE
  /hygiene [--dry-run] [--help]

OPTIONS
  --dry-run   List patterns that would be scanned; do not execute the scans.
  --help, -h  Show this help and stop.

EXAMPLES
  /hygiene             # Full audit
  /hygiene --dry-run   # Preview patterns

EXIT CODES
  0  Audit completed (may include warnings)
  1  Hygiene config malformed (cannot run)

FAMILY
  /gate      Quality gate (blocks on failure)
  /closeout  Session closure (composes gate + hygiene)
  /depart    Workstation departure
  /arrive    Workstation arrival
  /resume    Session start

## Argument parsing

**FIRST, read the user's arguments:**

1. If args contain `--help`, `-h`, or `help`: render the **Help** section above and STOP.
2. If args contain `--dry-run`: set `DRY_RUN=true`.
3. Unknown flags: print "unknown flag: <flag>" and STOP.

## Execution

### Load config

1. Look for `.claude/claude.yaml`. If missing, enter generic mode with standard patterns:
   - `console.log` in `**/*.ts`, `**/*.tsx`
   - `TODO|FIXME` in `**/*.ts`, `**/*.tsx`
   - `.DS_Store` files
   - Large files (>1MB) outside `node_modules/`, `.next/`, `.git/`
2. If present: read `hygiene` section.

### Execute patterns

For each pattern in `hygiene.patterns`:

1. Print: `▶ <name> (action: <action>)`
2. If `DRY_RUN`: print pattern shape, skip execution.
3. Else execute:
   - `kind: files` — find files matching `glob`, report count.
   - `kind: grep` — grep for `pattern` in `include` paths, excluding `exclude`. Report match count + first 5 file:line hits.
4. Apply `action`:
   - `warn` — emit a warning, count toward total
   - `report` — emit info, do not increment warnings
   - `suggest-delete` — emit suggestion ("run `rm <path>`"), count toward warnings

### Check `gitignore_required`

For each pattern in `hygiene.gitignore_required`:
- If not present in `.gitignore`: warn "missing from .gitignore: <pattern>"

### Check `file_structure`

- For each entry in `naming_rules`: glob files, check casing of basename matches `case`. Report violations.
- For each entry in `forbidden_filenames`: find files with that exact basename. Report.
- For each entry in `location_rules`: this requires project knowledge; report as "manual review" with the rule.

### Check `governance`

- Glob `<docs_dir>/**/*.md`.
- For each: check first 20 lines contain `<docs_must_have_header>`. If not, warn.
- For each: count lines. If > `docs_max_lines`, warn.

### Summary output

```
hygiene summary:
  patterns: 7 (5 clean, 2 with warnings)
  gitignore: 1 missing
  file_structure: 3 violations
  governance: 2 docs missing "Last Updated" header

total warnings: 8
```

Exit 0 unless config malformed. Hygiene never blocks via exit code.
