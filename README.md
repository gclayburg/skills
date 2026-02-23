

# buildgit

A CLI tool that lets you push code and see if the Jenkins build passed — without ever leaving your terminal. Built for humans on the command line and AI agents alike.

## The Problem

Every developer knows this workflow:

1. `git push`
2. Open Jenkins in a browser
3. Stare at the build page, hitting refresh
4. Click on 47 things only to eventually find out the build failed 4 minutes ago because of a missing semicolon

**buildgit** collapses all of that into one command. Push your code, and it monitors the Jenkins build right in your terminal until it passes or fails. When the build succeeds, you see a clean summary. When it fails, you see exactly what went wrong — the failed stage, the error, the failing tests — without wading through hundreds of lines of console log.

## The Workflow

The workflow is simple.  Make some changes to a file, commit it, and push with `buildgit`.
That's it. `buildgit` pushes your code, detectes the Jenkins build job starting, and streams the result to the terminal.  IN_PROGRESS banner is shown when running on a tty.

```bash
$ vim src/app.js
$ git commit -am "fix auth timeout"
$ buildgit push scranton
To ssh://scranton2.garyclayburg.com:2233/home/git/upbanner.git
   51bb15e..06af8bd  master -> master
[13:11:27] ℹ Waiting for Jenkins build upbanner to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        upbanner
Build:      #158
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     06af8bd - "fix with timeout"
            ✓ Your commit (HEAD)
Started:    2026-02-21 13:11:34

=== Build Info ===
  Started by:  buildtriggerdude
  Agent:       agent1paton
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/upbanner.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/upbanner/158/console

[13:11:38] ℹ   Stage: [agent1paton   ] Declarative: Checkout SCM (2s)
[13:11:43] ℹ   Stage: [agent1paton   ] Artifactory configuration (2s)
IN_PROGRESS Job upbanner #158 [=>                  ] 10% 19s / ~3m 5s
```

You'll see the basics about the build, along with build pipeline stages as they are finished.
The IN_PROGRESS indicator shows as long as the build is running.

At the completion you'll see the final message:

```bash
...
[13:11:38] ℹ   Stage: [agent1paton   ] Declarative: Checkout SCM (2s)
[13:11:43] ℹ   Stage: [agent1paton   ] Artifactory configuration (2s)
[13:14:37] ℹ   Stage: [agent1paton   ] main build (2m 52s)
[13:14:37] ℹ   Stage: [agent1paton   ] Publish build info (2s)
[13:14:37] ℹ   Stage: [agent1paton   ] Declarative: Post Actions (<1s)


=== Test Results ===
  Total: 52 | Passed: 52 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[13:14:47] ℹ Duration: 3m 2s
```

If there was an error, you'll get more detail about what went wrong.  compile?  build? test? something else?
Here is one that failed with a bad Jenkinsfile:

