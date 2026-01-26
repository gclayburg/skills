---
name: jbuildmon
description: git commit staged code, push to origin and monitor Jenkins build
---

# jbuildmon

Commits staged code, pushes to origin, and monitors the Jenkins build until completion.

## Usage

```bash
path/to/jenkins-build-monitor.sh <job-name> "<commit-message>"
```

## Agent Instructions

### Finding the Job Name

Before using this skill, determine the correct Jenkins job name:

1. **Check AGENTS.md** - Look for a "Jenkins CI/CD" or "Jenkins Jobs" section that documents the job names for this repository
2. **Ask the user** if no job documentation is found

### Example Agent Workflow

When a user requests to commit and monitor a build:

1. Read `AGENTS.md` in the repository root
2. Search for "Jenkins CI/CD", "Jenkins Jobs", or similar headings
3. Extract the appropriate job name from the table/list
4. Call the script with the job name and commit message

### Documentation Convention

Repositories using this skill should document their Jenkins jobs in `AGENTS.md`:

```markdown
## Jenkins CI/CD

| Job Name | Trigger | Description |
|----------|---------|-------------|
| `my-project-build` | All changes | Main build pipeline |
| `my-project-test` | All changes | Test pipeline |
```

## Environment Variables (Required)

The following environment variables must be set:

- `JENKINS_URL` - Jenkins server URL (e.g., `http://jenkins.example.com:8080`)
- `JENKINS_USER_ID` - Jenkins username
- `JENKINS_API_TOKEN` - Jenkins API token (generate from Jenkins user settings)

## What This Skill Does

1. **Commits** all staged changes with the provided commit message
2. **Pushes** the commit to `origin/main` (handles rebasing if needed)
3. **Waits** for the Jenkins build to start (up to 2 minutes)
4. **Monitors** the build progress, showing current stage information
5. **Reports** the final result:
   - On **success**: Shows build number and URL
   - On **failure**: Extracts and displays the failed stage logs

## Installation in Other Repositories

To use this skill in a different repository:

1. Copy the `.cursor/skills/jbuildmon/` folder to the target repository
2. Add a "Jenkins CI/CD" section to `AGENTS.md` documenting the job names
3. Ensure the required environment variables are set
4. The skill is now ready to use - no modifications needed!
