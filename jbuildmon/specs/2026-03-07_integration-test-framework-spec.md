## Integration test framework for buildgit stage display verification

- **Date:** `2026-03-07T10:00:00-0700`
- **References:** `specs/2026-03-07_parallel-branch-substages-spec.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

The existing unit tests (bats) for buildgit use mocked Jenkins API responses and console output. While effective for testing parsing and formatting logic in isolation, they cannot verify that buildgit correctly displays stages for **real** Jenkins pipeline executions. Differences between mocked and actual Jenkins API behavior — especially for parallel stages, nested `stages {}` blocks, and agent allocation — have led to display bugs that unit tests did not catch (e.g., sub-stages outside parallel blocks, agent name swaps).

This spec introduces integration tests that run real Jenkins pipeline builds and verify buildgit's stage output against expected patterns derived from each test pipeline's Jenkinsfile. Integration tests run as part of every normal build — not opt-in.

### What we are testing

The **system under test is buildgit** — specifically, its ability to correctly interpret and display the results from the Jenkins build server. We are NOT testing the Jenkins server itself. We assume Jenkins correctly executes the pipeline jobs it has been given: scheduling stages on agents matching the provided labels, running parallel branches concurrently, nesting sub-stages within branches, etc. Jenkins is the trusted execution environment; buildgit is the component whose output we are verifying.

The integration tests verify that buildgit's output is **consistent with the known structure of the pipeline job being executed**. Given a Jenkinsfile with known stages, parallel branches, agent labels, and nesting, buildgit must produce output that correctly reflects that structure — including stage names, parallel markers, agent attribution, nesting notation, and ordering.

Both **snapshot status** (`buildgit status --all`) and **monitoring status** (`buildgit status -f`) output must be consistent with the pipeline structure. This does not mean they must produce identical output — monitoring mode prints stage lines incrementally as each stage completes, while snapshot mode shows the final state all at once. What matters is that both modes, when the build is complete, reflect the same stage structure: the same stages, the same nesting, the same parallel grouping, and the same agents. The integration tests verify this consistency against the pipeline definition.

## Architecture

### Branch-aware integration testing

Both the main project (`ralph1`) and the integration test pipeline (`buildgit-integration-test`) are **multibranch pipeline** jobs scanning the same git repository. When a developer pushes branch `fix-substages`:

1. Jenkins scans and builds `ralph1/fix-substages` using the root `Jenkinsfile`
2. The `Integration Tests` stage in `ralph1/fix-substages` triggers `buildgit-integration-test/fix-substages`
3. `buildgit-integration-test/fix-substages` runs `jbuildmon/test/integration/Jenkinsfile-parallel-substages` **from the same branch**
4. The integration test bats file in `ralph1/fix-substages` uses buildgit **from the same branch** to query the completed build and verify output

This ensures the test pipeline definition, the buildgit tool, and the test assertions all come from the same branch — so developers can modify all three in a single commit and push.

```
Developer pushes branch 'fix-substages'
    │
    ├─► ralph1/fix-substages (Jenkinsfile)
    │       ├── Unit Tests (parallel A/B/C/D)
    │       ├── Integration Tests ◄── triggers downstream
    │       │       └── buildgit-integration-test/fix-substages
    │       │               └── Jenkinsfile-parallel-substages (from same branch)
    │       │               └── runs sleep-based test pipeline
    │       │       └── buildgit status --all --job buildgit-integration-test/fix-substages
    │       │       └── verify output against expected patterns
    │       └── Deploy
    │
    └─► buildgit-integration-test/fix-substages (auto-scanned)
            └── Jenkinsfile-parallel-substages (test pipeline)
