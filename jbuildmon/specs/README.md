# Specs/ directory: Specifications, Implementation Plans, and Bug fixes workflow

### Todo directory
The specs/todo directory contains raw ideas for new features and/or bug fixes.
- files in this directory represent raw ideas that might need to be done in the future, but have not been spec'd, planned or implemented yet.
- specs (`*-spec.md`) and plans (`*-plan.md`) that are ready to implement belong in `specs/`, not `specs/todo/`
- see specs/todo/README.md for an index of all the todo items in the folder


### Spec and Bug index
These files represent completed specifications in the specs/ directory.  This list should be updated when the specs are completed.
- checkbuild-spec.md  checkbuild.sh shell script to check the current build status of git/Jenkins project from working directory
- jenkins-build-monitor-spec.md  pushmon.sh shell script to push staged git changes to origin and monitor build status until complete.
- install-bats-core-spec.md  install bats-core as unit testing framework
- bug2026-01-28-jenkins-log-truncated-spec.md  fix for stage log truncation when displaying failure analysis
- test-failure-display-spec.md  enhancement to display junit test failures in terminal output
- bug2026-01-28-test-case-failure-not-shown-spec.md  fix for empty FAILED TESTS section when jq query doesn't match Jenkins API structure
- fixjobflags-spec.md  unify job name handling with auto-detection and --job flag for pushmon.sh and checkbuild.sh
- buildgit-spec.md  combined git and Jenkins build tool (status, push, build commands)
- full-stage-print-spec.md  display all pipeline stages with durations during build monitoring
- bug2026-02-04-running-stage-spam-spec.md  fix running stage printed on every poll cycle during monitoring
- unify-follow-log-spec.md  unified build monitoring output format for push, build, and status -f commands
- refactoring-simple-spec.md  deduplication pass across buildgit and jenkins-common.sh (extract helpers, remove dead wrappers, merge functions)
- buildgit-early-build-failure-spec.md  show full console log when a build fails before any pipeline stage runs (e.g. Jenkinsfile syntax error)
- bug-status-f-missing-header-spec.md  fix for missing build header when `buildgit status -f` detects a build that already completed
- bug-status-json-spec.md  fix `buildgit status --json` to include console output for early failures and multi-line error extraction for stage failures
- buildgit-skill-spec.md  make buildgit a portable Agent Skill following the agentskills.io open standard
- console-on-unstable-spec.md  add `--console` global option to suppress noisy error logs for UNSTABLE builds and allow explicit console log display
- bug-json-stdout-pollution-spec.md  remove `git status` from `buildgit status` to fix JSON stdout pollution and make status Jenkins-only
- bug2026-02-12-phandlemono-no-logs-spec.md  fix NOT_BUILT and other non-SUCCESS results missing error display in monitoring mode; add default error log display to push/build/status -f
- refactor-shared-failure-diagnostics-spec.md  extract shared `_display_failure_diagnostics()` function so monitoring mode shows same failure output as snapshot mode; adds missing Failed Jobs tree to monitoring mode
- nested-jobs-display-spec.md  display downstream/nested build stages inline with agent names, `->` nesting notation, real-time monitoring, and recursive support across all output modes
- feature-status-job-number-spec.md  `buildgit status <build#>` positional argument to query a specific historical build by number
- bug2026-02-13-build-monitoring-header-spec.md  fix missing Agent/Pipeline/Commit in build monitoring header, remove Elapsed field, add Duration line at completion, add running-time message for `status -f`, fix snapshot console_output passthrough
- show-test-results-always-spec.md  display test results summary for all completed builds (SUCCESS, FAILURE, UNSTABLE) across all output modes; green for all-pass, yellow for failures, placeholder when no report
- bug-parallel-stages-display-spec.md  fix parallel stage tracking in monitoring mode (premature printing, missing nested downstream stages), add visual `║` parallel indicator, and show aggregate wrapper duration
- feature2026-02-14-numbered-parallel-stage-display-spec.md  add numbered parallel branch markers (`║1`, `║2`, `║3.1`), fixed-width agent formatting, wrapper-last ordering, and snapshot/monitoring terminal output consistency rules
- bug2026-02-14-parallel-branch-downstream-mapping-spec.md  fix incorrect downstream job association in parallel branch stage mapping so each branch shows its own nested stages across status and monitoring modes
- bug2026-02-14-monitoring-missing-stages-spec.md  fix monitoring mode missing downstream stages and premature wrapper/branch printing by deferring wrapper and downstream parent stages until children are resolved
- usage-help-spec.md  display full usage help on unknown/invalid options for `status` and `build` subcommands; recognize `-h`/`--help` as valid help request on subcommands
- 2026-02-15_quick-status-line-spec.md  add TTY-aware one-line snapshot mode (`--line`/`--line=N`) and full-output override (`--all`) for `buildgit status`
- 2026-02-15_line-jobs-enhance-spec.md  align `status --line` result field to fixed width and colorize status tokens with existing TTY-aware color rules
- 2026-02-16_single-line-with-tests-spec.md  add `Tests=pass/fail/skip` to `status --line` output, replace `completed in` with `Took`, and add `--no-tests` to skip line-mode test report fetches
- 2026-02-16_add-once-flag-to-status-f-spec.md  add `--once` for `buildgit status -f` to follow one build and exit (including `--json` support)
- 2026-02-19_line-n-flag-oldest-first-spec.md  replace `--line=N` with `-n <count>` flag and reverse line mode output order to oldest-first (newest build on last line)
- 2026-02-20_add-f-option-to-line-status-spec.md  allow `status -f --line`, add TTY progress bar for in-progress builds, support `-n` + follow + line, and keep non-TTY follow-line output silent until completion
- 2026-02-20_expand-in-progress-status-bar-spec.md  add `--line` support to `push`/`build` and expand TTY in-progress progress bar rendering across build-monitoring commands
- 2026-02-21_expand-verbose-flag-spec.md  add `-v` short alias for `--verbose` global option
- 2026-02-21_allow-negative-job-number-spec.md  add relative `status` build references (`0`, `-1`, `-2`), reject build-ref with `-n`, and make `-n` work in full/json snapshot mode
- 2026-02-21_version-number-spec.md  add `--version` global option and `BUILDGIT_VERSION` variable for semantic versioning
- 2026-02-23_status-line-template-spec.md  add `--format <fmt>` option to customize `--line` output with `%`-style placeholders including git commit SHA and branch name
- 2026-02-27_change-default-oneline-status-spec.md  change default one-line output to `%s #%n id=%c Tests=%t Took %d on %I (%r)` and remove job name from default line mode
- 2026-02-27_estimated-build-time-and-old-jobs-spec.md  add monitoring preamble with prior completed builds (`--prior-jobs`, default 3) and estimated build time for `push`, `build`, and `status -f`
- 2026-02-27_add-prior-jobs-to-snapshot-status-spec.md  add prior-jobs block to snapshot `status` output (including `status <build#>` and `status -n`) with strict prior-to-target selection
- 2026-02-27_status-display-timing-issue-spec.md  fix monitoring header consistency so push/build/status -f align on Commit/Agent placement and always print Console last
- 2026-02-27_multiple-builds-at-once-spec.md  eliminate follow progress redraw flash, show concurrent running build rows, and surface queued builds/queue wait behavior in status/build/push monitoring
- 2026-02-27_enhance-multiple-builds-at-once-spec.md  reduce queue wait log noise with transition-based sticky/throttled updates, extend queued secondary rows to push/build monitoring, and tighten redraw sequencing to reduce flash
- 2026-02-27_bug-progressbar-missing-on-queued-build-spec.md  fix queue wait progress bar never showing on TTY for build/push due to command substitution breaking TTY detection
- 2026-02-27_copy-process-files-to-template-spec.md  extract generic spec-driven development process framework into reusable `templates/` directory with install script
- 2026-03-03_short-buildgit-status-spec.md  change snapshot `buildgit status` default to one-line output on both TTY/non-TTY and suppress snapshot prior-jobs by default (`--prior-jobs 0`)
- 2026-03-03_multibranch-pipeline-spec.md  add Jenkins Multibranch Pipeline support with `<job>/<branch>` job format, branch-aware auto-resolution, and encoded multibranch API paths
- 2026-03-04_bug-multibranch-push-spec.md  fix Bash 3.2 `set -u` crash in multibranch `buildgit push` when no push args are provided; add branch-inference tests for empty args and remote-only push
- 2026-03-04_short-status-sandbox-fail-spec.md  distinguish test-report communication failures from missing reports, show `Tests=!err!` in line mode, add one-time warning, and expose JSON `testResultsError` for communication failures
- 2026-03-04_status-all-wrong-node-name-spec.md  fix stage agent attribution to use per-stage console mapping, preserve full `Running on` names (including spaces), and keep Build Info header agent extraction accurate
- 2026-03-04_realtime-timing-fix-spec.md  make monitoring-mode parallel stage timing, ordering, and settle-loop completion match snapshot output for completed builds
- 2026-03-05_threads-display-tty-spec.md  add `--threads` TTY monitoring rows for live active-stage progress, per-stage duration estimates, terminal-size truncation, and redraw integration above the overall progress bar
- 2026-03-06_bug-agent-name-missed-spec.md  fix `--threads` synthetic parallel wrapper rows to use the orchestrator pipeline agent instead of blank or downstream agent names
- 2026-03-07_parallel-branch-substages-spec.md  nest branch-local sequential substages under their parallel branch, inherit branch agent/path, and aggregate branch/wrapper durations consistently across snapshot, follow, threads, and JSON output
- 2026-03-07_integration-test-framework-spec.md  add always-on Jenkins integration tests that trigger branch-matched multibranch pipelines and verify buildgit snapshot/follow output against a real parallel-substages pipeline
- 2026-03-09_threads-parallel-substage-visibility-spec.md  make `--threads` show active nested substages inside parallel branches, reuse substage duration estimates, and cover the behavior with redraw/unit/integration tests
- 2026-03-06_format-stage-display-spec.md  add customizable format strings, width/alignment controls, and env/default precedence for `--threads` live per-stage TTY rows
- 2026-03-08_agent-failure-diagnostics-spec.md  add `status --console-text [stage]`, `status --list-stages`, and verbose failed-test stdout/untruncated diagnostics for agent workflows
- 2026-03-11_build-optimization-diagnostics-spec.md  add node-centric agent overlap diagnostics, stage-correlated timing views/comparisons, and pipeline test-suite enrichment for build optimization work
- 2026-03-12_ralph-loop-workflow-spec.md  integrate SPEC workflow into ralph-loop multi-chunk plan execution with per-chunk workflow steps, implementation logs, and automated finalize step
- 2026-03-14_standardize-stdout-stderr-spec.md  route normal status/monitoring output to stdout, keep only actual command or Jenkins communication failures on stderr, and preserve clean redirected logs for `status`, `push`, and `build`
- 2026-03-14_condense-build-header-spec.md  condense full-output build headers, unify trigger/user display from Jenkins API causes, show commit subjects inline, and promote Agent to a top-level header field
- 2026-03-14_status-follow-probe-all-branches-spec.md  add `status -f --probe-all` so multibranch follow mode can latch onto the next build from any branch and then monitor that detected branch job
- 2026-03-16_test-fail-need-results-still-spec.md  hierarchical downstream test-result trees in full output, aggregated one-line totals, JSON `breakdown` arrays, and monitoring-mode consistency
