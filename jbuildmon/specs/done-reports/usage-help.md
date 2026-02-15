I see this when I use an unknown option:

```bash
$ buildgit status -h
[09:59:45] ✗ Unknown option for status command: -h

1 2261 0 [02-15 09:59:45] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit status -junk
[10:00:03] ✗ Unknown option for status command: -junk

1 2262 0 [02-15 10:00:03] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit status --help
[10:00:07] ✗ Unknown option for status command: --help

1 2263 0 [02-15 10:00:07] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit -garbage
[10:00:15] ✗ Unknown global option: -garbage

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

1 2264 0 [02-15 10:00:15] ED25519 :0.0 gclaybur@Garys-Mac-mini (main) ~/dev/ralph1/jbuildmon
$ buildgit status 234
[10:00:36] ✗ Build #234 not found for job 'ralph1'
```

Any time an unknown option is presented or it is invalid in any way, we need toshow the brief error message like we do today,but we also need to show the full Usage page to help the user use the correct option.