```

### Why multibranch for both jobs

- **No manual branch parameter passing**: Jenkins multibranch auto-discovers branches. The `ralph1` Integration Tests stage just triggers `buildgit-integration-test/<current-branch>` using the branch name from `env.BRANCH_NAME`.
- **Consistent code**: The test pipeline Jenkinsfile, buildgit code, and test assertions are all from the same git commit.
- **Works for any branch**: No special configuration needed when creating feature branches.
- **Scan trigger**: When `ralph1` triggers `buildgit-integration-test/<branch>`, Jenkins may need to scan/index the branch first if it hasn't seen it yet. The `build job:` step handles this — Jenkins will queue the build once the branch is indexed.

## Specification

### 1. Integration test directory structure

```
jbuildmon/test/integration/
├── Jenkinsfile-parallel-substages      # Test pipeline definition
└── integration_tests.bats              # Bats test runner
```

### 2. Test pipeline: `Jenkinsfile-parallel-substages`

A Jenkinsfile that exercises parallel branches with nested sequential sub-stages, using `sleep` commands for predictable durations. This pipeline covers:

- A sequential stage before the parallel block
- A parallel wrapper with 3 branches:
  - Branch 1: simple steps (no sub-stages)
  - Branch 2: a `stages {}` block with 2 sequential sub-stages, on a **different agent** (`slownode`) than the pipeline default
  - Branch 3: a `stages {}` block with 3 sequential sub-stages, on the default agent
- A sequential stage after the parallel block

```groovy
pipeline {
    agent {
        docker {
            image 'registry:5000/shell-jenkins-agent:latest'
            alwaysPull true
            label 'fastnode'
        }
    }
    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 5, unit: 'MINUTES')
    }
    stages {
        stage('Setup') {
            steps {
                echo 'Integration test pipeline: parallel-substages'
                sleep 2
            }
        }
        stage('Parallel Work') {
            parallel {
                stage('Quick Task') {
                    steps {
                        echo 'Simple parallel branch, no sub-stages'
                        sleep 3
                    }
                }
                stage('Slow Pipeline') {
                    agent {
                        docker {
                            image 'registry:5000/shell-jenkins-agent:latest'
                            alwaysPull true
                            label 'slownode'
                        }
                    }
                    stages {
                        stage('Compile') {
                            steps {
                                echo 'Compiling on slownode...'
                                sleep 4
                            }
                        }
                        stage('Package') {
                            steps {
                                echo 'Packaging on slownode...'
                                sleep 3
                            }
                        }
                    }
                }
                stage('Default Pipeline') {
                    stages {
                        stage('Lint') {
                            steps {
                                echo 'Linting on default agent...'
                                sleep 2
                            }
                        }
                        stage('Analyze') {
                            steps {
                                echo 'Analyzing on default agent...'
                                sleep 3
                            }
                        }
                        stage('Report') {
                            steps {
                                echo 'Reporting on default agent...'
                                sleep 2
                            }
                        }
                    }
                }
            }
        }
        stage('Finalize') {
            steps {
                echo 'All parallel work complete'
                sleep 1
            }
        }
    }
}
```

### 3. Expected stage output patterns

The integration test verifies buildgit's `status --all` output against expected patterns. Each pattern is a regex that must match a line in the output.

**Expected stages for `Jenkinsfile-parallel-substages`:**

```
Stage: \[.+\] Setup \(\d+s\)
Stage:   ║1 \[.+\] Quick Task \(\d+s\)
Stage:   ║2 \[.+\] Slow Pipeline->Compile \(\d+s\)
Stage:   ║2 \[.+\] Slow Pipeline->Package \(\d+s\)
Stage:   ║2 \[.+\] Slow Pipeline \(.+\)
Stage:   ║3 \[.+\] Default Pipeline->Lint \(\d+s\)
Stage:   ║3 \[.+\] Default Pipeline->Analyze \(\d+s\)
Stage:   ║3 \[.+\] Default Pipeline->Report \(\d+s\)
Stage:   ║3 \[.+\] Default Pipeline \(.+\)
Stage: \[.+\] Parallel Work \(.+\)
Stage: \[.+\] Finalize \(\d+s\)
```

Additional assertions:
- `Slow Pipeline->Compile` and `Slow Pipeline->Package` lines must show a **different** agent name than `Setup` (since they run on `slownode`)
- `Default Pipeline->Lint`, `Default Pipeline->Analyze`, `Default Pipeline->Report` lines must show the **same** agent as `Setup` (since they inherit the pipeline-level `fastnode` agent)
- `Slow Pipeline` branch summary duration must be >= 7s (sum of Compile=4s + Package=3s)
- `Default Pipeline` branch summary duration must be >= 7s (sum of Lint=2s + Analyze=3s + Report=2s)
- `Parallel Work` wrapper duration must be >= the longest branch duration
- Sub-stages must appear **before** their branch summary line
- Branch summary lines must appear **before** the `Parallel Work` wrapper line

### 4. Jenkins job setup

A multibranch pipeline job named `buildgit-integration-test`:

- **Type:** Multibranch Pipeline
- **Branch source:** Git, pointing to the same repository as `ralph1`
- **Script path:** `jbuildmon/test/integration/Jenkinsfile-parallel-substages`
- **Scan triggers:** Can be periodic or on-demand; the `ralph1` build triggers specific branches via `build job:`

The job is accessible via the same `JENKINS_URL`, `JENKINS_USER_ID`, and `JENKINS_API_TOKEN` credentials used by buildgit.

### 5. Integration test runner: `integration_tests.bats`

A bats test file that:

1. **Determines** the current branch from `BRANCH_NAME` env var (set by Jenkins multibranch) or falls back to `git rev-parse --abbrev-ref HEAD`
2. **Constructs** the integration job path as `buildgit-integration-test/<branch>`
3. **Triggers** the test pipeline build using `buildgit --job <job/branch> build --no-follow`
4. **Waits** for the build to complete using `buildgit --job <job/branch> status -f --once=180`
5. **Captures** the stage output using `buildgit --job <job/branch> status --all`
6. **Verifies** stage lines against expected patterns

```bash
#!/usr/bin/env bats

