The output is not quite correct yet.  I see  Build Info twice.  And Console: twice.  Also, I do not see anything with the 'Commit' information.

specs/todo/bug2026-02-13-build-monitoring-header-spec.md

```bash
$ buildgit build
[11:03:40] ℹ Waiting for Jenkins build ralph1 to start...

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job:        ralph1
Build:      #162
Status:     BUILDING
Trigger:    Manual (started by Ralph AI Read Only)
Started:    2026-02-13 11:03:45

=== Build Info ===
  Started by:  Ralph AI Read Only
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/162/console


=== Build Info ===
  Started by:  Ralph AI Read Only
  Pipeline:    Jenkinsfile from git ssh://git@scranton2:2233/home/git/ralph1.git
==================

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/162/console
[11:03:52] ℹ   Stage: [agent8_sixcore] Declarative: Checkout SCM (<1s)
```