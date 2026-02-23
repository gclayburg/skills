
# Prerequisites

`buildgit` sits on top of an existing git + Jenkins setup. You'll need:

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

### Project setup

Add the Jenkins job name to your project's root `CLAUDE.md` or `AGENTS.md`:

```markdown
## Jenkins CI
- JOB_NAME=my-project
```

This lets buildgit match your project to the Jenkins job automatically.

To override this inferred jobname, override it with `--job`:

```bash
buildgit --job jenkins-job-name status
```
