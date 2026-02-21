## Add `--version` global option and version variable for buildgit

- **Date:** `2026-02-21T16:18:35-07:00`
- **References:** `specs/done-reports/version-number.md`
- **Supersedes:** (none)
- **State:** `IMPLEMENTED`

## Background

The raw note (voice-transcribed from `specs/todo/version-number.md`) requests:

- A way to query the running version of buildgit (`buildgit --version`).
- Semantic versioning, starting at **1.0.0**.
- The version number stored alongside the code and tagged in git for releases.
- Manual version bumps (no automated bump tooling required yet).

The buildgit script is distributed as a standalone AI Agent skill (`jbuildmon/skill/buildgit/`). The version number must be embedded in the script itself so it travels with the skill distribution.

## Specification

### 1. Version variable in the buildgit script

Add a version variable near the top of `jbuildmon/skill/buildgit/scripts/buildgit`, before any function definitions:

```bash
BUILDGIT_VERSION="1.0.0"
```

This variable is the **single source of truth** for the version number. Starting version is `1.0.0`.

### 2. Version bump process

Version bumps are manual. The process is:

1. Edit the `BUILDGIT_VERSION` variable in the buildgit script.
2. Update `CHANGELOG.md` with the new version and changes.
3. Commit the changes.
4. Tag the commit: `git tag v<major>.<minor>.<patch>` (e.g. `git tag v1.0.0`).

Semantic versioning rules apply:
- **MAJOR** — breaking changes to CLI interface or output format.
- **MINOR** — new features, new options, backward-compatible additions.
- **PATCH** — bug fixes, documentation, internal refactoring.

### 3. `--version` global option

Add `--version` (long form only, no short alias) as a global option in `parse_global_options()`.

Behavior:
- Print the version string to stdout and exit 0.
- Output format: `buildgit <version>` (e.g. `buildgit 1.0.0`).

The option is documented in:
- The `show_usage()` help text, listed with the other global options.
- `buildgit --help` output.

### 4. Updated help output

The Global Options section of `--help` gains one new line:

```
Global Options:
  -j, --job <name>               Specify Jenkins job name (overrides auto-detection)
  -c, --console <mode>           Show console log output (auto or line count)
  -h, --help                     Show this help message
  -v, --verbose                  Enable verbose output for debugging
  --version                      Show version number and exit
```

### 5. Git tagging convention (documentation only)

Document in `CHANGELOG.md` that releases use git tags of the form `v<major>.<minor>.<patch>` (e.g. `v1.0.0`). The actual tagging is a manual step performed at release time — no automation is required by this spec.

## Test Strategy

### Unit tests (bats)

Add a new test file `jbuildmon/test/buildgit_version.bats`:

1. **`buildgit --version` prints version** — run `buildgit --version`, assert output matches `buildgit <version>` where `<version>` equals the `BUILDGIT_VERSION` variable extracted from the script.
2. **`--version` exits 0** — assert exit code is 0.
3. **`--version` takes precedence over commands** — run `buildgit --version status`, assert it still prints version and exits 0 (global option parsed before command).

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
