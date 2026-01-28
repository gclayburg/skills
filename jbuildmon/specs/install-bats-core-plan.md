# Install bats-core Implementation Plan

This plan breaks down the [install-bats-core-spec.md](./install-bats-core-spec.md) into independently implementable chunks.

---

- [x] **Chunk 1: Add bats-core Git Submodules**

### Description

Install bats-core and its helper libraries (bats-support, bats-assert, bats-file) as git submodules in the repository. This provides the testing framework foundation.

### Spec Reference

See spec [Installation Method: Git Submodules](./install-bats-core-spec.md#installation-method-git-submodules) and [Submodule Repositories](./install-bats-core-spec.md#submodule-repositories).

### Dependencies

- None (foundational chunk)

### Produces

- `test/bats/` (bats-core submodule)
- `test/test_helper/bats-support/` (bats-support submodule)
- `test/test_helper/bats-assert/` (bats-assert submodule)
- `test/test_helper/bats-file/` (bats-file submodule)
- Updated `.gitmodules` file

### Implementation Details

1. Create test directory structure:
   - Create `test/` directory if it doesn't exist
   - Create `test/test_helper/` directory

2. Add git submodules from repository root:
   - Add bats-core: `git submodule add https://github.com/bats-core/bats-core.git jbuildmon/test/bats`
   - Add bats-support: `git submodule add https://github.com/bats-core/bats-support.git jbuildmon/test/test_helper/bats-support`
   - Add bats-assert: `git submodule add https://github.com/bats-core/bats-assert.git jbuildmon/test/test_helper/bats-assert`
   - Add bats-file: `git submodule add https://github.com/bats-core/bats-file.git jbuildmon/test/test_helper/bats-file`

3. Verify installation:
   - Run `./jbuildmon/test/bats/bin/bats --version`
   - Verify all load.bash files exist in helper directories

4. Commit submodule configuration:
   - Stage `.gitmodules` and `jbuildmon/test/` directory
   - Commit with message describing the addition

### Test Plan

**Verification Script:** Run manual verification commands

| Verification | Description | Spec Section |
|--------------|-------------|--------------|
| `bats_executable_exists` | Verify `test/bats/bin/bats` exists and is executable | Verification |
| `bats_version_runs` | Verify `bats --version` outputs version info | Verification |
| `support_load_exists` | Verify `test_helper/bats-support/load.bash` exists | Helper Libraries |
| `assert_load_exists` | Verify `test_helper/bats-assert/load.bash` exists | Helper Libraries |
| `file_load_exists` | Verify `test_helper/bats-file/load.bash` exists | Helper Libraries |

**Mocking Requirements:**
- None (this is infrastructure setup)

**Dependencies:** None

---

- [x] **Chunk 2: Create test_helper.bash**

### Description

Create the common test helper file that all bats tests will source. This file loads the helper libraries and provides shared setup/teardown functions and utility helpers.

### Spec Reference

See spec [Test Helper Configuration](./install-bats-core-spec.md#test-helper-configuration) section.

### Dependencies

- Chunk 1 (bats-core submodules must be installed)

### Produces

- `test/test_helper.bash`
- `test/test_helper.bats` (unit tests for helper itself)

### Implementation Details

1. Create `test/test_helper.bash` with:
   - Shebang line: `#!/usr/bin/env bash`
   - Directory resolution for TEST_DIR and PROJECT_DIR
   - Load statements for bats-support, bats-assert, bats-file
   - Common `setup()` function that:
     - Creates TEST_TEMP_DIR using mktemp
     - Stores original environment variables (JENKINS_URL, JENKINS_USER_ID, JENKINS_API_TOKEN)
   - Common `teardown()` function that:
     - Removes TEST_TEMP_DIR
     - Restores original environment variables

2. Add helper functions per spec:
   - `create_mock_git_repo()` - Creates a temporary git repository for testing
   - `create_mock_agents_md()` - Creates AGENTS.md with JOB_NAME for testing

### Test Plan

**Test File:** `test/test_helper.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `test_helper_creates_temp_dir` | Verify TEST_TEMP_DIR is created in setup | Test Helper Configuration |
| `test_helper_cleans_temp_dir` | Verify TEST_TEMP_DIR is removed in teardown | Test Helper Configuration |
| `test_helper_preserves_env` | Verify environment variables are saved and restored | Test Helper Configuration |
| `create_mock_git_repo_works` | Verify mock git repo is created with initial commit | Test Helper Configuration |
| `create_mock_agents_md_works` | Verify AGENTS.md is created with correct JOB_NAME | Test Helper Configuration |

**Mocking Requirements:**
- None (testing the helper itself)

**Dependencies:** Chunk 1 (submodules must be present)

---

- [x] **Chunk 3: Create Sample Test File (Smoke Test)**

### Description

Create a sample/smoke test file that demonstrates the testing patterns and verifies the entire bats-core setup works end-to-end. This serves as both verification and documentation.

### Spec Reference

See spec [Writing Tests](./install-bats-core-spec.md#writing-tests) and [Verification](./install-bats-core-spec.md#verification) sections.

### Dependencies

- Chunk 1 (bats-core submodules)
- Chunk 2 (test_helper.bash)

### Produces

- `test/smoke.bats`

### Implementation Details

1. Create `test/smoke.bats` with:
   - Shebang: `#!/usr/bin/env bats`
   - Load test_helper
   - Tests demonstrating each assertion type

2. Include demonstration tests for:
   - Basic pass/fail using `assert_success` and `assert_failure`
   - Output assertions using `assert_output`, `assert_output --partial`, `assert_line`
   - File assertions using `assert_file_exists`, `assert_dir_exists`
   - Using TEST_TEMP_DIR for file operations
   - Negative assertions using `refute_output`, `refute_line`

3. Add spec reference comments to each test case

### Test Plan

**Test File:** `test/smoke.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `smoke_test_passes` | Basic true command passes | Verification |
| `smoke_test_assert_success` | Demonstrates assert_success | bats-assert |
| `smoke_test_assert_failure` | Demonstrates assert_failure | bats-assert |
| `smoke_test_assert_output` | Demonstrates assert_output exact match | bats-assert |
| `smoke_test_assert_output_partial` | Demonstrates assert_output --partial | bats-assert |
| `smoke_test_assert_line` | Demonstrates assert_line | bats-assert |
| `smoke_test_refute_output` | Demonstrates refute_output | bats-assert |
| `smoke_test_file_exists` | Demonstrates assert_file_exists | bats-file |
| `smoke_test_dir_exists` | Demonstrates assert_dir_exists | bats-file |
| `smoke_test_temp_dir_available` | Verify TEST_TEMP_DIR is available | Test Helper Configuration |

**Mocking Requirements:**
- None (smoke tests use built-in commands)

**Dependencies:** Chunks 1 and 2

---

- [x] **Chunk 4: Jenkins CI Integration**

### Description

Update the Jenkins pipeline configuration to run bats tests as part of the CI build, including submodule initialization and JUnit XML reporting.

### Spec Reference

See spec [Jenkins CI Integration](./install-bats-core-spec.md#jenkins-ci-integration) section.

### Dependencies

- Chunk 1 (bats-core submodules)
- Chunk 2 (test_helper.bash)
- Chunk 3 (at least one test file to run)

### Produces

- Updated `Jenkinsfile` (or new if not present)

### Implementation Details

1. Add or update Jenkinsfile with:
   - Stage for submodule initialization: `git submodule update --init --recursive`
   - Stage for running unit tests with JUnit output format
   - Post-build action to publish JUnit results

2. Test stage implementation:
   - Use `./test/bats/bin/bats --formatter junit test/ > test-results.xml || true`
   - Capture results even if tests fail
   - Publish with `junit 'jbuildmon/test-results.xml'`

3. Alternative: Configure Git SCM plugin for automatic submodule checkout (document both options)

### Test Plan

**Test File:** Manual verification in Jenkins

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `jenkins_submodules_init` | Verify submodules initialize on fresh checkout | Jenkins CI Integration |
| `jenkins_tests_run` | Verify bats tests execute in pipeline | Jenkins CI Integration |
| `jenkins_junit_report` | Verify JUnit XML is generated and parsed | Jenkins CI Integration |
| `jenkins_test_failure_reported` | Verify failing tests show in Jenkins UI | Jenkins CI Integration |

**Mocking Requirements:**
- Requires actual Jenkins environment for full verification
- Can dry-run Jenkinsfile syntax locally

**Dependencies:** Chunks 1, 2, 3

---

## Summary

| Chunk | Title | Dependencies | Key Deliverable |
|-------|-------|--------------|-----------------|
| 1 | Add bats-core Git Submodules | None | Test framework installed |
| 2 | Create test_helper.bash | Chunk 1 | Common test infrastructure |
| 3 | Create Sample Test File | Chunks 1, 2 | Verified working setup |
| 4 | Jenkins CI Integration | Chunks 1, 2, 3 | Automated test execution |

## Definition of Done

Per each chunk:
- [ ] All unit tests written as part of the chunk have been executed and pass
- [ ] All existing unit tests in the project still pass
- [ ] If documentation is user-facing (e.g., new commands or options), it is updated
