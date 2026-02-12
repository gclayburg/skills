# buildgit

A CLI tool that lets you push code and see if the Jenkins build passed — without ever leaving your terminal. Built for humans on the command line and AI agents alike.

## The Problem

Every developer knows this workflow:

1. `git push`
2. Open Jenkins in a browser
3. Stare at the build page, hitting refresh
4. Eventually find out the build failed 4 minutes ago because of a missing semicolon

**buildgit** collapses all of that into one command. Push your code, and it monitors the Jenkins build right in your terminal until it passes or fails. When the build succeeds, you see a clean summary. When it fails, you see exactly what went wrong — the failed stage, the error, the failing tests — without wading through hundreds of lines of console log.

## The Workflow

```
# 1. Make your changes
vim src/app.js

# 2. Commit
git commit -am "fix auth timeout"

# 3. Push and watch
buildgit push
```

That's it. Step 3 pushes your code, picks up the Jenkins build, and streams the result:

```
$ buildgit push
Enumerating objects: 5, done.
Writing objects: 100% (3/3), 312 bytes | 312.00 KiB/s, done.
To github.com:user/myproject.git
   a1b2c3d..e4f5g6h  main -> main

Monitoring build myproject #42...
Stage: Initialize      ✓ (2s)
Stage: Build           ✓ (3s)
Stage: Unit Tests      ✓ (12s)
Stage: Deploy          ✓ (1s)
Build #42: SUCCESS
```

When something breaks, you see only what matters:

```
Stage: Unit Tests      FAILED (8s)

FAILED TESTS:
  - com.example.AuthTest.testLoginExpired
  - com.example.AuthTest.testTokenRefresh

Error: 2 test(s) failed
Build #43: FAILURE
```

No scrolling through a full console log. buildgit filters out the noise and shows you the details you need to fix the problem.

## For Humans and Agents

buildgit is designed for two audiences:

**Humans** use it on the command line. Push code, see results, fix failures — all without leaving the terminal.

**AI agents** (Claude Code, Cursor, Codex, Gemini CLI, etc.) use it as an [Agent Skill](https://agentskills.io). When you tell your agent "push this and watch the build" or "is CI green?", it invokes buildgit automatically. Because the output is concise — just stages, results, and failures — the agent gets the signal it needs without burning context on a massive console log. The agent can then immediately act on failures: read the error, fix the code, and push again.

## Install

### As an Agent Skill

Install buildgit so your AI coding agent can discover and use it automatically:

```bash
npx skills add https://github.com/gclayburg/skills --skill buildgit
```

Once installed, any Agent Skills-compatible tool (Claude Code, Cursor, etc.) will pick it up. Ask your agent "is the build passing?" and it just works.

### Manual install

Clone the repo and add the script to your PATH:

```bash
git clone https://github.com/gclayburg/skills.git
export PATH="$PATH:$(pwd)/skills/jbuildmon/skill/buildgit/scripts"
```

### Prerequisites

buildgit sits on top of an existing git + Jenkins setup. You'll need:

- **bash**, **curl**, **jq**
- **Git** for your project, with a remote repository
- **Jenkins** with a **Pipeline** job for your project (freestyle jobs are not supported)
- **Automatic build triggers** — your git remote must be configured to trigger a Jenkins build on every push (e.g. via a webhook, a git post-receive hook, or a Jenkins plugin like GitHub Branch Source). buildgit monitors builds; it doesn't create the link between your repo and Jenkins.

### Jenkins user setup

buildgit needs a Jenkins user with read and build permissions. It does **not** need any administrative access. The minimum required permissions are:

- **Overall/Read** — connect to Jenkins
- **Job/Read** — view job and build details
- **Job/Build** — trigger new builds (only needed for `buildgit build`)

The user does not need permissions to create, delete, configure, or administer jobs or Jenkins itself. A role with just these permissions keeps the attack surface small.

### Jenkins credentials

Once you have a Jenkins user, generate an API token and set these environment variables (e.g. in your `~/.bashrc` or `~/.zshrc`):

```bash
export JENKINS_URL="https://jenkins.example.com"
export JENKINS_USER_ID="your-username"
export JENKINS_API_TOKEN="your-api-token"
```

To generate an API token: Jenkins > your user > Configure > API Token > Add new Token.


## Usage

### Push and monitor

The core workflow — push your commits and watch the build:

```bash
buildgit push
```

Just want to push without waiting?

```bash
buildgit push --no-follow
```

### Check build status

See the current state of the latest build:

```bash
buildgit status
```

Follow builds in real-time (stays open and watches for new builds):

```bash
buildgit status -f
```

Get machine-readable output for scripting or agent consumption:

```bash
buildgit status --json
```

### Trigger a build

Kick off a build without pushing (like hitting "Build Now" in Jenkins):

```bash
buildgit build
```

### Git passthrough

Any command buildgit doesn't recognize gets passed straight to `git`:

```bash
buildgit log --oneline -5
buildgit diff HEAD~1
buildgit checkout -b feature
```

### Multiple projects

buildgit auto-detects the Jenkins job name from your project configuration. Override it with `--job`:

```bash
buildgit --job other-project status
```

## Per-Project Setup

Add the Jenkins job name to your project's root `CLAUDE.md` or `AGENTS.md`:

```markdown
## Jenkins CI
- JOB_NAME=my-project
```

This lets both buildgit and your AI agent find the right Jenkins job automatically.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `buildgit push` | Push + monitor build |
| `buildgit push --no-follow` | Push only |
| `buildgit status` | Build status snapshot |
| `buildgit status -f` | Follow builds in real-time |
| `buildgit status --json` | JSON output |
| `buildgit build` | Trigger + monitor build |
| `buildgit build --no-follow` | Trigger only |
| `buildgit --job NAME CMD` | Override job name |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success — build passed |
| 1 | Failure — build failed or error occurred |
| 2 | Build is in progress |

## License

MIT