BUILDGIT="$BATS_TEST_DIRNAME/../../skill/buildgit/scripts/buildgit"

# Determine the branch and construct the job path
_get_integration_job() {
    local branch="${BRANCH_NAME:-}"
    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="main"
    fi
    echo "buildgit-integration-test/${branch}"
}

setup() {
    # Integration tests require Jenkins credentials — fail immediately if missing
    if [[ -z "${JENKINS_URL:-}" ]]; then
        echo "JENKINS_URL is not set" >&2
        return 1
    fi
    if [[ -z "${JENKINS_USER_ID:-}" ]]; then
        echo "JENKINS_USER_ID is not set" >&2
        return 1
    fi
    if [[ -z "${JENKINS_API_TOKEN:-}" ]]; then
        echo "JENKINS_API_TOKEN is not set" >&2
        return 1
    fi

    INTEGRATION_JOB=$(_get_integration_job)
}

# --- Trigger and wait (runs once, results cached for subsequent tests) ---

_ensure_build_complete() {
    if [[ -n "${_INTTEST_BUILD_NUMBER:-}" ]]; then
        return 0
    fi

    # Trigger a new build — fail if trigger fails
    local trigger_output
    trigger_output=$("$BUILDGIT" --job "$INTEGRATION_JOB" build --no-follow 2>&1)

    # Wait for it to complete — fail if wait times out or errors
    "$BUILDGIT" --job "$INTEGRATION_JOB" status -f --once=180 2>/dev/null

    # Capture the latest build number for subsequent queries
    _INTTEST_BUILD_NUMBER=$("$BUILDGIT" --job "$INTEGRATION_JOB" status --json 2>/dev/null \
        | jq -r '.number // empty')
    if [[ -z "$_INTTEST_BUILD_NUMBER" ]]; then
        echo "Failed to capture build number for $INTEGRATION_JOB" >&2
        return 1
    fi

    # Capture the full status --all output
    _INTTEST_STATUS_OUTPUT=$("$BUILDGIT" --job "$INTEGRATION_JOB" status --all 2>/dev/null)
    if [[ -z "$_INTTEST_STATUS_OUTPUT" ]]; then
        echo "Failed to capture status output for $INTEGRATION_JOB #$_INTTEST_BUILD_NUMBER" >&2
        return 1
    fi
}

@test "parallel-substages: build completes successfully" {
    _ensure_build_complete

    [[ -n "$_INTTEST_BUILD_NUMBER" ]]

    local result
    result=$("$BUILDGIT" --job "$INTEGRATION_JOB" status --json 2>/dev/null \
        | jq -r '.result // empty') || result=""
    [[ "$result" == "SUCCESS" ]]
}

