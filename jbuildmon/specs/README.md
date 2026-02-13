# Specs/ directory: Specifications, Implementation Plans, and Bug fixes workflow

## Project Specs

Individual `*-spec.md` files are treated as the specification for each feature—they define what the feature is and what it must do. These specification files are the authoritative ("canonical") source of requirements for their parts of the application.

- If there are conflicting specifications, newer ones are always more important than older ones
- All spec files that are created from other raw report documents should reference those documents in the title header of the spec
- When writing a new spec, review the existing specs in the specs/ directory and identify any that are clearly superseded by your new specification. List only the directly superseded (first-level) specs.

## Creating a new spec

**Specification template (include at top of each spec):**
```
# Title
Date: <ISO 8601 format with seconds, America/Denver timezone>
References: list of <other-raw-report-path.md> or <none>
Supersedes: list of <other-spec-file.md>
```

## Spec rules
- any changes to the 'buildgit status' command must ensure that 'buildgit status', 'buildgit status -f', and 'buildgit status --json' are always consistent with each other.  If you change one of these, they all should be changed to match.

### Todo directory
The specs/todo directory contains specs or plans for new features and/or bug fixes.  
- files in this directory represent items that need to be done in the future, but have not been implemented yet.
- IMPORTANT: when these items are completed, the file should be moved to the specs/directory
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



## Helper Prompts
Helper prompts are used by AI to automatically generate other documents
- taskcreator.md  instructions to create individual chunks (implementation tasks) from a spec file
- chunk_template.md template of sample chunk of implementation plan

## implementation plan
- Any file named *-plan.md or *_plan.md is an implementation plan that have rules for how they are updated
- These files are created from a spec file using taskcreator.md
- Each chunk has a brief description, which has backing documentation in the referenced spec section
- Each chunk starts as an un marked checkbox, meaning the task has not been completed.
- When a task or 'chunk' in the plan has been implemented, it is marked as completed.
- Once a plan is implemented, the corresponding plan.md file is not useful and can be considered archival status

### Chunk Execution Rules
- **All chunks are designed to be executed by an AI agent.** There are no "manual-only" or "investigation-only" chunks that should be skipped.
- Agents must attempt each chunk before concluding it cannot be done. If a chunk requires data gathering (API calls, file reads, etc.), the agent should execute those operations.
- Chunks must be completed in dependency order. Do not skip a prerequisite chunk and substitute assumptions for its outputs.
- See AGENTS.md for detailed execution guidance.


## Bug reports
### Bug Report File Naming Conventions
Bug reports go through these phases

raw bug report -> root cause analysis spec -> implementation plan -> code fix
Each arrow here goes through a documented process to create the next phase

- **Raw bug reports:**  
  Use the following naming pattern for raw, unprocessed bug reports:  
  ```
  specs/bug<YYYY-MM-DD>-<title>-raw-bugreport.md
  ```
  Example: `specs/bug2026-01-28-stage-log-truncated-raw-bugreport.md`
- **Analyzed bug reports:**  
  Once a bug report has been analyzed for its root cause, name the file as:  
  ```
  specs/bug<YYYY-MM-DD>-<title>-spec.md
  ```
  Example: `specs/bug2026-01-28-stage-log-truncated-spec.md`
- **Implementation plans for bug fixes:**  
  After a bug spec has been broken down into an implementation plan, use the following naming pattern:  
  ```
  specs/bug<YYYY-MM-DD>-<title>-plan.md
  ```
  Example: `specs/bug2026-01-28-stage-log-truncated-plan.md`

