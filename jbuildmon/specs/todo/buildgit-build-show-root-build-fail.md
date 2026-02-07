He have a new problem if the build fails at an early state, i.e. it fails before any stage in the pipeline is executed.  If the build fails early, all these commands, must be able to see it and display the cause of the failure:
- buildgit push
- buildgit status -f 
- buildgit build


Here is the what is seen on the console:

```bash
$ buildgit push
To ssh://scranton2:2233/home/git/ralph1.git
   bf2b860..d84788e  main -> main
[10:50:35] ℹ Verifying Jenkins connectivity...
[10:50:35] ✓ Connected to Jenkins
[10:50:35] ℹ Verifying job 'ralph1' exists...
[10:50:35] ✓ Job 'ralph1' found

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #103
Status:     BUILDING
Trigger:    Automated (git push)
Commit:     unknown
            ✗ Unknown commit
Started:    2026-02-07 10:50:42
Elapsed:    3s

=== Build Info ===
  Started by:  buildtriggerdude
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/103/console



Finished: FAILURE
```

This is not enough context to show the user.  If I browse the jenkins UI manually, I see the complete console log which is informative:

```
Started by user buildtriggerdude
Obtained Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
org.codehaus.groovy.control.MultipleCompilationErrorsException: startup failed:
WorkflowScript: 3: Too many arguments for map key "node" @ line 3, column 9.
           node('fastnode') {
           ^

1 error

	at org.codehaus.groovy.control.ErrorCollector.failIfErrors(ErrorCollector.java:309)
	at org.codehaus.groovy.control.CompilationUnit.applyToPrimaryClassNodes(CompilationUnit.java:1107)
	at org.codehaus.groovy.control.CompilationUnit.doPhaseOperation(CompilationUnit.java:624)
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
```

We need to fix this so any of our tools that monitor an ongoing build will see the failure.


# buildgit status fail

A related bug is that 'buildgit status' also does not show enough of the console log to be useful.  It tries to show something, but it is not good enough.  We need to be consistent in what log information is shown whether we are looking at a build live, or we are looking at an old build like 'buildgit status' does.  This needs to be consistent, i.e. we are sharing the same code betwee nall these entrypoints.