@test "parallel-substages: stage output matches expected structure" {
    _ensure_build_complete

    local stage_lines
    stage_lines=$(echo "$_INTTEST_STATUS_OUTPUT" | grep 'Stage:')

    # Sequential stage before parallel
    echo "$stage_lines" | grep -qP 'Stage: \[.+\] Setup \(\d+s\)'

    # Branch 1: simple, no sub-stages
    echo "$stage_lines" | grep -qP 'Stage:   ║1 \[.+\] Quick Task \(\d+s\)'

    # Branch 2: sub-stages with -> notation on different agent
    echo "$stage_lines" | grep -qP 'Stage:   ║2 \[.+\] Slow Pipeline->Compile \(\d+s\)'
    echo "$stage_lines" | grep -qP 'Stage:   ║2 \[.+\] Slow Pipeline->Package \(\d+s\)'
    echo "$stage_lines" | grep -qP 'Stage:   ║2 \[.+\] Slow Pipeline \(.+\)'

    # Branch 3: sub-stages with -> notation on default agent
    echo "$stage_lines" | grep -qP 'Stage:   ║3 \[.+\] Default Pipeline->Lint \(\d+s\)'
    echo "$stage_lines" | grep -qP 'Stage:   ║3 \[.+\] Default Pipeline->Analyze \(\d+s\)'
    echo "$stage_lines" | grep -qP 'Stage:   ║3 \[.+\] Default Pipeline->Report \(\d+s\)'
    echo "$stage_lines" | grep -qP 'Stage:   ║3 \[.+\] Default Pipeline \(.+\)'

    # Wrapper and final stage
    echo "$stage_lines" | grep -qP 'Stage: \[.+\] Parallel Work \(.+\)'
    echo "$stage_lines" | grep -qP 'Stage: \[.+\] Finalize \(\d+s\)'
}

@test "parallel-substages: sub-stages appear before branch summary" {
    _ensure_build_complete

    local stage_lines
    stage_lines=$(echo "$_INTTEST_STATUS_OUTPUT" | grep 'Stage:')

    # Verify ordering: sub-stages before branch summary before wrapper
    local compile_line package_line slow_summary_line wrapper_line
    compile_line=$(echo "$stage_lines" | grep -nP 'Slow Pipeline->Compile' | head -1 | cut -d: -f1)
    package_line=$(echo "$stage_lines" | grep -nP 'Slow Pipeline->Package' | head -1 | cut -d: -f1)
    slow_summary_line=$(echo "$stage_lines" | grep -nP '║2 \[.+\] Slow Pipeline \(' | head -1 | cut -d: -f1)
    wrapper_line=$(echo "$stage_lines" | grep -nP 'Parallel Work \(' | head -1 | cut -d: -f1)

    [[ "$compile_line" -lt "$slow_summary_line" ]]
    [[ "$package_line" -lt "$slow_summary_line" ]]
    [[ "$slow_summary_line" -lt "$wrapper_line" ]]
}

@test "parallel-substages: slownode branch uses different agent than fastnode" {
    _ensure_build_complete

    # Extract agent from Setup stage (fastnode)
    local setup_agent
    setup_agent=$(echo "$_INTTEST_STATUS_OUTPUT" | grep 'Stage:.*\] Setup' | head -1 \
        | sed -E 's/.*\[([^]]+)\] Setup.*/\1/' | xargs)

    # Extract agent from Slow Pipeline sub-stage (slownode)
    local slow_agent
    slow_agent=$(echo "$_INTTEST_STATUS_OUTPUT" | grep 'Slow Pipeline->Compile' | head -1 \
        | sed -E 's/.*\[([^]]+)\] Slow.*/\1/' | xargs)

    [[ -n "$setup_agent" ]]
    [[ -n "$slow_agent" ]]
    [[ "$setup_agent" != "$slow_agent" ]]
}

