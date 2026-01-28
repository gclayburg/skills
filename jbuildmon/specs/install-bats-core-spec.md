# Install bats-core Testing Framework

## Overview

This specification defines the installation and configuration of bats-core (Bash Automated Testing System) for unit testing bash shell scripts in the jbuildmon project. The installation uses git submodules to vendor the testing framework and its helper libraries directly in the repository.

## Purpose

Establish a repeatable, portable testing infrastructure for bash scripts that:
- Works identically on developer machines (macOS) and CI build agents (Linux)
- Requires no system-level package installation
- Is version-controlled alongside the codebase
- Supports comprehensive assertions and file operations testing

---

## Prerequisites

### Required Tools

| Tool | Description |
|------|-------------|
| `git` | For submodule management |
| `bash` | Version 3.2+ (macOS default) or 4.0+ (Linux) |

### No Additional System Dependencies

By using git submodules, bats-core and its helpers are vendored in the repository. Developers and CI agents only need git and bash.

---

## Installation Method: Git Submodules

### Directory Structure

```
jbuildmon/
├── test/
│   ├── bats/                    # bats-core submodule
│   │   └── bin/
│   │       └── bats             # Test runner executable
│   ├── test_helper/
│   │   ├── bats-support/        # bats-support submodule
│   │   ├── bats-assert/         # bats-assert submodule
│   │   └── bats-file/           # bats-file submodule
│   ├── test_helper.bash         # Common test setup (loads libraries)
│   ├── checkbuild.bats          # Tests for checkbuild.sh
│   ├── pushmon.bats             # Tests for pushmon.sh
│   └── jenkins-common.bats      # Tests for lib/jenkins-common.sh
├── pushmon.sh
├── checkbuild.sh
└── lib/
    └── jenkins-common.sh
```

### Submodule Repositories

| Submodule | Repository URL | Path |
|-----------|----------------|------|
| bats-core | `https://github.com/bats-core/bats-core.git` | `jbuildmon/test/bats` |
| bats-support | `https://github.com/bats-core/bats-support.git` | `jbuildmon/test/test_helper/bats-support` |
| bats-assert | `https://github.com/bats-core/bats-assert.git` | `jbuildmon/test/test_helper/bats-assert` |
| bats-file | `https://github.com/bats-core/bats-file.git` | `jbuildmon/test/test_helper/bats-file` |

### Installation Commands

From the repository root:

```bash
# Add bats-core
git submodule add https://github.com/bats-core/bats-core.git jbuildmon/test/bats

# Add helper libraries
git submodule add https://github.com/bats-core/bats-support.git jbuildmon/test/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git jbuildmon/test/test_helper/bats-assert
git submodule add https://github.com/bats-core/bats-file.git jbuildmon/test/test_helper/bats-file

# Commit the submodule configuration
git add .gitmodules jbuildmon/test/
git commit -m "Add bats-core testing framework as submodules"
```

### Clone/Checkout with Submodules

New clones or checkouts must initialize submodules:

```bash
# Option 1: Clone with submodules
git clone --recurse-submodules <repo-url>

# Option 2: Initialize after clone
git submodule update --init --recursive
```

---

## Helper Libraries

### bats-support

Provides foundational functions used by other helper libraries.

**Key Functions:**
- `fail` — Fail the test with a message
- Output formatting utilities

**Load in tests:**
```bash
load 'test_helper/bats-support/load'
```

### bats-assert

Provides assertion functions for validating command output and exit status.

**Key Functions:**

| Function | Description |
|----------|-------------|
| `assert_success` | Assert command exited with status 0 |
| `assert_failure` | Assert command exited with non-zero status |
| `assert_output` | Assert exact output match |
| `assert_output --partial` | Assert output contains substring |
| `assert_output --regexp` | Assert output matches regex |
| `assert_line` | Assert specific line in output |
| `refute_output` | Assert output does NOT match |
| `refute_line` | Assert line is NOT in output |

**Load in tests:**
```bash
load 'test_helper/bats-assert/load'
```

### bats-file

Provides assertion functions for file system operations.

**Key Functions:**

| Function | Description |
|----------|-------------|
| `assert_file_exists` | Assert file exists |
| `assert_file_not_exists` | Assert file does not exist |
| `assert_dir_exists` | Assert directory exists |
| `assert_file_contains` | Assert file contains string |
| `assert_file_executable` | Assert file is executable |

**Load in tests:**
```bash
load 'test_helper/bats-file/load'
```

---

## Test Helper Configuration

### test_helper.bash

Create a common helper file that all tests source:

**File:** `jbuildmon/test/test_helper.bash`

