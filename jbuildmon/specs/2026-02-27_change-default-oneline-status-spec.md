## Change Default One-Line Status Output Format

- **Date:** `2026-02-27T00:00:00-0700`
- **References:** `specs/done-reports/change-default-oneline-status.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

The current default `--line` format (defined in `2026-02-23_status-line-template-spec.md`) is:

```
%s Job %j #%n Tests=%t Took %d on %D (%r)
```

Which produces output like:

```
SUCCESS     Job phandlemono-IT #50 Tests=19/0/0 Took 5m 29s on 2026-02-22 (4 days ago)
```

The job name (`%j`) is already known from context (you're in the repo for that job), making it redundant noise. The short date (`%D`) loses the time of day and timezone. The commit SHA (`%c`) is more useful than the job name for identifying exactly what was built.

## Specification

### Change the default format string

Change `_DEFAULT_LINE_FORMAT` from:

```
_DEFAULT_LINE_FORMAT="%s Job %j #%n Tests=%t Took %d on %D (%r)"
```

To:

```
_DEFAULT_LINE_FORMAT="%s #%n id=%c Tests=%t Took %d on %I (%r)"
```

The changes are:
- Remove `Job %j` (job name) — redundant when you're working in the repo
- Add `id=%c` — short 7-char commit SHA immediately after build number
- Replace `%D` (short date `2026-02-22`) with `%I` (ISO 8601 with timezone `2026-02-22T21:27:23-0700`)

### New default output example

```
SUCCESS     #50 id=011d32c Tests=19/0/0 Took 5m 29s on 2026-02-22T21:27:23-0700 (4 days ago)
```

### Files to change

| File | Change |
|------|--------|
| `skill/buildgit/scripts/buildgit` | Update `_DEFAULT_LINE_FORMAT` variable (already done in working tree). Remove debug comment lines added during exploration. Update `--help` text to show new default format string. |
| `test/buildgit_status.bats` | Update all test assertions that match against the old default format (see below). |
| `test/buildgit_status_follow.bats` | Update assertions that match `Job <name> #N` in default line mode output. |
| `skill/buildgit/references/reference.md` | Update the documented default format string. |
| `skill/buildgit/SKILL.md` | Update any default format string references. |

### Help text update

The `--format` documentation in `show_usage()` currently shows:

```
  Default: "%s Job %j #%n Tests=%t Took %d on %D (%r)"
```

Update to:

```
  Default: "%s #%n id=%c Tests=%t Took %d on %I (%r)"
```

### Cleanup: debug comments in script

Remove the two `#SUCCESS ...` comment lines near the top of the script that were added during exploratory testing (they contain example output lines and are not appropriate in committed code).

## Test Strategy

### Unit tests to update

These tests assert old default format output and must be updated to match the new format. The key changes are:
- Remove `Job test-repo` from expected strings
- Add `id=<sha>` field (use a partial match or regex that accepts any 7-char hex)
- Update date regex from `[0-9]{4}-[0-9]{2}-[0-9]{2}` to ISO 8601 pattern `[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[-+][0-9]{4}`

Files and patterns to update:

**`test/buildgit_status.bats`:**
- Tests asserting `"Job test-repo #42"` in partial output — remove `Job test-repo`; add `id=` SHA pattern
- Tests asserting regex `Job test-repo #42 Tests=120/0/0 Took 2m 0s on [0-9]{4}-[0-9]{2}-[0-9]{2} \(.*\)` — update to new format with ISO 8601 date pattern
- Tests asserting `Tests=?/?/? Took` alongside `Job test-repo` — remove `Job test-repo`

**`test/buildgit_status_follow.bats`:**
- Tests asserting `"Job test-repo #42"` in default line output — remove `Job`; add `id=` pattern

### New unit test

Add a test that verifies the default format output matches the new pattern:

```
status_line_default_format_no_job_name:
  Run status --line with no explicit --format
  Assert output does NOT contain "Job"
  Assert output matches: ^<STATUS> #<N> id=<sha7> Tests=
```

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
