# `.claude/claude.yaml` Schema Reference (v1)

> Authoritative shape for project configs consumed by the closeout family
> (closeout, gate, hygiene, depart, arrive). When validating, the agent
> reads this file and reports specific deviations.

## Top-level required keys

| Key | Type | Required | Notes |
|---|---|---|---|
| `schema_version` | integer | yes | Must equal 1 |
| `project` | map | yes | See `project` block below |
| `gate` | map | yes | Quality-gate definition |
| `hygiene` | map | yes | Project audit (may be empty `{}`) |
| `security` | map | yes | Non-negotiables (may be empty list) |
| `closeout` | map | yes | Session.md + NEXT.md behavior |
| `depart` | map | no | Workstation departure config |
| `arrive` | map | no | Workstation arrival config |

## `project` block

```yaml
project:
  name: <string>                    # required
  type: <string>                    # optional; framework hint
  claude_md_path: <relative-path>   # optional; default ./CLAUDE.md
  claude_md_hash: <sha256>          # optional; populated by bootstrap
  bootstrapped_at: <ISO-8601>       # optional; populated by bootstrap
  bootstrapped_by: <skill-version>  # optional; populated by bootstrap
```

## `gate` block

```yaml
gate:
  commands:                         # required; list of named commands
    - name: <string>                # required
      cmd: <shell-string>           # required
      required: <bool>              # default true
  quick_subset: [<name>, ...]       # optional; names from commands[] for --quick
  parallel: <bool>                  # default true
  fail_fast: <bool>                 # default true
```

## `hygiene` block

```yaml
hygiene:
  patterns:                         # list; may be empty
    - name: <string>
      kind: files | grep            # which check kind
      glob: <glob>                  # for kind=files
      pattern: <regex>              # for kind=grep
      include: [<glob>, ...]        # for kind=grep
      exclude: [<glob>, ...]        # for kind=grep
      action: warn | report | suggest-delete
  gitignore_required: [<pattern>, ...]   # patterns that must be in .gitignore
  file_structure:
    forbidden_filenames: [<name>, ...]
    naming_rules:
      - { pattern: <glob>, case: PascalCase | kebab-case | snake_case }
    location_rules:
      - { kind: <string>, must_live_in: <path> }
  governance:
    docs_must_have_header: <string>
    docs_max_lines: <int>
    docs_dir: <path>
```

## `security` block

```yaml
security:
  rules:                            # list; hard-fail on violations
    - name: <string>
      description: <string>
      check:
        kind: grep-required | grep-required-pair | grep-forbidden | shell
        # kind=grep-required:
        in_files: <glob>
        required_pattern: <regex>
        # kind=grep-required-pair:
        anchor: <regex>
        required_within_lines: <int>
        required_pattern: <regex>
        include: [<glob>, ...]
        exclude: [<glob>, ...]
        # kind=grep-forbidden:
        pattern: <regex>
        include: [<glob>, ...]
        # kind=shell: project-provided audit script must exit 0
        cmd: <shell-string>           # e.g. "npm run audit:tenant-isolation"
        timeout_seconds: <int>        # optional; default 60
      source: <path-or-url>         # where this rule is defined
```

## `closeout` block

```yaml
closeout:
  session_md:
    path: <relative-path>           # default .claude/session.md
    template: <relative-path>       # optional override
    stale_threshold_days: <int>     # default 7
    draft_then_confirm: <bool>      # default true
  next_md:
    path: <relative-path>           # default NEXT.md; null to disable
    prompt_on_completion: <bool>    # default true
    auto_update: <bool>             # default false
  daily_report:
    enabled: <bool>                 # default true
    path_template: <string>         # default docs/testing/daily/{YYYY-MM-DD}.md
```

## `depart` block (optional)

```yaml
depart:
  remote: <string>                  # default origin
  protected_branches: [<branch>, ...]
  require_session_md_fresh: <bool>  # default true
  session_md_freshness_hours: <int> # default 4
```

## `arrive` block (optional)

```yaml
arrive:
  pull_strategy: rebase | merge     # default rebase
  post_pull_hooks:
    - { if_changed: <glob>, run: <shell-string> }
  suggest_resume: <bool>            # default true
```

## Validation behavior (agent reading this doc)

| Condition | Action |
|---|---|
| Missing required key | Report which key, exit with hard-fail |
| `schema_version != 1` | Report mismatch; suggest `/closeout --init --migrate` |
| Unknown top-level key | Warn but proceed (forward-compatible) |
| Malformed YAML | Hard-fail with line number from parser error |
| Type mismatch on a field | Hard-fail with field path and expected type |
| `claude_md_hash` differs from on-disk hash | Warn: "CLAUDE.md changed since bootstrap" |