```bash
#!/usr/bin/env bash

# Get the directory containing this helper
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# Load bats helper libraries
load "${TEST_DIR}/test_helper/bats-support/load"
load "${TEST_DIR}/test_helper/bats-assert/load"
load "${TEST_DIR}/test_helper/bats-file/load"

# Common setup for all tests
setup() {
    # Create a temporary directory for test artifacts
    TEST_TEMP_DIR="$(mktemp -d)"

    # Store original environment
    ORIG_JENKINS_URL="${JENKINS_URL:-}"
    ORIG_JENKINS_USER_ID="${JENKINS_USER_ID:-}"
    ORIG_JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"
}

# Common teardown for all tests
teardown() {
    # Clean up temporary directory
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi

    # Restore original environment
    export JENKINS_URL="${ORIG_JENKINS_URL}"
    export JENKINS_USER_ID="${ORIG_JENKINS_USER_ID}"
    export JENKINS_API_TOKEN="${ORIG_JENKINS_API_TOKEN}"
}

# Helper: Create a mock git repository
create_mock_git_repo() {
    local repo_dir="${1:-${TEST_TEMP_DIR}/repo}"
    mkdir -p "${repo_dir}"
    cd "${repo_dir}"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"
    echo "${repo_dir}"
}

# Helper: Create mock AGENTS.md with JOB_NAME
create_mock_agents_md() {
    local job_name="$1"
    local repo_dir="${2:-${TEST_TEMP_DIR}/repo}"
    cat > "${repo_dir}/AGENTS.md" << EOF
# AGENTS.md
JOB_NAME=${job_name}
EOF
}
```

### Using test_helper.bash in Tests

```bash
#!/usr/bin/env bats

# Load common test helper
load 'test_helper'

@test "example test using helpers" {
    # Spec: install-bats-core-spec.md, Section: Test Helper Configuration
    run echo "hello world"
    assert_success
    assert_output "hello world"
}
```

---

## Running Tests

### Run All Tests

```bash
# From repository root
./jbuildmon/test/bats/bin/bats jbuildmon/test/

# From jbuildmon directory
./test/bats/bin/bats test/
```

### Run Specific Test File

```bash
./jbuildmon/test/bats/bin/bats jbuildmon/test/checkbuild.bats
```

### Run Specific Test by Name

```bash
./jbuildmon/test/bats/bin/bats jbuildmon/test/checkbuild.bats --filter "job discovery"
```

### Output Formats

```bash
# Default: TAP format
./jbuildmon/test/bats/bin/bats test/

# Pretty format (for terminals)
./jbuildmon/test/bats/bin/bats --formatter pretty test/

# JUnit XML (for CI)
./jbuildmon/test/bats/bin/bats --formatter junit test/ > test-results.xml
```

### Useful Options

| Option | Description |
|--------|-------------|
| `--tap` | TAP output format (default) |
| `--formatter pretty` | Colorized output for terminals |
| `--formatter junit` | JUnit XML for CI systems |
| `--filter <pattern>` | Run only tests matching pattern |
| `--jobs <n>` | Run tests in parallel |
| `--timing` | Show test execution times |
| `--verbose-run` | Print commands as they execute |

---

## Jenkins CI Integration

### Jenkinsfile Stage

Add a test stage to the project's Jenkinsfile:

```groovy
pipeline {
    agent any

    stages {
        stage('Initialize Submodules') {
            steps {
                sh 'git submodule update --init --recursive'
            }
        }

        stage('Run Unit Tests') {
            steps {
                dir('jbuildmon') {
                    sh './test/bats/bin/bats --formatter junit test/ > test-results.xml || true'
                }
            }
            post {
                always {
                    junit 'jbuildmon/test-results.xml'
                }
            }
        }

        // ... other stages
    }
}
```

### Build Agent Requirements

The Jenkins build agent requires:
- `git` — For submodule initialization
- `bash` — Version 3.2+ (typically pre-installed on Linux agents)

No additional package installation is required on the build agent.

### Handling Submodule Initialization

If the Jenkins job uses the Git plugin, configure it to initialize submodules:

**Pipeline (Declarative):**
```groovy
pipeline {
    agent any
    options {
        // Checkout with submodules
        checkout([$class: 'GitSCM',
            branches: [[name: '*/main']],
            extensions: [[$class: 'SubmoduleOption',
                disableSubmodules: false,
                parentCredentials: true,
                recursiveSubmodules: true,
                reference: '',
                trackingSubmodules: false
            ]],
            userRemoteConfigs: [[url: 'your-repo-url']]
        ])
    }
    stages {
        // ...
    }
}
```

**Alternative: Manual Initialization:**
```groovy
stage('Checkout') {
    steps {
        checkout scm
        sh 'git submodule update --init --recursive'
    }
}
```

---

## Writing Tests

### Test File Naming Convention

