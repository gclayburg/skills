# Changelog

All notable changes to **jbuildmon** (Jenkins Build Monitor / `buildgit`) are documented in this file.

## 2026-02-15

### Features
- **Usage help on invalid options** — Unknown or invalid options for `status` and `build` subcommands now display the full usage help alongside the error message. `-h`/`--help` is recognized on `status` and `build` subcommands as a valid help request (exit 0, stdout). Error usage output goes to stderr consistently across all commands.
- **Quick status line mode** — Added `buildgit status --line` with optional count (`--line=N`) for compact one-line summaries. Added `--all` to force full status output. Default snapshot behavior is now TTY-aware (`status` shows full output on TTY and one-line output when piped/redirected).
- **Line status alignment and color** — Enhanced `buildgit status --line` and `--line=N` output to render a fixed-width 11-character result column (padded/truncated) and color only the status token using existing TTY-aware color rules.

## 2026-02-14

### Bug Fixes
- **Monitoring mode missing stages** — Fixed monitoring mode (`build`, `push`, `status -f`) missing downstream stages and printing wrapper/parent stages prematurely. Wrapper stages with parallel branches are now deferred until all branches reach terminal status. Downstream parent stages are deferred until at least one child stage appears. Settlement window increased to allow deeply nested builds to fully resolve.
- **Downstream job matching for shared-prefix job names** — Fixed `_select_downstream_build_for_stage` matching the wrong downstream job when multiple job names share a common prefix (e.g., `phandlemono-handle` vs `phandlemono-signalboot`). Segment-level matches now score higher than substring matches.

## 2026-02-13

### Features
- **Show test results for all builds** — Test results summary (`=== Test Results ===`) now appears for all completed builds including SUCCESS, not just failures. Uses green color for all-pass, yellow for failures. Shows placeholder when no test report is available. JSON output includes `test_results` field for all completed builds.
- **Parallel stages display** — Parallel pipeline stages (e.g., `parallel { }` blocks) are now visually distinguished with `║` markers, properly tracked in monitoring mode, and show aggregate wrapper duration. JSON output includes `is_parallel_wrapper`, `parallel_branches`, `parallel_branch`, and `parallel_wrapper` fields.

### Bug Fixes
- **Parallel stages premature printing** — Fixed monitoring mode printing parallel branch stages before they completed, showing `(unknown)` duration. All parallel branches are now independently tracked through completion.
- **Missing downstream stages for parallel branches** — Fixed `extract_stage_logs()` not finding parallel branch console logs because Jenkins uses `(Branch: StageName)` prefix. Added fallback to search with `Branch:` prefix.
- **Parallel wrapper stage duration** — Wrapper stages containing parallel blocks now show aggregate wall-clock duration (wrapper API time + longest branch duration) instead of just the setup time.
- **Build monitoring header cleanup** — Removed misleading `Elapsed:` field from build header; added `Duration:` line after `Finished:` in monitoring mode.
- **Snapshot mode missing Agent/Pipeline** — Fixed `buildgit status` not passing console output to header, so Build Info section (Agent, Pipeline) now displays in snapshot mode.
- **Deferred header fields** — When `buildgit build` triggers a new build, fields not yet available (Commit, Build Info, Console URL) are printed as soon as console output arrives instead of showing "unknown".
- **Running-time message for `status -f`** — When `status -f` joins an already in-progress build, shows "Job X #N has been running for Xm Xs" instead of a misleading elapsed time in the header.

## 2026-02-12

### Features
- **Nested/downstream job display** — Downstream and nested build stages are shown inline with agent names, `->` nesting notation, real-time monitoring, and recursive support across all output modes (status, status -f, status --json, push, build).
- **`buildgit status <build#>`** — Query a specific historical build by number using a positional argument.
- **`--console` global option** — Suppress noisy error logs for UNSTABLE builds; allow explicit console log display on demand.

### Bug Fixes
- **NOT_BUILT / non-SUCCESS results missing error display** — Fixed monitoring mode (push/build/status -f) not showing error output for NOT_BUILT and other non-SUCCESS stage results.
- **JSON stdout pollution** — Removed `git status` output from `buildgit status` so `--json` output is clean; `buildgit status` is now Jenkins-only.

### Refactoring
- **Shared failure diagnostics** — Extracted `_display_failure_diagnostics()` so monitoring mode shows the same failure output as snapshot mode; added missing Failed Jobs tree to monitoring mode.

## 2026-02-09 — 2026-02-11

### Features
- **Agent Skill packaging** — Packaged `buildgit` as a portable Agent Skill following the agentskills.io open standard (`skill/buildgit/`).

### Bug Fixes
- **`buildgit status --json` incomplete output** — Fixed JSON mode to include console output for early failures and multi-line error extraction for stage failures.
- **`buildgit status -f` missing build header** — Fixed missing header when `status -f` detects a build that already completed.
- **Early build failure display** — Show full console log when a build fails before any pipeline stage runs (e.g. Jenkinsfile syntax error).

### Refactoring
- **Code deduplication pass** — Extracted helpers, removed dead wrappers, and merged duplicated functions across `buildgit` and `jenkins-common.sh`.
- **Migrated legacy tests to bats-core** — Converted old checkbuild/pushmon shell tests to the bats-core framework.

## 2026-02-06 — 2026-02-08

### Features
- **Unified follow/monitoring output** — Consistent output format across `push`, `build`, and `status -f` commands during build monitoring.
- **Full stage print** — Display all pipeline stages with durations during build monitoring (not just the running stage).

### Bug Fixes
- **Running stage spam** — Fixed the running stage being printed on every poll cycle during monitoring.

## 2026-01-31 — 2026-02-02

### Features
- **`buildgit` unified CLI** — Combined git and Jenkins build tool with `status`, `push`, `build` subcommands and git pass-through.
- **`--job` flag and auto-detection** — Unified job name handling with auto-detection from git remote and explicit `--job` override for all commands.

### Bug Fixes
- **Monitoring mode failures** — Fixed various issues with build monitoring not detecting or reporting failures correctly.
- **checkbuild silent exit** — Fixed `checkbuild` exiting silently instead of reporting errors.

## 2026-01-27 — 2026-01-30

### Features
- **Test failure display** — Show JUnit test failure details in terminal output after a failed build.
- **bats-core test framework** — Installed and configured bats-core as the project unit testing framework.

### Bug Fixes
- **Jenkins log truncation** — Fixed stage log being truncated when displaying failure analysis.
- **Empty FAILED TESTS section** — Fixed jq query not matching Jenkins API structure, resulting in an empty test failure display.

## 2026-01-25 — 2026-01-26

### Initial Release
- **checkbuild** — Shell script to check current build status of a git/Jenkins project from the working directory.
- **pushmon** — Shell script to push staged git changes to origin and monitor build status until complete.
- Jenkins CI integration with build metadata display (user, agent, pipeline) on failure.
