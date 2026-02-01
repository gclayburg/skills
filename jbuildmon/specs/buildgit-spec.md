# buildgit - Combined Git and Jenkins Build Tool
Date: 2026-01-31

## Overview

`buildgit` is a bash shell script that combines functionality from the regular `git` executable with Jenkins build monitoring capabilities from `checkbuild.sh`, `pushmon.sh`, and `jenkins-common.sh`. It provides a unified interface for git operations that are tied to Jenkins CI/CD pipelines.

## Installation

The script is installed as `./buildgit` in the project directory alongside the existing scripts.

## Dependencies

- Reuses `jenkins-common.sh` for Jenkins API interactions and common functionality
- Must not break existing `checkbuild.sh` or `pushmon.sh` scripts
- Requires the same Jenkins configuration as existing scripts

## Global Options

These options apply to all commands and must appear before the command name:

| Option | Description |
|--------|-------------|
| `-j, --job <name>` | Specify Jenkins job name (same behavior as checkbuild.sh/pushmon.sh) |
| `-h, --help` | Display help information |
| `--verbose` | Enable verbose output for debugging |

### Verbosity Behavior

**Default (quiet mode):**
- Suppresses informational messages: "Connected to Jenkins", "Found job name", "Analyzing build details...", "Waiting for build to start..."
- Shows essential output: git command output, build results, errors/failures, test failure details

**With `--verbose`:**
- Shows all messages including connection status, job detection, progress details
- Useful for debugging when something goes wrong

## Commands

### `buildgit status`

Displays combined git and Jenkins build status.

**Behavior:**
1. Execute and display `git status` output
2. Display Jenkins build status (identical to `checkbuild.sh` output)

**Options:**
| Option | Description |
|--------|-------------|
| `-f, --follow` | Follow builds: monitor current build if in progress, then wait indefinitely for subsequent builds. Displays "Waiting for next build of <job>..." between builds. Exit with Ctrl+C. |
| `--json` | Output Jenkins status in JSON format (same as `checkbuild.sh --json`) |
| Other options | Passed through to `git status` (e.g., `-s` for short format) |

**Examples:**
```bash
buildgit status              # Git status + Jenkins build snapshot
buildgit status -f           # Follow builds indefinitely
buildgit status --json       # JSON format for Jenkins status
buildgit status -s           # Short git status + Jenkins status
buildgit --job visualsync status --json  # Specific job, JSON output
```

### `buildgit push`

Pushes commits to remote and monitors the resulting Jenkins build.

**Behavior:**
1. Execute `git push` with any provided arguments
2. If push succeeds, monitor Jenkins build until completion (like `pushmon.sh`)
3. If nothing to push, display git's output and exit with git's exit code

**Options:**
| Option | Description |
|--------|-------------|
| `--no-follow` | Push only, do not monitor Jenkins build |
| Other options | Passed through to `git push` |

**Exit Code:** Returns non-zero if the Jenkins build fails (when monitoring is enabled).

**Examples:**
```bash
buildgit push                        # Push + monitor build
buildgit push --no-follow            # Push only, no monitoring
buildgit push origin featurebranch   # Push to specific remote/branch + monitor
buildgit --job visualsync push       # Push with specific job
```

**Notes:**
- Does not commit. Users should run: `git commit -m 'message' && buildgit push`
- Uncommitted changes are handled by git's normal behavior

### `buildgit build`

Triggers a Jenkins build and monitors it until completion.

**Behavior:**
1. Trigger a new build for the job (equivalent to pressing "Build Now" in Jenkins)
2. Monitor build progress until completion (like `pushmon.sh`)

**Options:**
| Option | Description |
|--------|-------------|
| `--no-follow` | Trigger build and confirm queued, then exit without monitoring |

**Exit Code:** Returns non-zero if the build fails.

**Error Handling:**
- If `--job` is not specified and auto-detection fails, error out with a descriptive message

**Examples:**
```bash
buildgit build                       # Trigger + monitor build
buildgit build --no-follow           # Trigger only
buildgit --job visualsync build      # Build specific job
```

### Unknown Commands

Any command not explicitly handled by `buildgit` is passed through to `git` for processing.

**Examples:**
```bash
buildgit log                 # Passes to: git log
buildgit diff HEAD~1         # Passes to: git diff HEAD~1
buildgit checkout -b feature # Passes to: git checkout -b feature
```

## Error Handling

### Jenkins Unavailable

If Jenkins is unavailable (network error, authentication failure, etc.):
- Git operations (push, status) should still be attempted and complete
- Display appropriate error messages about Jenkins connectivity
- For `buildgit build`, the command will fail since it cannot function without Jenkins

### Non-Git Directory

If `buildgit` is used in a directory that is not a git repository:
- Git commands will produce stderr output and non-zero exit codes
- Display git's error message
- Still attempt to show Jenkins build information (especially if `--job` is provided)

### Job Detection Failure

If no `--job` is specified and auto-detection fails:
- For `buildgit status`: Show git status, display error for Jenkins portion
- For `buildgit build`: Exit with error and descriptive message

## Exit Codes

| Scenario | Exit Code |
|----------|-----------|
| Success (git OK, build OK) | 0 |
| Git command fails | Git's exit code |
| Jenkins build fails | Non-zero |
| Nothing to push | Git's exit code |
| Jenkins unavailable during push | Non-zero (after git push completes) |

## Output Format

### `buildgit status` (default)

```
[git status output]

[checkbuild.sh equivalent output]
```

### `buildgit status --json`

```
[git status output]

[JSON build status from checkbuild.sh]
```

## Command Syntax Summary

```
buildgit [global-options] <command> [command-options] [arguments]

Global Options:
  -j, --job <name>    Specify Jenkins job name
  -h, --help          Show help
  --verbose           Enable verbose/debug output

Commands:
  status [-f|--follow] [--json] [git-status-options]
  push [--no-follow] [git-push-options] [remote] [branch]
  build [--no-follow]
  <any-git-command>   Passed through to git
```
