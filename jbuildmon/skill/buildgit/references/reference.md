# buildgit — Real-World Examples

## Setup requirements

buildgit assumes:

1. Your project is a git project
2. A git push will automatically trigger a build in a Jenkins CI/CD system.
3. The Jenkins job is setup as a pipeline job. Other types of jobs have not been tested.
4. You have a Jenkins user with read/build permissions. It does not need to be an administrator.
5. There are no network/sandbox restrictions to access your Jenkins server.

## Push and monitor a build (with failure output)

If any failures are detected in the build, any tests, or any build pipeline stage, buildgit attempts to show you what failed. It does not fill the output with meaningless log data.
Humans don't need this most of the time. They just need to know what failed. Agents care about the same thing. They don't need their context window filled with useless logs.

Monitoring commands now include a preamble before active monitoring:

```bash
[10:23:48] ℹ Waiting for Jenkins build ralph1 to start...
[10:23:48] ℹ Prior 3 Jobs
SUCCESS     #54 id=6685a31 Tests=19/0/0 Took 5m 38s on 2026-02-22T22:37:21-0700 (4 days ago)
SUCCESS     #55 id=46f85cb Tests=19/0/0 Took 5m 40s on 2026-02-23T00:10:00-0700 (4 days ago)
SUCCESS     #56 id=0046c54 Tests=19/0/0 Took 6m 39s on 2026-02-24T10:14:10-0700 (3 days ago)
[10:23:48] ℹ Estimated build time = 6m 39s
[10:23:58] ℹ Starting
```

Use `--prior-jobs 0` to suppress the prior-jobs block.

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

## Custom format string (--format)

```bash
$ buildgit status --format '%s #%n %c'
SUCCESS     #55 9b9d481

$ buildgit status --format '%s Job %j #%n commit=%c branch=%b'
SUCCESS     Job phandlemono-IT #55 commit=9b9d481 branch=main

$ buildgit status -n 3 --format '%s #%n %d'
FAILURE     #53 3m 41s
SUCCESS     #54 5m 40s
SUCCESS     #55 5m 38s
```

Format placeholders: `%s`=status `%j`=job `%n`=build# `%t`=tests `%d`=duration `%D`=date `%I`=iso8601 `%r`=relative `%c`=commit `%b`=branch `%%`=literal%
Default line format: `%s #%n id=%c Tests=%t Took %d on %I (%r)`

## Show status for last N builds (--line)

```bash
$ buildgit status --line -n 5
FAILURE     #34 id=09a1b2c Tests=?/?/? Took 3m 41s on 2026-02-14T09:41:10-0700 (6 days ago)
FAILURE     #35 id=1bc2d3e Tests=?/?/? Took 3m 27s on 2026-02-14T09:52:58-0700 (6 days ago)
NOT_BUILT   #36 id=2cd3e4f Tests=?/?/? Took 3m 52s on 2026-02-16T11:07:44-0700 (4 days ago)
SUCCESS     #37 id=3de4f5a Tests=19/0/0 Took 5m 41s on 2026-02-16T12:26:03-0700 (4 days ago)
SUCCESS     #38 id=4ef5a6b Tests=19/0/0 Took 5m 32s on 2026-02-17T08:14:52-0700 (3 days ago)
```

## Show one relative build

```bash
$ buildgit status -2
# Shows exactly one build: two builds before the latest
```

## Show last N builds in full or JSONL mode

```bash
$ buildgit status -n 3
# Prints 3 full build reports, oldest first

$ buildgit status -n 3 --json
{"job":"phandlemono-IT","build":{"number":36,...}}
{"job":"phandlemono-IT","build":{"number":37,...}}
{"job":"phandlemono-IT","build":{"number":38,...}}
```

## Show last N builds then follow (--line -f)

```bash
$ buildgit status --line -n 5 -f
FAILURE     #34 id=09a1b2c Tests=?/?/? Took 3m 41s on 2026-02-14T09:41:10-0700 (6 days ago)
FAILURE     #35 id=1bc2d3e Tests=?/?/? Took 3m 27s on 2026-02-14T09:52:58-0700 (6 days ago)
NOT_BUILT   #36 id=2cd3e4f Tests=?/?/? Took 3m 52s on 2026-02-16T11:07:44-0700 (4 days ago)
SUCCESS     #37 id=3de4f5a Tests=19/0/0 Took 5m 41s on 2026-02-16T12:26:03-0700 (4 days ago)
SUCCESS     #38 id=4ef5a6b Tests=19/0/0 Took 5m 32s on 2026-02-17T08:14:52-0700 (3 days ago)
IN_PROGRESS Job phandlemono-IT #39 [>                   ] 1% 5s / ~5m 32s
```