```bash
$ buildgit push
To ssh://scranton2:2233/home/git/phandlemono.git
   4ae2fc1..039301d  main -> main
[09:13:35] ℹ Waiting for Jenkins build phandlemono-IT to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #41
Status:     BUILDING
Trigger:    Automated (git push)
Started:    2026-02-21 09:13:43

=== Build Info ===
  Started by:  buildtriggerdude
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/41/console



=== Console Output ===
Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
WorkflowScript: 59: expecting ')', found 'eSet' @ line 59, column 45.
             for (entry in chang eSet.items
                                 ^

1 error

        at org.codehaus.groovy.control.ErrorCollector.failIfErrors(ErrorCollector.java:309)
        at org.codehaus.groovy.control.ErrorCollector.addFatalError(ErrorCollector.java:149)
        at org.codehaus.groovy.control.ErrorCollector.addError(ErrorCollector.java:119)
        at org.codehaus.groovy.control.ErrorCollector.addError(ErrorCollector.java:131)
        at org.codehaus.groovy.control.SourceUnit.addError(SourceUnit.java:349)
        at org.codehaus.groovy.antlr.AntlrParserPlugin.transformCSTIntoAST(AntlrParserPlugin.java:225)
        at org.codehaus.groovy.antlr.AntlrParserPlugin.parseCST(AntlrParserPlugin.java:191)
        at org.codehaus.groovy.control.SourceUnit.parse(SourceUnit.java:233)
        at org.codehaus.groovy.control.CompilationUnit$1.call(CompilationUnit.java:189)
        at org.codehaus.groovy.control.CompilationUnit.applyToSourceUnits(CompilationUnit.java:966)
        at org.codehaus.groovy.control.CompilationUnit.doPhaseOperation(CompilationUnit.java:626)
        at org.codehaus.groovy.control.CompilationUnit.processPhaseOperations(CompilationUnit.java:602)
        at org.codehaus.groovy.control.CompilationUnit.compile(CompilationUnit.java:579)
        at groovy.lang.GroovyClassLoader.doParseClass(GroovyClassLoader.java:323)
        at groovy.lang.GroovyClassLoader.parseClass(GroovyClassLoader.java:293)
        at PluginClassLoader for script-security//org.jenkinsci.plugins.scriptsecurity.sandbox.groovy.GroovySandbox$Scope.parse(GroovySandbox.java:162)
        at PluginClassLoader for workflow-cps//org.jenkinsci.plugins.workflow.cps.CpsGroovyShell.doParse(CpsGroovyShell.java:188)
        at PluginClassLoader for workflow-cps//org.jenkinsci.plugins.workflow.cps.CpsGroovyShell.reparse(CpsGroovyShell.java:173)
        at PluginClassLoader for workflow-cps//org.jenkinsci.plugins.workflow.cps.CpsFlowExecution.parseScript(CpsFlowExecution.java:653)
        at PluginClassLoader for workflow-cps//org.jenkinsci.plugins.workflow.cps.CpsFlowExecution.start(CpsFlowExecution.java:599)
        at PluginClassLoader for workflow-job//org.jenkinsci.plugins.workflow.job.WorkflowRun.run(WorkflowRun.java:341)
        at hudson.model.ResourceController.execute(ResourceController.java:101)
        at hudson.model.Executor.run(Executor.java:454)
[Checks API] No suitable checks publisher found.
Finished: FAILURE
======================

Finished: FAILURE
[09:13:48] ℹ Duration: 0s
```

When something breaks, you see only what matters.

No scrolling through a full console log. `buildgit` filters out the noise and shows you the details you need to fix the problem.
**Note**: This part is an overall goal, not yet completed.  Got an idea to make this better?  PR's are welcome!

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

### Setup

See[jbuildmon/skill/buildgit/references/buildgit-setup.md](jbuildmon/skill/buildgit/references/buildgit-setup.md)

### Real-world output examples

See [jbuildmon/skill/buildgit/references/reference.md](jbuildmon/skill/buildgit/references/reference.md)
for full examples: push with failure, parallel pipeline stages, progress bars, and live follow mode.

# Usage

```bash
$ buildgit --help
Usage: buildgit [global-options] <command> [command-options] [arguments]

A unified interface for git operations with Jenkins CI/CD integration.

Global Options:
  -j, --job <name>               Specify Jenkins job name (overrides auto-detection)
  -c, --console <mode>           Show console log output (auto or line count)
  -h, --help                     Show this help message
  -v, --verbose                  Enable verbose output for debugging
  --version                      Show version number and exit

Commands:
  status [build#] [-f|--follow] [--once[=N]] [-n <count>] [--json] [--line] [--all] [--no-tests] [--format <fmt>]
                      Display Jenkins build status (latest or specific build)
                      build# can be absolute (31) or relative (0=latest, -1=previous, -2=two ago)
                      Default: full output on TTY, one-line on pipe/redirect
  push [--no-follow] [--line] [--format <fmt>] [git-push-options] [remote] [branch]
                      Push commits and monitor Jenkins build
  build [--no-follow] [--line] [--format <fmt>]
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

Format placeholders for --format (use with --line):
  %s=status  %j=job  %n=build#  %t=tests  %d=duration
  %D=date  %I=iso8601  %r=relative  %c=commit  %b=branch  %%=literal%
  Default: "%s Job %j #%n Tests=%t Took %d on %D (%r)"

Passthrough:
  buildgit log --oneline -5        # Passed through to git

Environment Variables:
  JENKINS_URL         Base URL of the Jenkins server
  JENKINS_USER_ID     Jenkins username for API authentication
  JENKINS_API_TOKEN   Jenkins API token for authentication
 ```

## License

MIT

## Developing

This project uses bats-core for testing.  It must be installed as a git submodule to run the tests:

```bash
$ git submodule update --init --recursive
```

Contributions are welcome.
