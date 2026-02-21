## Relative build numbers and fix `-n` in full output mode

- **Date:** `2026-02-21T14:43:52-0700`
- **References:** `specs/done-reports/allow-negative-job-number.md`, `specs/done-reports/negative-numbers-with-n-enhanced.md`
- **Supersedes:** (none)
- **State:** `IMPLEMENTED`

## Background

Currently `buildgit status <build#>` only accepts positive integers (e.g. `buildgit status 31`). Users cannot specify relative build references like "the previous build" or "two builds ago". Additionally, the `-n <count>` flag only works in `--line` mode — in full output mode, `-n` is silently ignored and only the latest build is shown.

### Bug: `-n` ignored in full output mode

`buildgit status -n 2` on a TTY shows only the latest build instead of the last 2 builds. The `_jenkins_status_check()` code path does not accept a count parameter, so the `STATUS_LINE_COUNT` value is discarded when `use_line_mode` is false.

### Root cause

In `cmd_status()`, when `use_line_mode` is false, the code calls `_jenkins_status_check "$_VALIDATED_JOB_NAME" "$STATUS_JSON_MODE" "$STATUS_BUILD_NUMBER"` which has no count parameter. The `line_count` variable is only used in the `_status_line_check` path.

## Specification

### Key principle: `status <build-ref>` always shows exactly one build

Any form of `buildgit status <build-ref>` — whether positive, zero, or negative — always shows the status of **exactly one build**. This is distinct from `-n <count>`, which shows multiple builds.

### 1. Relative build number syntax

Accept `0` and negative integers as the build number positional argument. These are **relative references** that resolve to a single absolute build number:

| Syntax | Meaning | Example (latest=#200) |
|--------|---------|----------------------|
| `buildgit status 31` | Absolute build #31 | Shows #31 |
| `buildgit status 0` | Current/latest build | Shows #200 |
| `buildgit status -1` | One build before the latest | Shows #199 |
| `buildgit status -2` | Two builds before the latest | Shows #198 |
| `buildgit status -N` | N builds before the latest | Shows #(200-N) |

**Resolution of `0`:** Show the in-progress build if one exists, otherwise show the last completed build (same as `buildgit status` with no argument). Internally, treat `0` as equivalent to omitting the build number.

**Resolution of negative numbers:** Call `get_last_build_number()` and subtract the absolute value. If `last_build == 200` then `-2` resolves to build `#198`. If the resolved number is less than 1, show an error.

**Single build only:** `-N` as a build reference always shows exactly one build. It is **not** a shorthand for `-n N`. These are completely different:
- `buildgit status -2` → shows one build: the build from 2 ago (#198)
- `buildgit status -n 2` → shows two builds: the last 2 builds (#199, #200)

### 2. `-N` option parsing

In `_parse_status_options()`, recognize `-N` (where N is a positive integer) as a relative build reference:

- `-1` → relative build offset 1 (one before latest)
- `-2` → relative build offset 2 (two before latest)
- `-99` → relative build offset 99

This is parsed as a build number, not as `-n`. Internally, the negative value is stored and resolved to an absolute build number before the Jenkins API call.

**Validation:**
- `-0` is accepted and treated the same as `0` (latest build)
- Must not conflict with existing short flags (`-f`, `-n`, `-h`, `-a`). Since those are all single letters and `-N` starts with a digit, there is no conflict.
- If a build number is already set (e.g. `buildgit status 31 -2`), show an error: build number already specified.

### 3. Mutual exclusivity: build reference vs `-n`

A build reference (positive, zero, or negative) and `-n <count>` are **mutually exclusive**. If both are specified, show an error:

```
$ buildgit status -2 -n 3 --line
Error: Cannot combine a build number with -n
```

This applies to all combinations:
- `buildgit status 31 -n 3` → error
- `buildgit status -2 -n 3` → error
- `buildgit status 0 -n 5` → error

### 4. Fix `-n` in full output mode

When `-n` is specified without `--line` on a TTY, show full output for each of the N builds instead of only the latest.

#### Implementation

In `cmd_status()`, when `use_line_mode` is false and `STATUS_N_SET` is true:
- Get the starting build number via `get_last_build_number()`
- Collect N build numbers working backwards (same logic as `_status_line_check`)
- Loop through them oldest-first, calling `_jenkins_status_check()` for each
- Separate multiple builds with a blank line
- Exit code based on the last (newest) build

This applies to all output modes:
- `buildgit status -n 3` → 3 full-output status reports (oldest first)
- `buildgit status -n 3 --line` → unchanged (already works)
- `buildgit status -n 3 --json` → N newline-separated JSON objects (JSONL format)

### 5. Interaction with other flags

| Combination | Behavior |
|-------------|----------|
| `-2` | Show one build: 2 builds ago, full output |
| `-2 --line` | Show one build: 2 builds ago, line output |
| `-2 --json` | Show one build: 2 builds ago, JSON output |
| `-2 -f` | Error: cannot combine build number with `-f` (existing rule) |
| `-2 -n 3` | Error: cannot combine build number with `-n` |
| `-n 3` (TTY) | Show last 3 builds in full mode (bug fix) |
| `-n 3 --line` | Show last 3 builds in line mode (unchanged) |
| `-n 3 --json` | Show last 3 builds in JSONL |
| `-n 3 -f` | Error: `-n` and `-f` are incompatible (existing rule) |
| `0` | Same as no build number |
| `0 --line` | Same as `--line` with no build number |
| `-n 3 --all` | Show last 3 builds in full mode (forced) |

### 6. Help text updates

Update `buildgit --help` to document relative build numbers:

```
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      build# can be absolute (31) or relative (0=latest, -1=previous, -2=two ago)
```

## Test Strategy

### New tests

1. **`-1` shows second-to-last build** — if latest is #200, shows #199 only
2. **`-2` shows third-to-last build** — if latest is #200, shows #198 only
3. **`0` shows latest build** — same as no argument
4. **`-0` shows latest build** — same as `0`
5. **`-1 --line` shows one line** — the second-to-last build
6. **`-2 --json` shows one JSON object** — the build from 2 ago
7. **Relative build resolves to < 1** — error message (e.g. `-999` when only 5 builds exist)
8. **`-2 -n 3` rejected** — error: cannot combine build number with `-n`
9. **`31 -n 3` rejected** — error: cannot combine build number with `-n`
10. **`0 -n 3` rejected** — error: cannot combine build number with `-n`
11. **Full mode `-n 2` shows 2 builds** — bug fix validation: two complete build reports
12. **Full mode `-n 3` shows 3 builds** — three complete build reports
13. **Full mode `-n` exit code** — based on newest (last-printed) build
14. **Full mode `-n` ordering** — oldest first, newest last
15. **`-n 3 --json` outputs 3 JSONL objects** — one per line
16. **`-N -f` rejected** — error: cannot combine build number with `-f` (existing rule)
17. **`-N` with existing build number rejected** — e.g. `buildgit status 31 -2` errors

### Existing tests to verify

- All current `-n` + `--line` tests still pass
- All current build number positional arg tests still pass
- All current `-f` incompatibility tests still pass

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
