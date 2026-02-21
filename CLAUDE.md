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
  -j, --job <name>               Specify Jenkins job name (overrides auto-detection)
  -c, --console <mode>           Show console log output (auto or line count)
  -h, --help                     Show this help message
  -v, --verbose                  Enable verbose output for debugging

Commands:
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests]
                      Display Jenkins build status (latest or specific build)
                      build# can be absolute (31) or relative (0=latest, -1=previous, -2=two ago)
                      Default: full output on TTY, one-line on pipe/redirect
  push [--no-follow] [--line] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] [--line]
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
  buildgit status --all | less     # Full status piped to pager
  buildgit push --no-follow        # Push only, no monitoring

Monitor ongoing Jenkins build jobs:
  buildgit status -f               # Follow builds indefinitely
  buildgit status -f --once        # Follow current/next build, exit when done (10s timeout)
  buildgit status -f --once=20     # Same, but wait up to 20 seconds for build to start
  buildgit status -n 3 -f          # Show 3 prior builds, then follow indefinitely
  buildgit status -n 3 -f --once   # Show 3 prior builds, then follow once with timeout
  buildgit status -f --line        # Follow builds with one-line output + progress bar (TTY only)
  buildgit status -f --once --line # Follow one build in one-line mode, then exit
  buildgit status -n 5 -f --line   # Show 5 prior one-line rows, then follow in one-line mode
  buildgit push                    # Push + monitor build
  buildgit push --line             # Push + compact one-line monitoring with progress bar
  buildgit build --line            # Trigger + compact one-line monitoring with progress bar
  buildgit --job myjob build       # Trigger build for specific job

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

## buildgit
- see jbuildmon/CLAUDE.md for buildgit testing, changes, AI Agent skill

## Building on Jenkins CI server

- Jenkins build server will build automatically on a git push to origin main
- There is one Jenkins pipeline job for this project, defined in ./Jenkinsfile.
- JOB_NAME=ralph1
- You have env variables that represent the credentials for Jenkins.
  - JENKINS_URL
  - JENKINS_USER_ID
  - JENKINS_API_TOKEN
- These credentials give you read only access to this Jenkins job.
