## Count IMPLEMENTED specs

- **Date:** `2026-03-15T14:31:09-06:00`
- **References:** `specs/todo/specreport.md`
- **Supersedes:** none
- **Plan:** `none`
- **Chunked:** `false`
- **State:** `DRAFT`

## Problem Statement

There is no quick way to see how many specs have reached the IMPLEMENTED state. Counting manually across 70+ spec files is tedious.

## Specification

### 1. Script location and name

Create `jbuildmon/specs/specreport.sh` — a standalone shell script.

### 2. Behavior

The script scans all `*-spec.md` files in the `jbuildmon/specs/` directory for a `State:` header matching `IMPLEMENTED` and prints a single line with the count.

**Output format:**
```
IMPLEMENTED: 42
```

- The number is the count of spec files whose `State:` field is `IMPLEMENTED`.
- No other output. Exit code 0.

### 3. Implementation details

- Use `grep` to find the `State:` header line in each `*-spec.md` file and match `IMPLEMENTED`.
- The script must be compatible with macOS bash 3.2 (no bash 4+ features).
- The script must work from any working directory — resolve the specs directory relative to the script's own location.
- No external dependencies beyond standard POSIX tools (`grep`, `wc`, `dirname`, `basename`).

### 4. Affected functions

None — this is a new standalone script.

## Test Strategy

### New tests in existing test files

No bats tests needed — this is a trivial standalone script outside the buildgit tool.

## Manual Test Plan

See [`2026-03-15_specreport-test-plan.md`](2026-03-15_specreport-test-plan.md) for the CLI-driven test plan.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
