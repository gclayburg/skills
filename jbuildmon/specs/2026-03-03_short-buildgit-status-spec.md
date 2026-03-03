## Change `buildgit status` default to one-line output

- **Date:** `2026-03-03T09:57:25-0700`
- **References:** `specs/todo/short-buildgit-status.md`
- **Supersedes:** `2026-02-15_quick-status-line-spec.md` (partially — removes TTY/non-TTY distinction for default output)
- **State:** `DRAFT`

## Background

Currently `buildgit status` has different default behavior depending on whether stdout is a TTY:

- **TTY (interactive terminal):** Full verbose output (banner, build info, stages, test results, console URL, prior-jobs block)
- **Non-TTY (piped/redirected):** One-line compact output with prior-jobs block

This creates an inconsistency — the same command produces dramatically different output depending on context. The full output is verbose and slow (requires multiple API calls for stages, tests, console logs).

The proposal is to make `buildgit status` always default to compact one-line output regardless of TTY state, matching what `--line` produces today.

## Specification

### Default output change

`buildgit status` (with no flags) will always produce a single one-line summary of the latest build, regardless of whether stdout is a TTY or not:

```
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)
```

The format follows the existing default template: `%s #%n id=%c Tests=%t Took %d on %I (%r)`

### TTY vs non-TTY difference

The only difference between TTY and non-TTY output is **color**:

- **TTY:** Status (`SUCCESS`/`FAILURE`) and test counts are colorized (existing behavior from line mode)
- **Non-TTY:** Plain text, no ANSI color codes (unchanged)

### Prior-jobs block

The default for `--prior-jobs` changes from 3 to **0** (suppressed) for plain `buildgit status`.

- `buildgit status` — one line, no prior-jobs (new default)
- `buildgit status --prior-jobs 3` — prior-jobs block + one line (opt-in)
- `buildgit status --prior-jobs 0` — explicitly suppress prior-jobs (same as new default)

### Preserved flags

All existing flags continue to work as before:

| Flag | Behavior |
|------|----------|
| `--all` | Forces full verbose output (banner, stages, tests, console URL). This is the escape hatch to get the old TTY default. |
| `--line` | Explicit one-line mode (now redundant with default, but still accepted) |
| `--format <fmt>` | Custom format string (implies one-line) |
| `--json` | JSON output (unchanged) |
| `-n <count>` | Show N most recent builds in one-line format, oldest first |
| `--no-tests` | Skip test API calls, show `?/?/?` |
| `--prior-jobs <N>` | Show N prior builds before main output (default now 0 instead of 3) |
| `<build#>` | Query specific build number (one-line output) |

### Commands NOT affected

These commands retain their existing behavior unchanged:

- `buildgit push` — still shows full monitoring output with prior-jobs
- `buildgit build` — still shows full monitoring output with prior-jobs
- `buildgit status -f` — still shows full follow/monitoring output with prior-jobs

Only the snapshot `buildgit status` (without `-f`) changes its default.

## Examples

```bash
# New default — one line, same on TTY and pipe
$ buildgit status
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)

# Piped — same output, no color
$ buildgit status | cat
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on 2026-03-02T17:09:01-0700 (16 hours ago)

# Full verbose output (old TTY default)
$ buildgit status --all

# With prior jobs opt-in
$ buildgit status --prior-jobs 3
[HH:MM:SS] ℹ Prior 3 Jobs
SUCCESS     #249 id=d502ded Tests=666/0/0 Took 2m 28s on ...
FAILURE     #250 id=unknown Tests=?/?/? Took 0s on ...
SUCCESS     #251 id=9512c5d Tests=666/0/0 Took 2m 19s on ...
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on ...

# Multiple builds
$ buildgit status -n 5
SUCCESS     #248 id=d502ded Tests=666/0/0 Took 2m 22s on ...
SUCCESS     #249 id=d502ded Tests=666/0/0 Took 2m 28s on ...
FAILURE     #250 id=unknown Tests=?/?/? Took 0s on ...
SUCCESS     #251 id=9512c5d Tests=666/0/0 Took 2m 19s on ...
SUCCESS     #252 id=9512c5d Tests=666/0/0 Took 2m 18s on ...
```

## Test Strategy

1. **Default output is one-line on TTY:** Verify `buildgit status` produces a single status line (no banner, no stages, no prior-jobs block)
2. **Default output is one-line on non-TTY:** Verify `buildgit status | cat` produces the same single line without color
3. **`--all` restores full output:** Verify `buildgit status --all` produces the full verbose output with banner, stages, tests
4. **`--prior-jobs` opt-in works:** Verify `buildgit status --prior-jobs 3` shows the prior-jobs block before the one-line status
5. **`--prior-jobs 0` suppresses:** Verify no prior-jobs block (same as default)
6. **`-n` flag works:** Verify `buildgit status -n 5` shows 5 one-line rows, oldest first
7. **`push`/`build`/`status -f` unchanged:** Verify these commands still show full monitoring output with default prior-jobs=3
8. **Existing `--line` flag still accepted:** Verify `buildgit status --line` works (now equivalent to default)

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
