# Agent Instructions (CLAUDE.md / AGENTS.md) 

This file provides guidance to Claude Code (claude.ai/code) and other agents like Cursor when working with code in this repository.

## Project Overview

This repository contains **jbuildmon** (Jenkins Build Monitor), a CLI tool that automates the developer workflow of committing code, pushing to a remote repository, and monitoring the resulting Jenkins CI/CD build until completion.

The canonical location of the buildgit script is `jbuildmon/skill/buildgit/scripts/buildgit`.
A symlink at `jbuildmon/buildgit` preserves backward compatibility.

Execute this tool with:  ./jbuildmon/buildgit

```bash
$ buildgit --help
Usage: buildgit [global-options] <command> [command-options] [arguments]

A unified interface for git operations with Jenkins CI/CD integration.

Global Options:
  -j, --job <name>               Specify Jenkins job name (or multibranch job/branch)
  -c, --console <mode>           Show console log output (auto or line count)
  --threads [<format>]           Show live active-stage progress during TTY monitoring
  -h, --help                     Show this help message
  -v, --verbose                  Enable verbose output for debugging
  --version                      Show version number and exit

Commands:
  status [build#] [-f|--follow] [--once[=N]] [--probe-all] [-n <count>] [--json] [--line] [--all] [--no-tests] [--format <fmt>] [--prior-jobs <N>] [--console-text [stage]] [--list-stages]
                      Display Jenkins build status (latest or specific build)
                      build# can be absolute (31) or relative (0=latest, -1=previous, -2=two ago)
                      Default: one-line output (TTY adds color)
  agents [--json] [--label <name>] [--nodes]
                      Show Jenkins executor capacity by label
  timing [build#] [--json] [--tests] [--by-stage] [--compare <a> <b>] [-n <count>]
                      Show per-stage and per-test-suite timing
  pipeline [build#] [--json]
                      Show pipeline structure (stages, parallelism, labels)
  queue [--json]
                      Show Jenkins build queue with wait reasons
  push [--no-follow] [--line] [--format <fmt>] [--prior-jobs <N>] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] [--line] [--format <fmt>] [--prior-jobs <N>]
                      Trigger and monitor Jenkins build
  <any-git-command>   Passed through to git

Examples:
Snapshot status of completed Jenkins build jobs:
  buildgit status                  # Jenkins build status snapshot
  buildgit status 31               # Status of build #31
  buildgit status --json           # JSON format for Jenkins status
  buildgit status --line           # One-line status with test results
  buildgit status -n 5 --line      # Last 5 builds, oldest first, one line each
  buildgit status -n 10 --no-tests # Last 10 builds, skip test fetch
  buildgit status --prior-jobs 5   # Latest build + 5 prior one-line builds
  buildgit status --prior-jobs 5 201  # Build #201 + 5 prior one-line builds
  buildgit status --prior-jobs 0   # Latest build, suppress prior-jobs display
  buildgit status --list-stages    # List available pipeline stages
  buildgit status --console-text   # Raw full console text
  buildgit status 60 --console-text "Unit Tests D"  # Raw console for one stage
  buildgit status --all | less     # Full status piped to pager
  buildgit push --no-follow        # Push only, no monitoring

Monitor ongoing Jenkins build jobs:
  buildgit status -f               # Follow builds indefinitely
  buildgit status -f --once        # Follow current/next build, exit when done (10s timeout)
  buildgit status -f --once=20     # Same, but wait up to 20 seconds for build to start
  buildgit status -f --probe-all   # Follow next build on any branch
  buildgit status -f --probe-all --once   # Follow one build on any branch, then exit
  buildgit status -n 3 -f          # Show 3 prior builds, then follow indefinitely
  buildgit status -n 3 -f --once   # Show 3 prior builds, then follow once with timeout
  buildgit status -f --line        # Follow builds with one-line output + progress bar (TTY only)
  buildgit --threads status -f --line # Add active-stage progress rows above the main bar
  buildgit --threads '[%a] %S %p' status -f --line # Custom stage-row format
  buildgit status -f --once --line # Follow one build in one-line mode, then exit
  buildgit status -n 5 -f --line   # Show 5 prior one-line rows, then follow in one-line mode
  buildgit push                    # Push + monitor build
  buildgit push --prior-jobs 5     # Push + show last 5 builds before monitoring
  buildgit push --prior-jobs 0     # Push + suppress prior-jobs display
  buildgit push --line             # Push + compact one-line monitoring with progress bar
  buildgit --threads push          # Push + show live active-stage progress rows on TTY
  buildgit build --line            # Trigger + compact one-line monitoring with progress bar
  buildgit --threads build         # Trigger + show live active-stage progress rows on TTY
  buildgit status -f --prior-jobs 5  # Follow with last 5 builds shown first
  buildgit --job myjob build       # Trigger build for specific job
  buildgit --job myjob/main status # Query explicit multibranch branch job

Build optimization:
  buildgit agents                  # Executor capacity by label
  buildgit agents --nodes          # Executor capacity by node with all labels
  buildgit queue                   # Current Jenkins queue and wait reasons
  buildgit timing --tests          # Slowest stages and test suites for latest successful build
  buildgit timing --tests --by-stage # Group test suites under their parent pipeline stage
  buildgit timing --compare 40 42  # Compare stage timing and deltas across two builds
  buildgit timing -n 3             # Compact timing table for the last 3 builds
  buildgit pipeline 42 --json      # Pipeline graph and agent labels for build #42

Format placeholders for --format (use with --line):
  %s=status  %j=job  %n=build#  %t=tests  %d=duration
  %D=date  %I=iso8601  %r=relative  %c=commit  %b=branch  %%=literal%
  Default: "%s #%n id=%c Tests=%t Took %d on %I (%r)"

Threads format placeholders for --threads (TTY monitoring only):
  %a=agent  %S=stage  %g=progress-bar  %p=percent  %e=elapsed  %E=estimate  %%=literal%
  Width: %14a (max 14 chars, right-aligned), %-14a (left-aligned)
  Default: "  [%-14a] %S %g %p %e / %E"
  Env: BUILDGIT_THREADS_FORMAT

Special diagnostics:
  `buildgit -v status --all` preserves full failed-test stack traces and captured stdout.
  `buildgit -v status --json` adds untruncated failed-test `stdout` fields.
  `buildgit status --list-stages [--json]` lists pipeline stages for one build.
  `buildgit status --console-text [stage]` prints raw build or stage console text.

Passthrough:
  buildgit log --oneline -5        # Passed through to git

Environment Variables:
  JENKINS_URL         Base URL of the Jenkins server
  JENKINS_USER_ID     Jenkins username for API authentication
  JENKINS_API_TOKEN   Jenkins API token for authentication
```

## Detailed Specifications
- see jbuildmon/specs/README.md for an overview of all existing specs
- see jbuildmon/specs/CLAUDE.md for comprehensinve spec creating, implement, state migrating rules and conventions
- all specs use this naming pattern: `jbuildmon/specs/*-spec.md`

## Changelog
- When modifying or reviewing CHANGELOG.md, always use the `changelog-maintenance` skill.

## buildgit
- see jbuildmon/CLAUDE.md for buildgit testing, changes, AI Agent skill

## Building on Jenkins CI server

- Jenkins build server is configured as a Multibranch Pipeline and builds pushed branches after scan/webhook.
- The top-level Jenkins job for this project is `ralph1` (branch jobs are sub-jobs under it, e.g. `ralph1/main`).
- JOB_NAME=ralph1
- You have env variables that represent the credentials for Jenkins.
  - JENKINS_URL
  - JENKINS_USER_ID
  - JENKINS_API_TOKEN
- These credentials give you read only access to this Jenkins job.
