# buildgit as a Portable Agent Skill
Date: 2026-02-07
References: none

## 1. Overview

Make `buildgit` a portable, model-invoked [Agent Skill](https://agentskills.io) following the open standard. This enables any Agent Skills-compatible tool (Claude Code, Cursor, Codex, Gemini CLI, etc.) to automatically discover and use `buildgit` when the user asks about CI/CD status, build results, or wants to push code and monitor the Jenkins build.

**Key properties:**
- **Portable** — same skill definition works across all supporting tools
- **Model-invoked** — the agent decides when to use it based on the description and user intent (no explicit `/slash-command` required)
- **Progressive disclosure** — lightweight metadata loaded at startup; full instructions loaded only when the skill is activated

**Prerequisite:** `buildgit` is already installed and on `$PATH`.

## 2. Skill File Structure

Install location (user-level, Claude Code convention):

```
~/.claude/skills/buildgit/
├── SKILL.md              # Main skill definition (required)
└── references/
    └── reference.md      # Full command reference (progressive disclosure)
```

The directory name `buildgit` must match the `name` field in the SKILL.md frontmatter per the Agent Skills specification.

## 3. SKILL.md Content

### Frontmatter

```yaml
---
name: buildgit
description: >-
  Jenkins CI/CD build monitor. Check build status, push and monitor builds,
  follow builds in real-time. Use when the user asks about CI/CD status,
  build results, wants to push code and monitor the Jenkins build, or asks
  if CI is passing.
compatibility: Requires bash, curl, jq, and buildgit on PATH
allowed-tools: Bash(buildgit:*)
---
```

### Body

The SKILL.md body should contain:

#### When to Use

Trigger phrases and intents that should activate this skill:
- "check build", "build status", "is CI passing", "is the build green"
- "push and watch", "push and monitor"
- "what failed in CI", "why did the build fail"
- "follow the build", "watch the build"
- "trigger a build", "run the build"

#### Prerequisites Check

Before running any command, verify:
1. `buildgit` is on PATH: `which buildgit`
2. Jenkins env vars are set: `JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN`
3. Project has `JOB_NAME=<name>` in its CLAUDE.md or AGENTS.md (for job auto-detection)

If any prerequisite fails, inform the user what's missing rather than attempting the command.

#### Command Quick Reference

| Command | Purpose |
|---------|---------|
| `buildgit status` | Git status + Jenkins build snapshot |
| `buildgit status -f` | Follow builds in real-time (Ctrl+C to stop) |
| `buildgit status --json` | Machine-readable Jenkins build status |
| `buildgit push` | Push + monitor Jenkins build until complete |
| `buildgit push --no-follow` | Push only, no build monitoring |
| `buildgit build` | Trigger a new build + monitor until complete |
| `buildgit build --no-follow` | Trigger only, no monitoring |
| `buildgit --job <name> <cmd>` | Override auto-detected job name |

#### Interpreting Output

**Exit codes:**

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success (build passed, or git command succeeded) |
| 1 | Build failed, or an error occurred |
| 2 | Build is currently in progress |

**Build states to communicate to the user:**
- `SUCCESS` — build passed, all tests green
- `FAILURE` — build failed; output includes failed stage and error details
- `BUILDING` / in-progress — build is still running
- `ABORTED` — build was manually cancelled

For failures, `buildgit` output includes the failed stage name, error logs, and test failure details. Summarize these for the user.

#### Dynamic Context

To inject live build state into the agent's context, use:

```
!`buildgit status --json 2>/dev/null`
```

This allows the agent to make decisions based on current build status without the user needing to ask.

#### Further Reference

See [references/reference.md](references/reference.md) for full command documentation, example output, and troubleshooting.

## 4. reference.md Content

Located at `references/reference.md`, this file provides full details loaded only when the agent needs deeper context.

### Contents

**Full command documentation** (from `buildgit --help`):

```
Usage: buildgit [global-options] <command> [command-options] [arguments]

Global Options:
  -j, --job <name>    Specify Jenkins job name (overrides auto-detection)
  -h, --help          Show this help message
  --verbose           Enable verbose output for debugging

Commands:
  status [-f|--follow] [--json] [git-status-options]
                      Display combined git and Jenkins build status
  push [--no-follow] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] Trigger and monitor Jenkins build
  <any-git-command>   Passed through to git
```

**Exit codes and their meanings:**

| Scenario | Exit Code |
|----------|-----------|
| Success (git OK, build OK) | 0 |
| Git command fails | Git's exit code |
| Jenkins build fails | 1 |
| Build is in progress (`status` command) | 2 |
| Nothing to push | Git's exit code |
| Jenkins unavailable during push | Non-zero (after git push completes) |

**Example output for each command:**

`buildgit status`:
```
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean

Jenkins Build Status: ralph1 #42
Result: SUCCESS
```

`buildgit status --json`:
```
On branch main
...

{"result":"SUCCESS","building":false,"number":42,"url":"http://jenkins:8080/job/ralph1/42/", ...}
```

`buildgit status -f`:
```
[git status output]

Monitoring build ralph1 #42...
Stage: Build        ✓ (3s)
Stage: Test         ✓ (12s)
Stage: Deploy       RUNNING...
...
Build #42: SUCCESS

Waiting for next build of ralph1...
```

`buildgit push`:
```
[git push output]

Monitoring build ralph1 #43...
Stage: Build        ✓ (3s)
Stage: Test         ✓ (12s)
Build #43: SUCCESS
```

**Troubleshooting:**

| Problem | Cause | Fix |
|---------|-------|-----|
| "Jenkins credentials not configured" | Missing env vars | Set `JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN` |
| "Could not determine job name" | No `JOB_NAME` in CLAUDE.md and auto-detection failed | Add `JOB_NAME=<name>` to project CLAUDE.md or use `--job` flag |
| "Connection refused" | Jenkins server unreachable | Verify `JENKINS_URL` is correct and server is running |
| Build monitoring hangs | Network issue or build stuck | Ctrl+C to stop, check Jenkins web UI |

## 5. Per-Project Configuration Convention

Each project that uses the buildgit skill must declare its Jenkins job name so the agent (and `buildgit` auto-detection) can find it.

### Required

Add to the project's `CLAUDE.md` or `AGENTS.md`:

```markdown
## Jenkins CI

- JOB_NAME=<your-jenkins-job-name>
```

### Required Environment Variables

These must be set in the user's shell environment (not per-project):

| Variable | Description |
|----------|-------------|
| `JENKINS_URL` | Base URL of the Jenkins server (e.g., `http://jenkins.example.com:8080`) |
| `JENKINS_USER_ID` | Jenkins username for API authentication |
| `JENKINS_API_TOKEN` | Jenkins API token (generate from Jenkins user settings) |

### Template Snippet for Project CLAUDE.md

```markdown
## Building on Jenkins CI server

- Jenkins build server will build automatically on a git push to origin main
- JOB_NAME=my-project
- You have env variables that represent the credentials for Jenkins:
  - JENKINS_URL
  - JENKINS_USER_ID
  - JENKINS_API_TOKEN
```

## 6. Cross-Tool Portability

The Agent Skills standard is supported by multiple tools. The SKILL.md format is identical across tools; only the installation directory differs.

| Tool | Skill Directory |
|------|----------------|
| Claude Code | `~/.claude/skills/buildgit/` |
| Cursor | `.cursor/skills/buildgit/` (per-project) or `~/.cursor/skills/buildgit/` (user-level) |
| Other Agent Skills-compatible tools | Follow each tool's skill discovery path; the SKILL.md format is the same |

**Notes:**
- The SKILL.md file is identical regardless of which tool loads it
- Each tool may have different conventions for user-level vs. project-level skill directories
- Some tools support `allowed-tools` for pre-approving tool usage; others may ignore it
- The `compatibility` field helps tools decide if the skill is relevant to their environment

## 7. Cleanup

### Replace outdated jbuildmon/SKILL.md

The current `jbuildmon/SKILL.md` references the deleted `jenkins-build-monitor.sh` script and an outdated workflow. Replace its contents with a pointer to the new skill:

```markdown
---
name: buildgit
description: >-
  This skill has moved. See ~/.claude/skills/buildgit/SKILL.md for the
  current Agent Skills-standard skill definition.
---

# buildgit skill — moved

This skill definition is outdated. The canonical version follows the
[Agent Skills](https://agentskills.io) open standard and is installed at:

    ~/.claude/skills/buildgit/SKILL.md

See `jbuildmon/specs/buildgit-skill-spec.md` for the full specification.
```

### Remove outdated .cursor/skills/checkbuild/SKILL.md

The file `jbuildmon/.cursor/skills/checkbuild/SKILL.md` references the deleted `checkbuild.sh` script. Delete this file and its parent directory.

## 8. Verification

After installation, verify the skill works end-to-end:

1. **Command availability:** `buildgit --help` works from any directory (confirms it's on PATH)
2. **Skill discovery:** In Claude Code, ask "What skills are available?" — buildgit should appear in the list with its description
3. **Model invocation:** From a project with `JOB_NAME` in its CLAUDE.md, ask "check build status" — the agent should invoke `buildgit status` without being explicitly told which tool to use
4. **Cross-project:** From a different project (not ralph1) that has `JOB_NAME` configured, ask "is CI passing" — the agent should use buildgit
5. **Prerequisite detection:** From a project without `JOB_NAME`, ask "check build" — the agent should report the missing configuration rather than failing silently