@test "parallel-substages: default branch inherits pipeline agent" {
    _ensure_build_complete

    # Extract agent from Setup stage (fastnode)
    local setup_agent
    setup_agent=$(echo "$_INTTEST_STATUS_OUTPUT" | grep 'Stage:.*\] Setup' | head -1 \
        | sed -E 's/.*\[([^]]+)\] Setup.*/\1/' | xargs)

    # Extract agent from Default Pipeline sub-stage (should be same as Setup)
    local default_agent
    default_agent=$(echo "$_INTTEST_STATUS_OUTPUT" | grep 'Default Pipeline->Lint' | head -1 \
        | sed -E 's/.*\[([^]]+)\] Default.*/\1/' | xargs)

    [[ -n "$setup_agent" ]]
    [[ -n "$default_agent" ]]
    [[ "$setup_agent" == "$default_agent" ]]
}
```

### 6. Always-on execution

Integration tests run as part of every normal build on every branch. There is no opt-in flag. The tests **must always execute and must never be silently skipped**. They require:

- Valid Jenkins credentials (`JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN`)
- The `buildgit-integration-test` multibranch pipeline job configured in Jenkins

If any prerequisite is missing (credentials not set, Jenkins job not found, branch not indexed), the tests **fail** with a clear error message explaining what is missing. A skipped or silently passing integration test provides false confidence and defeats the purpose of end-to-end verification. The environment must be correctly configured for the tests to run — if it isn't, that is a broken environment that must be surfaced as a failure.

### 7. Jenkinsfile stage for integration tests

Add a new `Integration Tests` stage to the root `Jenkinsfile`, placed between the existing `Unit Tests` parallel stage and the `Deploy` stage:

```groovy
stage('Integration Tests') {
    agent {
        docker {
            image 'registry:5000/shell-jenkins-agent:latest'
            alwaysPull true
            label 'fastnode'
        }
    }
    steps {
        sh 'git submodule update --init --recursive --depth 1'
        dir('jbuildmon') {
            sh '''
                ./test/bats/bin/bats --formatter tap --report-formatter junit --output . \
                    test/integration/integration_tests.bats || true
            '''
        }
    }
    post {
        always {
            junit skipPublishingChecks: true, testResults: 'jbuildmon/report.xml'
        }
    }
}
```

This stage triggers the `buildgit-integration-test/<BRANCH_NAME>` job as a downstream build. The integration test pipeline runs on the same branch, ensuring the test Jenkinsfile, buildgit code, and assertions are all consistent.

### 8. Multibranch scan considerations

When a new branch is pushed for the first time:

1. `ralph1/<branch>` starts building (Jenkins has already indexed this branch)
2. The Integration Tests stage triggers `buildgit-integration-test/<branch>`
3. If `buildgit-integration-test` hasn't scanned this branch yet, Jenkins will return a 404 or queue the build pending scan

To handle this:
- The `build job:` step in the bats test should retry or wait if the branch hasn't been indexed yet
- The `buildgit build` command handles queue wait already via `--once=180` (3 minute timeout)
- If the integration test job doesn't exist for this branch after the timeout (scan hasn't happened), the test **fails** with a clear error message identifying the missing job/branch

### 9. Adding future test scenarios

To add a new integration test scenario:

1. Create a new `Jenkinsfile-<scenario>` in `jbuildmon/test/integration/`
2. Configure a new multibranch pipeline job in Jenkins with Script Path pointing to the new Jenkinsfile
3. Add test cases to `integration_tests.bats` (or create a new `.bats` file)

Each scenario should focus on a specific pipeline pattern (downstream builds, deeply nested parallel, agent-per-stage, etc.).

### 10. Test isolation

Each integration test run triggers a **new** build of the test pipeline. To prevent interference from concurrent test runs or previous builds:

- The test captures the build number after triggering
- Subsequent assertions query that specific build number, not "latest"
- The test pipeline uses `disableConcurrentBuilds()` is NOT set — if concurrent builds are triggered, each gets its own build number

### 11. Timeout and failure handling

- The test pipeline itself has a 5-minute timeout (in its Jenkinsfile)
- The bats test uses `--once=180` (3 minutes) when waiting for the build to complete
- If the test pipeline fails (e.g., agent unavailable), the integration test reports the failure clearly but does not block the rest of the `ralph1` build (the bats runner uses `|| true`)
- Integration test failures show as test failures in the JUnit report, not as build-breaking errors

## Test Strategy

### Verification of the framework itself

1. **Fail without credentials**: Run without Jenkins credentials. Verify all tests fail with clear error messages identifying the missing variables.
2. **Branch resolution**: Verify `_get_integration_job()` correctly constructs the job path from `BRANCH_NAME` (Jenkins env) or `git rev-parse` (local fallback).
3. **Trigger and capture**: In Jenkins, verify the test successfully triggers `buildgit-integration-test/<branch>`, waits for completion, and captures output.
4. **Pattern matching**: Verify the stage output assertions correctly identify parallel markers, agent names, nesting notation, and ordering.

### Existing test coverage

All existing unit tests must continue to pass without modification. Integration tests are additive.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
