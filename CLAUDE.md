# Agent Instructions (CLAUDE.md / AGENTS.md) 

This file provides guidance to Claude Code (claude.ai/code) and other agents like Cursor when working with code in this repository.

## Project Overview

This repository contains **jbuildmon** (Jenkins Build Monitor), a CLI tool that automates the developer workflow of committing code, pushing to a remote repository, and monitoring the resulting Jenkins CI/CD build until completion.

The canonical location of the buildgit script is `jbuildmon/skill/buildgit/scripts/buildgit`.
A symlink at `jbuildmon/buildgit` preserves backward compatibility.

Execute this tool with:  ./jbuildmon/buildgit

```bash
$ ./jbuildmon/buildgit --help
Usage: buildgit [global-options] <command> [command-options] [arguments]

A unified interface for git operations with Jenkins CI/CD integration.

Global Options:
  -j, --job <name>               Specify Jenkins job name (overrides auto-detection)
  -c, --console <mode>           Show console log output (auto or line count)
  -h, --help                     Show this help message
  --verbose                      Enable verbose output for debugging

Commands:
  status [build#] [-f|--follow] [--json]
                      Display Jenkins build status (latest or specific build)
  push [--no-follow] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] Trigger and monitor Jenkins build
  <any-git-command>   Passed through to git

Examples:
  buildgit status              # Jenkins build status snapshot
  buildgit status 31           # Status of build #31
  buildgit status -f           # Follow builds indefinitely
  buildgit status --json       # JSON format for Jenkins status
  buildgit push                # Push + monitor build
  buildgit push --no-follow    # Push only, no monitoring
  buildgit --job myjob build   # Trigger build for specific job
  buildgit log --oneline -5    # Passed through to git

Environment Variables:
  JENKINS_URL         Base URL of the Jenkins server
  JENKINS_USER_ID     Jenkins username for API authentication
  JENKINS_API_TOKEN   Jenkins API token for authentication
```

## Detailed Specifications
- see jbuildmon/specs/README.md for an overview of all existing specs
- see jbuildmon/specs/CLAUDE.md for comprehensinve spec creating, migrating rules and conventions
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
