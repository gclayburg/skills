# AGENTS.md  CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) amd other agents like Cursor when working with code in this repository.

## Project Overview

This repository contains **jbuildmon** (Jenkins Build Monitor), a CLI tool that automates the developer workflow of committing code, pushing to a remote repository, and monitoring the resulting Jenkins CI/CD build until completion.

## Detailed Specifications
- see jbuildmon/specs/README.md for an overview of all specs
- all specs use this naming pattern: jbuildmon/specs/*-spec.md

## Building on Jenkins CI server

- Jenkins build server will build automatically on a git push to origin main
- There is one Jenkins pipeline job for this project, defined in ./Jenkinsfile.
- JOB_NAME=ralph1
- You have env variables that represent the credentials for Jenkins.
  - JENKINS_URL
  - JENKINS_USER_ID
  - JENKINS_API_TOKEN
- These credentials give you read only access to this Jenkins job.
