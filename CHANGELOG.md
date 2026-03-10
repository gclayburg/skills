# Changelog

All notable changes to **jbuildmon** (Jenkins Build Monitor / `buildgit`) are documented in this file.

## [1.2.0] - 2026-03-10

### Added
- **Multibranch Pipeline job support** — `--job` now accepts `<job>/<branch>` for Multibranch Pipeline jobs. When omitted, the branch auto-resolves from the current or pushed git branch.
- **`--threads` live stage progress** — New global option shows per-stage progress rows above the build progress bar during TTY monitoring, with agent names, elapsed time, and estimated completion.
- **Custom `--threads` format strings** — `--threads` accepts an optional format argument with `%`-placeholders (`%a` agent, `%S` stage, `%g` bar, `%p` percent, `%e` elapsed, `%E` estimate) and width/alignment controls. Configurable via `BUILDGIT_THREADS_FORMAT`.
- **`--console-text [stage]`** — Print raw console text for an entire build or a specific pipeline stage. Stage names support case-insensitive partial matching.
- **`--list-stages`** — List available pipeline stages for a build. Combine with `--json` for machine-readable output.
- **Verbose failure diagnostics** — `-v` now preserves full failed-test stack traces and captured `stdout` in snapshot and JSON output.

### Fixed
- **`--console-text` stage lookup** — Partial stage names are now matched case-insensitively; ambiguous matches produce a clear error. Parent stages with no direct log text now return concatenated descendant logs with section headers.
- **Test report errors distinguished from missing reports** — Jenkins communication failures now show `Tests=!err!` in line mode, a warning in full output, and `testResultsError` in JSON, instead of silently showing no test results.
- **Per-stage agent names** — Each stage now shows its own Jenkins agent instead of reusing a single agent for all stages.
- **Parallel stage timing in monitoring** — `push`, `build`, and `status -f` now wait for all parallel branches before printing, showing correct durations and `║`-ordered rows.
- **Nested stages inside parallel branches** — Substages within a parallel branch now render as `Branch->Substage` with correct nesting, agent names, and aggregated durations across all output modes.
- **`--threads` with nested parallel substages** — Active substages inside parallel branches now display correctly with proper agent and duration estimates.

### Changed
- **`buildgit status` defaults to one-line output** — Snapshot mode now uses compact one-line output on both TTY and piped stdout (TTY keeps color). Use `--all` for full output.
- **`--prior-jobs` default changed to 0 for snapshots** — `buildgit status` no longer shows prior builds unless `--prior-jobs <N>` is specified. Monitoring commands (`push`, `build`, `status -f`) are unchanged.

## [1.1.0] - 2026-03-02

### Added
- **`--format <fmt>` custom output format** — Customize `--line` output with `%`-style placeholders: `%s` (status), `%j` (job), `%n` (build number), `%t` (tests), `%d` (duration), `%D` (date), `%I` (ISO 8601 datetime), `%r` (relative time), `%c` (git commit SHA), `%b` (git branch), `%%` (literal `%`). Specifying `--format` implies `--line`. Conflicts with `--json` and `--all` are reported as errors.
- **`--prior-jobs <N>` prior build context** — Show N recently completed builds (default 3, oldest-first) before the main output in `status`, `push`, `build`, and `status -f`. Use `--prior-jobs 0` to suppress. Works with `status <build#>` to show builds prior to the specified build.
- **Estimated build time in monitoring** — `push`, `build`, and `status -f` now print `Estimated build time = ...` from Jenkins `lastSuccessfulBuild` duration before monitoring begins.
- **Concurrent build and queue display** — Monitoring modes (`push`, `build`, `status -f`) now show one progress row per concurrently running build and display queued builds with `QUEUED` status, queue reason, and elapsed queue time. Queue wait uses transition-based logging to reduce noise.

