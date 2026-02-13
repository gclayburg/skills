# Feature: `buildgit status <build#>` — Query Specific Build Number
Date: 2026-02-13T10:30:00-07:00
References: specs/todo/feature-status-job-number.md, specs/todo/needed_tools.md
Supersedes: none

## Overview

`buildgit status` currently always shows the latest build. This feature adds an optional positional argument to query a specific historical build by number.

## Syntax

```
buildgit status [build#] [--json]
buildgit --job <name> status [build#] [--json]
buildgit --console <mode> status [build#]
```

The build number is an optional positional argument to the `status` command. It can appear in any position among the status options (before or after `--json`).

### Examples

```bash
buildgit status 31                    # Status of build #31
buildgit status 31 --json             # JSON status of build #31
buildgit status --json 31             # Same as above (order doesn't matter)
buildgit --job handle status 31       # Build #31 of job "handle"
buildgit --console auto status 31     # Build #31 with console error logs
buildgit status                       # Latest build (unchanged behavior)
```

## Specification

### 1. Positional Argument Parsing in `_parse_status_options()`

The `_parse_status_options()` function gains support for a bare positional argument representing the build number. It sets a new global variable:

```
STATUS_BUILD_NUMBER=""    # empty = latest build (default)
```

**Validation rules:**
- Must be a positive integer (regex: `^[1-9][0-9]*$`)
- Non-numeric values (e.g. `abc`, `0`, `-5`, `1.5`) produce an error and non-zero exit
- Only one build number may be specified; a second positional argument is an error

**Error output format:**
```
Error: Invalid build number: <value> (must be a positive integer)
```

### 2. Incompatibility with Follow Mode

`buildgit status <build#> -f` is invalid — it doesn't make sense to follow a historical build.

When both a build number and `-f`/`--follow` are specified (in any order), the command must:
1. Print an error message: `Error: Cannot use --follow with a specific build number`
2. Print the correct usage
3. Exit with a non-zero code

This validation occurs after `_parse_status_options()` finishes parsing, before any Jenkins API calls.

### 3. Build Number Passed to `_jenkins_status_check()`

`_jenkins_status_check()` currently takes `(job_name, json_mode)`. It gains an optional third parameter for the build number:

```bash
_jenkins_status_check "$_VALIDATED_JOB_NAME" "$STATUS_JSON_MODE" "$STATUS_BUILD_NUMBER"
```

**Behavior when build number is specified:**
- Skip the `get_last_build_number()` call
- Use the provided build number directly
- All subsequent logic (build info fetch, stage display, failure diagnostics, JSON output) proceeds identically

**Behavior when build number is empty (default):**
- Unchanged — calls `get_last_build_number()` as today

### 4. Non-Existent Build Number

When the Jenkins API returns no data for the requested build number (i.e., `get_build_info()` returns empty), display:

```
Error: Build #<number> not found for job '<job_name>'
```

Exit with non-zero code. This is consistent with the existing "Failed to fetch build information" error path, but with a more specific message when the user requested a particular build number.

### 5. Output Format

The output format is identical to the current `buildgit status` output. There is no special indication that a historical build was requested vs. the latest. The build header already includes the build number (e.g. `Build #31 of ralph1 ...`), which is sufficient context.

### 6. Interaction with Other Options

| Option | Compatible? | Behavior |
|--------|-------------|----------|
| `--json` | Yes | JSON output for the specified build |
| `-f`/`--follow` | No | Error (see Section 2) |
| `--job <name>` | Yes | Query build number on the specified job |
| `--console <mode>` | Yes | Show console output for the specified build |

### 7. Other Commands Unchanged

The build number positional argument applies **only** to `buildgit status`. The `push` and `build` commands are not affected and do not accept a build number argument.

### 8. Help Text Update

Update `show_usage()` to reflect the new syntax:

```
Commands:
  status [build#] [-f|--follow] [--json]
                      Display Jenkins build status (latest or specific build)
```

Add an example:
```
  buildgit status 31             # Status of build #31
```

### 9. Consistency Rule

Per `specs/README.md`: `buildgit status`, `buildgit status -f`, and `buildgit status --json` must be consistent. This feature maintains that:
- `buildgit status <build#>` — human-readable output for specific build
- `buildgit status <build#> --json` — JSON output for the same specific build
- `buildgit status <build#> -f` — explicitly disallowed (error)

## Files to Modify

| File | Changes |
|------|---------|
| `skill/buildgit/scripts/buildgit` | Update `_parse_status_options()` to parse positional build number. Add follow+build# incompatibility check in `cmd_status()`. Pass build number to `_jenkins_status_check()`. Update `_jenkins_status_check()` to accept and use optional build number. Update `show_usage()`. |
| `test/buildgit_status.bats` | Add tests: specific build number, invalid build number, non-existent build, build number with `--json`, build number with `--follow` error |