- Test files use `.bats` extension
- Name tests after the script they test: `checkbuild.bats`, `pushmon.bats`
- Library tests: `jenkins-common.bats`

### Test Structure

```bash
#!/usr/bin/env bats

# Load common test helper (provides setup/teardown and assertions)
load 'test_helper'

# Optional: File-specific setup that runs once before all tests
setup_file() {
    # Expensive setup shared across all tests in this file
    export PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

# Optional: File-specific teardown that runs once after all tests
teardown_file() {
    # Cleanup shared resources
}

@test "descriptive test name" {
    # Spec: <spec-file>, Section: <section-name>

    # Arrange
    export JENKINS_URL="http://test.example.com"

    # Act
    run "${PROJECT_ROOT}/checkbuild.sh"

    # Assert
    assert_failure
    assert_output --partial "JENKINS_USER_ID"
}
```

### Testing Guidelines

1. **Document spec reference**: Each test should comment which spec section it validates
2. **Use `run` for command execution**: Captures output and status without failing the test
3. **Isolate tests**: Use `setup`/`teardown` to ensure tests don't affect each other
4. **Mock external dependencies**: Don't make real network calls; mock curl responses
5. **Test edge cases**: Empty input, missing files, invalid arguments

### Mocking External Commands

For testing scripts that call `curl`, `git`, or other external commands:

```bash
# Create a mock curl that returns canned responses
setup() {
    # Create mock bin directory
    MOCK_BIN="${TEST_TEMP_DIR}/bin"
    mkdir -p "${MOCK_BIN}"

    # Create mock curl
    cat > "${MOCK_BIN}/curl" << 'EOF'
#!/usr/bin/env bash
# Mock curl - return canned response based on URL
if [[ "$*" == *"/api/json"* ]]; then
    echo '{"number": 42, "result": "SUCCESS"}'
else
    echo "Mock curl called with: $*" >&2
    exit 1
fi
EOF
    chmod +x "${MOCK_BIN}/curl"

    # Prepend mock bin to PATH
    export PATH="${MOCK_BIN}:${PATH}"
}
```

---

## Verification

### Post-Installation Verification

After installing the submodules, verify the setup:

```bash
# 1. Verify submodules are present
ls -la jbuildmon/test/bats/bin/bats
ls -la jbuildmon/test/test_helper/bats-support/load.bash
ls -la jbuildmon/test/test_helper/bats-assert/load.bash
ls -la jbuildmon/test/test_helper/bats-file/load.bash

# 2. Verify bats runs
./jbuildmon/test/bats/bin/bats --version

# 3. Run a smoke test
echo '@test "smoke test" { true; }' > /tmp/smoke.bats
./jbuildmon/test/bats/bin/bats /tmp/smoke.bats
rm /tmp/smoke.bats
```

### Expected Output

```
Bats 1.x.x

1..1
ok 1 smoke test
```

---

## Updating Submodules

To update bats-core or helper libraries to newer versions:

```bash
# Update all submodules to latest
git submodule update --remote --merge

# Or update specific submodule
cd jbuildmon/test/bats
git fetch origin
git checkout v1.10.0  # specific version
cd ../../..
git add jbuildmon/test/bats
git commit -m "Update bats-core to v1.10.0"
```

---

## Troubleshooting

### Submodules Not Initialized

**Symptom:** Empty `test/bats/` directory, "command not found" when running bats

**Solution:**
```bash
git submodule update --init --recursive
```

### Permission Denied on bats

**Symptom:** `./test/bats/bin/bats: Permission denied`

**Solution:**
```bash
chmod +x jbuildmon/test/bats/bin/bats
```

### Load Errors in Tests

**Symptom:** `load: cannot find 'test_helper/bats-support/load'`

**Cause:** Test is not running from the correct directory, or paths are wrong

**Solution:** Ensure tests use correct relative paths and are run from appropriate directory

### Tests Pass Locally, Fail in Jenkins

**Symptom:** Tests work on developer machine but fail in CI

**Common Causes:**
1. Submodules not initialized — Add `git submodule update --init --recursive`
2. Different bash version — Check `bash --version` on agent
3. Missing environment variables — Ensure test mocks all external dependencies

---

## Testing Checklist

- [ ] Git submodules added for bats-core, bats-support, bats-assert, bats-file
- [ ] Submodules committed to repository (.gitmodules updated)
- [ ] test_helper.bash created with common setup/teardown
- [ ] bats executable runs: `./jbuildmon/test/bats/bin/bats --version`
- [ ] Sample test file created and passes
- [ ] Tests run successfully on macOS
- [ ] Tests run successfully on Linux (or CI agent)
- [ ] Jenkins pipeline updated with test stage
- [ ] JUnit XML output works for Jenkins reporting
- [ ] README or AGENTS.md updated with test instructions
