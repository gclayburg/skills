## Relative build numbers and fix `-n` in full output mode

- **Date:** `2026-02-21T14:43:52-0700`
- **References:** `specs/todo/allow-negative-job-number.md`
- **Supersedes:** (none)
- **State:** `DRAFT`

## Background

Currently `buildgit status <build#>` only accepts positive integers (e.g. `buildgit status 31`). Users cannot specify relative build references like "the previous build" or "two builds ago". Additionally, the `-n <count>` flag only works in `--line` mode — in full output mode, `-n` is silently ignored and only the latest build is shown.

### Bug: `-n` ignored in full output mode

`buildgit status -n 2` on a TTY shows only the latest build instead of the last 2 builds. The `_jenkins_status_check()` code path does not accept a count parameter, so the `STATUS_LINE_COUNT` value is discarded when `use_line_mode` is false.

### Root cause

In `cmd_status()`, when `use_line_mode` is false, the code calls `_jenkins_status_check "$_VALIDATED_JOB_NAME" "$STATUS_JSON_MODE" "$STATUS_BUILD_NUMBER"` which has no count parameter. The `line_count` variable is only used in the `_status_line_check` path.

## Specification

### 1. Relative build number syntax

Accept `0` and negative integers as the build number positional argument:

| Syntax | Meaning | Equivalent |
|--------|---------|------------|
| `buildgit status 31` | Specific build #31 | (unchanged) |
| `buildgit status 0` | Current/latest build | `buildgit status` (no arg) |
| `buildgit status -1` | One build before the latest | `buildgit status -n 1 --line` shows same build |
| `buildgit status -2` | Two builds before the latest | — |
| `buildgit status -N` | N builds before the latest | — |

**Resolution of `0`:** Show the in-progress build if one exists, otherwise show the last completed build (same as `buildgit status` with no argument).

**Resolution of negative numbers:** Resolve `get_last_build_number()` and subtract the absolute value. If `last_build == 199` then `-2` resolves to build `#197`. If the resolved number is less than 1, show an error.

### 2. Negative-number shorthand for `-n`

Accept `-N` (where N is 1–99) as a shorthand for `-n N` when no build number has been set:

| Shorthand | Equivalent |
|-----------|------------|
| `buildgit status -3 --line` | `buildgit status -n 3 --line` |
| `buildgit status -5` | `buildgit status -n 5` |

**Disambiguation rule:** A bare negative number like `-3` acts as a `-n` shorthand (show last 3 builds). To reference a specific relative build (3 builds ago), the user combines it differently — this is the natural reading since `-3` as "show 3 builds" is more common than "show the build from 3 ago".

Wait — this creates ambiguity. Let me reconsider.

Looking at the raw file more carefully:
- `buildgit status -3 --line` should equal `buildgit status -n 3 --line`
- `buildgit status 0` = current build
- `buildgit status -1` = 1 build before current

These two definitions conflict: `-3` can't mean both "3 builds ago" (relative) and "show last 3" (`-n 3`).

**Resolution per the raw file:** `-N` is shorthand for `-n N` (show last N builds). This is the primary use case. The `0` and negative relative build concepts apply only to the positional build number argument when it stands alone or is clearly a build reference.

Revised rule:
- **`-N` as a status option** (e.g. `-3`) → treated as shorthand for `-n N` (show last N builds)
- **`0` as positional argument** → current/latest build (equivalent to no argument)

This means there is **no** "negative relative build" syntax — `-1` means "show last 1 build" (same as `-n 1`), not "one build before latest". This matches the raw file's stated equivalences.

### Revised specification

#### 2a. Accept `-N` as `-n N` shorthand in status option parsing

In `_parse_status_options()`, recognize `-N` (where N is 1–99) as equivalent to `-n N`:

- `-1` → `-n 1`
- `-3` → `-n 3`
- `-99` → `-n 99`

Validation: reject `-0`, `-100+`, and non-numeric values.

Must not conflict with other short flags (currently `-f`, `-n`, `-h`, `-a`). Since these are all single-letter and `-N` is always a digit, there is no conflict.

#### 2b. Accept `0` as build number positional argument

In `_parse_status_options()`, accept `0` as a valid build number. Treat `0` identically to omitting the build number (show latest/current build). Internally, convert `0` to empty string so existing code paths handle it naturally.

### 3. Fix `-n` in full output mode

When `-n` is specified without `--line` on a TTY, show full output for each of the N builds instead of only the latest.

#### Implementation

In `cmd_status()`, when `use_line_mode` is false and `STATUS_N_SET` is true:
- Get the starting build number (from `STATUS_BUILD_NUMBER` or `get_last_build_number()`)
- Collect N build numbers working backwards (same logic as `_status_line_check`)
- Loop through them oldest-first, calling `_jenkins_status_check()` for each
- Separate multiple builds with a visual divider (e.g. a blank line or `---`)
- Exit code based on the last (newest) build

This applies to all modes where `-n` is relevant:
- `buildgit status -n 3` → 3 full-output status reports
- `buildgit status -3` → same (via shorthand)
- `buildgit status -n 3 --line` → unchanged (already works)
- `buildgit status -n 3 --json` → array of N JSON objects (or N newline-separated objects)

#### JSON with `-n`

When `-n` is combined with `--json`, output one JSON object per build, newline-separated (JSONL format). This keeps each object parseable with standard tools like `jq`.

### 4. Interaction with other flags

| Combination | Behavior |
|-------------|----------|
| `-3 --line` | Show last 3 builds in line mode |
| `-3` (TTY) | Show last 3 builds in full mode |
| `-3` (non-TTY) | Show last 3 builds in line mode (existing TTY-aware default) |
| `-3 --json` | Show last 3 builds in JSONL |
| `-3 -f` | Error: `-n` and `-f` are incompatible (existing validation) |
| `0` | Same as no build number |
| `0 --line` | Same as `--line` with no build number |
| `-3 --all` | Show last 3 builds in full mode (forced) |

### 5. Existing validation updates

- Build number regex: change from `^[1-9][0-9]*$` to also accept `0`
- Add new case for `-N` pattern in option parsing (before the generic unknown-option error)
- `-n` combined with a specific build number (e.g. `buildgit status 31 -n 3`): existing behavior already works in line mode; extend to full mode

## Test Strategy

### New tests

1. **`-3` shorthand sets STATUS_LINE_COUNT** — verify `-3` produces same parsed state as `-n 3`
2. **`-1` shorthand works** — single build
3. **`-99` shorthand works** — max two-digit count
4. **`-0` rejected** — error message
5. **`-100` not treated as shorthand** — falls through to unknown option error
6. **`0` as build number** — accepted, treated as latest build
7. **`0` with `--line`** — works, shows latest build in line mode
8. **Full mode `-n 2`** — shows 2 complete build reports (bug fix validation)
9. **Full mode `-n 3`** — shows 3 complete build reports
10. **Full mode `-n` exit code** — based on newest (last-printed) build
11. **Full mode `-n` ordering** — oldest first, newest last
12. **`-3 --json`** — outputs 3 JSONL objects
13. **`-3 -f` rejected** — error (existing incompatibility preserved)
14. **`-3 --line`** — equivalent to `-n 3 --line`
15. **`-N` with existing build number rejected** — e.g. `buildgit status 31 -3` errors

### Existing tests to verify

- All current `-n` + `--line` tests still pass
- All current build number positional arg tests still pass
- All current `-f` + `-n` incompatibility tests still pass

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