### Changed
- **`status --line` default format** — Changed to `%s #%n id=%c Tests=%t Took %d on %I (%r)`, dropping redundant job name and adding commit id with ISO 8601 timestamp.
- **Monitoring header field order** — `push`, `build`, and `status -f` now keep Commit before Started, Agent in Build Info, and Console printed last.

## [1.0.0] - 2026-02-21

### Added
- **`buildgit` unified CLI** — Combined git and Jenkins build tool with `status`, `push`, `build` subcommands and transparent git pass-through for any other git command.
- **`--job` flag and auto-detection** — Job name auto-detected from git remote; `--job <name>` overrides for all commands.
- **`--version` global option** — Display current buildgit version and exit. Version `1.0.0` is the initial release.
- **`-v` verbose short flag** — `-v` as alias for `--verbose`.
- **`buildgit status <build#>`** — Query a specific historical build by number. Supports relative references (`0` for latest, `-1` for previous, etc.).
- **`-n <count>` multi-build display** — Show N most recent builds in oldest-first order. Works with `--line`, `--json` (JSONL), and full output modes.
- **`--line` one-line status mode** — Compact one-line build summaries with fixed-width status column, TTY-aware color, and `Tests=pass/fail/skip` results. `--all` forces full output. Default is TTY-aware (full on terminal, one-line when piped).
- **`--no-tests` flag** — Skip test report API calls in line mode.
- **`--once` follow mode** — `status -f --once[=N]` follows one build and exits. Optional timeout (default 10s) for waiting when no build is in progress.
- **`status -f --line` follow with progress bar** — In-progress builds show an animated progress bar with elapsed time and estimate on TTY. Completed builds replace the bar with a standard `--line` row. Non-TTY output is silent until completion.
- **`push --line` and `build --line`** — Compact line monitoring mode for push and build commands with the same progress bar behavior.
- **`--console` global option** — Control console log display; suppress noisy error logs for UNSTABLE builds.
- **Nested/downstream job display** — Downstream build stages shown inline with agent names, `->` nesting notation, real-time monitoring, and recursive support across all output modes.
- **Parallel stage display** — Parallel pipeline stages marked with numbered `║` indicators, proper tracking in monitoring mode, and aggregate wrapper duration.
- **Test results for all builds** — Test results summary shown for SUCCESS, FAILURE, and UNSTABLE builds. Green for all-pass, yellow for failures, placeholder when no report available.
- **Full stage print during monitoring** — All pipeline stages with durations displayed during build monitoring, not just the running stage.
- **Unified monitoring output** — Consistent output format across `push`, `build`, and `status -f` during build monitoring.
- **Usage help on invalid options** — Unknown options for `status` and `build` display full usage help. `-h`/`--help` recognized on subcommands.
- **Early build failure display** — Full console log shown when a build fails before any pipeline stage runs (e.g. Jenkinsfile syntax error).
- **Agent Skill packaging** — `buildgit` packaged as a portable Agent Skill following the agentskills.io open standard.
- **Test failure display** — JUnit test failure details shown in terminal output after a failed build.
- **bats-core test framework** — Unit testing framework installed and configured for the project.

### Fixed
- **Jenkins log truncation** — Fixed stage log truncation when displaying failure analysis.
- **Empty test failure section** — Fixed jq query not matching Jenkins API structure.
- **JSON stdout pollution** — Removed `git status` output from `buildgit status` so `--json` output is clean.
- **NOT_BUILT results missing error display** — Fixed monitoring mode not showing error output for NOT_BUILT and other non-SUCCESS stage results.
- **Parallel branch downstream mapping** — Fixed incorrect downstream job association in parallel branches.
- **Monitoring missing stages** — Fixed monitoring mode missing downstream stages and printing wrapper stages prematurely.
- **Build monitoring header** — Fixed missing Agent/Pipeline/Commit fields, removed misleading Elapsed field, added Duration line at completion.
- **`status -f` missing header** — Fixed missing build header when `status -f` detects an already-completed build.
- **`status --json` incomplete output** — Fixed JSON mode missing console output for early failures and multi-line error extraction.