## Full status output for a successful build

```bash
$ buildgit status

╔════════════════════════════════════════╗
║           BUILD SUCCESSFUL             ║
╚════════════════════════════════════════╝

Job:        phandlemono-IT
Build:      #39
Status:     SUCCESS
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     4ae2fc1 - "fix: resolve port 9222 conflict and remove deliberate build failures"
            ✓ Your commit (HEAD)
Started:    2026-02-20 20:23:56

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/39/console

[09:00:08] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[09:00:08] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[09:00:08] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Checkout (<1s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Check for Relevant Changes (<1s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Clean (<1s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Setup (8s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Build (13s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Test (2s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->TestContainers IT (21s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Playwright e2e IT (1m 14s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Coverage (2s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Package (1m 40s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Archive Artifacts (8s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Post Actions (<1s)
[09:00:08] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle (4m 5s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Declarative: Checkout SCM (<1s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Checkout (<1s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Check for Relevant Changes (<1s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Artifactory configuration (<1s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->System Diagnostics (2s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Docker Diagnostics (4s)
[09:00:08] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->main build (1m 4s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Docker Build (25s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Docker Push (13s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Deploy registerdemo (19s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Publish to Artifactory (37s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Archive Artifacts (41s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Publish build info (<1s)
[09:00:09] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Declarative: Post Actions (2s)
[09:00:09] ℹ   Stage:   ║2 [agent8_sixcore] Build SignalBoot (3m 44s)
[09:00:09] ℹ   Stage: [agent8_sixcore] Trigger Component Builds (4m 5s)
[09:00:09] ℹ   Stage: [agent8_sixcore] Verify Docker Images (6s)
[09:00:09] ℹ   Stage: [agent8_sixcore] Setup Handle (19s)
[09:00:09] ℹ   Stage: [agent8_sixcore] Integration Tests (22s)
[09:00:09] ℹ   Stage: [agent8_sixcore] E2E Tests (1m 14s)
[09:00:09] ℹ   Stage: [agent8_sixcore] Declarative: Post Actions (<1s)

=== Test Results ===
  Total: 19 | Passed: 19 | Failed: 0 | Skipped: 0
====================

Finished: SUCCESS
[09:00:09] ℹ Duration: 6m 13s
```

## Full status — build in progress (-f)

```bash
$ buildgit status -f

[09:02:13] ℹ Waiting for next build of phandlemono-IT...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job phandlemono-IT #40 has been running for unknown

Job:        phandlemono-IT
Build:      #40
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Commit:     4ae2fc1 - "fix: resolve port 9222 conflict and remove deliberate build failures"
            ✓ Your commit (HEAD)
Started:    2026-02-21 09:02:43

=== Build Info ===
  Started by:  Ralph AI Read Only
  Agent:       agent8_sixcore
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/phandlemono.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/phandlemono-IT/40/console
[09:02:49] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
[09:02:49] ℹ   Stage: [agent8_sixcore] Checkout (<1s)
[09:02:49] ℹ   Stage: [agent8_sixcore] Analyze Component Changes (<1s)
[09:03:01] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Declarative: Checkout SCM (<1s)
[09:03:07] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Checkout (<1s)
[09:03:07] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Check for Relevant Changes (<1s)
[09:03:07] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Clean (<1s)
[09:03:07] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Declarative: Checkout SCM (<1s)
[09:03:07] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Checkout (<1s)
[09:03:07] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Check for Relevant Changes (<1s)
[09:03:07] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Artifactory configuration (<1s)
[09:03:13] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->System Diagnostics (2s)
[09:03:13] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Docker Diagnostics (3s)
[09:03:19] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Setup (9s)
[09:03:26] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Build (12s)
[09:03:33] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->Test (2s)
[09:03:53] ℹ   Stage:   ║1 [agent8_sixcore] Build Handle->TestContainers IT (21s)
[09:04:20] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->main build (1m 2s)
[09:04:35] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Docker Build (20s)
[09:04:49] ℹ   Stage:   ║2 [agent7        ] Build SignalBoot->Docker Push (8s)
IN_PROGRESS Job phandlemono-IT #40 [======>             ] 35% 2m 12s / ~6m 13s
```
