# Checkbuild Implementation Plan

This plan breaks down the checkbuild-spec.md into independent, implementable chunks. Each chunk is self-contained, testable, and references the detailed spec for clarifying information.

---

## Chunk 1: Shared Library - Core Infrastructure

- [x] **Create `jbuildmon/lib/jenkins-common.sh` with core infrastructure**

  **Scope:** Color support, logging functions, and timestamp utilities.

  **Reference:** checkbuild-spec.md → "Shared Library: jenkins-common.sh" → Color Support, Logging Functions

  **Deliverables:**
  - Create `jbuildmon/lib/jenkins-common.sh`
  - Implement color detection and color variables (`COLOR_RESET`, `COLOR_BLUE`, `COLOR_GREEN`, `COLOR_YELLOW`, `COLOR_RED`)
  - Implement `_timestamp` function returning HH:MM:SS format
  - Implement logging functions: `log_info`, `log_success`, `log_warning`, `log_error`
  - Implement `log_banner` for large status banners

  **Test Plan:**
  1. Source the library in a test script: `source jbuildmon/lib/jenkins-common.sh`
  2. Verify color variables are set (or empty if not a TTY)
  3. Call `_timestamp` and verify it returns time in HH:MM:SS format
  4. Call each logging function and verify output goes to correct stream (stdout/stderr)
  5. Call `log_banner "SUCCESS"` and verify banner format matches spec
  6. Test with `TERM=dumb` to verify colors are disabled

---

## Chunk 2: Shared Library - Validation Functions

- [x] **Implement environment and dependency validation functions**

  **Scope:** Functions to validate environment variables, dependencies, and git repository state.

  **Reference:** checkbuild-spec.md → "Shared Library: jenkins-common.sh" → Validation Functions; "Startup Validation"

  **Deliverables:**
  - Implement `validate_environment` - checks JENKINS_URL, JENKINS_USER_ID, JENKINS_API_TOKEN
  - Implement `validate_dependencies` - checks for jq and curl availability
  - Implement `validate_git_repository` - verifies git repo with origin remote

  **Test Plan:**
  1. Test `validate_environment` with all vars set → returns success
  2. Test `validate_environment` with JENKINS_URL unset → returns failure with message
  3. Test `validate_dependencies` with jq and curl available → returns success
  4. Test `validate_dependencies` when jq is missing → returns failure
  5. Test `validate_git_repository` from within a git repo → returns success
  6. Test `validate_git_repository` from outside a git repo → returns failure
  7. Test `validate_git_repository` from repo without origin → returns failure

---

## Chunk 3: Shared Library - Jenkins API Functions

- [x] **Implement Jenkins API request functions**

  **Scope:** Functions for making authenticated requests to Jenkins API.

  **Reference:** checkbuild-spec.md → "Shared Library: jenkins-common.sh" → Jenkins API Functions; "Jenkins API Queries"

  **Deliverables:**
  - Implement `jenkins_api` - authenticated GET request, returns body
  - Implement `jenkins_api_with_status` - authenticated GET request, returns body + HTTP status
  - Implement `verify_jenkins_connection` - test connectivity to Jenkins
  - Implement `verify_job_exists` - verify job exists and set JOB_URL global

  **Test Plan:**
  1. Test `jenkins_api` against a known endpoint → returns JSON body
  2. Test `jenkins_api` with invalid credentials → handles 401/403 appropriately
  3. Test `jenkins_api_with_status` → returns both body and HTTP status code
  4. Test `verify_jenkins_connection` → returns success when Jenkins is reachable
  5. Test `verify_job_exists` with valid job → sets JOB_URL global, returns success
  6. Test `verify_job_exists` with invalid job → returns failure, reports 404

---

## Chunk 4: Shared Library - Build Information Functions

- [ ] **Implement build information retrieval functions**

  **Scope:** Functions for getting build details from Jenkins.

  **Reference:** checkbuild-spec.md → "Shared Library: jenkins-common.sh" → Build Information Functions; "Jenkins API Queries"

  **Deliverables:**
  - Implement `get_build_info` - get build JSON from API (number, result, building, timestamp, duration, url)
  - Implement `get_console_output` - get console text for a build
  - Implement `get_current_stage` - get currently executing stage name
  - Implement `get_failed_stage` - get first failed stage name
  - Implement `get_last_build_number` - get the last build number for a job

  **Test Plan:**
  1. Test `get_build_info` for a completed build → returns JSON with all expected fields
  2. Test `get_build_info` for an in-progress build → building=true, result=null
  3. Test `get_console_output` → returns console text
  4. Test `get_current_stage` for building job → returns stage name
  5. Test `get_failed_stage` for failed build → returns failed stage name
  6. Test `get_last_build_number` → returns numeric build number

---

## Chunk 5: Shared Library - Failure Analysis Functions

- [ ] **Implement failure analysis functions**

  **Scope:** Functions for analyzing build failures, extracting errors, and finding downstream failures.

  **Reference:** checkbuild-spec.md → "Shared Library: jenkins-common.sh" → Failure Analysis Functions; "Failure Analysis"

  **Deliverables:**
  - Implement `extract_error_lines` - extract error patterns from console output
  - Implement `extract_stage_logs` - extract logs for a specific pipeline stage
  - Implement `display_build_metadata` - show user, agent, pipeline info
  - Implement `detect_all_downstream_builds` - find all triggered downstream builds
  - Implement `find_failed_downstream_build` - find the failed downstream build
  - Implement `check_build_failed` - check if a build result indicates failure
  - Implement `analyze_failure` - full failure analysis orchestration

  **Test Plan:**
  1. Test `extract_error_lines` with console containing ERROR patterns → extracts errors
  2. Test `extract_error_lines` with console containing exceptions → extracts exception traces
  3. Test `extract_stage_logs` with stage name → returns only that stage's logs
  4. Test `display_build_metadata` → outputs user, agent, pipeline in correct format
  5. Test `detect_all_downstream_builds` with nested triggers → finds all builds
  6. Test `find_failed_downstream_build` → returns deepest failed build
  7. Test `check_build_failed` with FAILURE/UNSTABLE/ABORTED → returns true
  8. Test `check_build_failed` with SUCCESS → returns false
  9. Test `analyze_failure` end-to-end → produces complete failure report

---

## Chunk 6: Job Name Discovery

- [ ] **Implement job name discovery in checkbuild.sh**

  **Scope:** Logic to discover Jenkins job name from AGENTS.md or git origin.

  **Reference:** checkbuild-spec.md → "Job Name Discovery"

  **Deliverables:**
  - Implement `discover_job_name` function
  - Implement AGENTS.md parsing with flexible JOB_NAME matching:
    - `JOB_NAME=myjob`
    - `JOB_NAME = myjob`
    - `- JOB_NAME=myjob`
    - Embedded in text: `the job is JOB_NAME=myjob`
  - Implement git origin fallback for URL formats:
    - `git@github.com:org/my-project.git`
    - `https://github.com/org/my-project.git`
    - `ssh://git@server:2233/home/git/ralph1.git`
    - `git@server:path/to/repo.git`
  - Strip `.git` suffix from extracted names

  **Test Plan:**
  1. Create test AGENTS.md with `JOB_NAME=testjob` → discovers "testjob"
  2. Create test AGENTS.md with `JOB_NAME = testjob` → discovers "testjob"
  3. Create test AGENTS.md with `- JOB_NAME=testjob` → discovers "testjob"
  4. Test without AGENTS.md, origin is `git@github.com:org/my-project.git` → discovers "my-project"
  5. Test without AGENTS.md, origin is `https://github.com/org/my-project.git` → discovers "my-project"
  6. Test without AGENTS.md, origin is `ssh://git@server:2233/home/git/ralph1.git` → discovers "ralph1"
  7. Test without AGENTS.md, origin is `git@server:path/to/repo.git` → discovers "repo"
  8. Test with no AGENTS.md and no origin → returns error

---

## Chunk 7: Trigger Detection and Commit Extraction

- [ ] **Implement trigger detection and commit extraction**

  **Scope:** Parse build console to determine trigger type and extract commit information.

  **Reference:** checkbuild-spec.md → "Trigger Detection"

  **Deliverables:**
  - Implement `detect_trigger_type` - returns "automated" or "manual" with username
  - Implement `extract_triggering_commit` - extracts SHA and commit message
  - Parse console for `Started by user <username>`
  - Compare username against CHECKBUILD_TRIGGER_USER (default: buildtriggerdude)
  - Extract commit from build API (`lastBuiltRevision.SHA1`) or console patterns

  **Test Plan:**
  1. Test console with `Started by user buildtriggerdude` → returns type="automated"
  2. Test console with `Started by user jsmith` → returns type="manual", user="jsmith"
  3. Test with CHECKBUILD_TRIGGER_USER=customuser, `Started by user customuser` → returns type="automated"
  4. Test commit extraction from build API with `lastBuiltRevision.SHA1` → extracts SHA
  5. Test commit extraction from console with `Checking out Revision abc1234` → extracts SHA
  6. Test commit extraction from console with `> git checkout -f abc1234` → extracts SHA
  7. Test commit message extraction → extracts message text

---

## Chunk 8: Git Commit Correlation

- [ ] **Implement git commit correlation logic**

  **Scope:** Determine relationship between build's triggering commit and local git history.

  **Reference:** checkbuild-spec.md → "Git Commit Correlation"

  **Deliverables:**
  - Implement `correlate_commit` function
  - Check if commit exists locally: `git cat-file -t <sha>`
  - Check if commit is reachable from HEAD: `git merge-base --is-ancestor`
  - Return correlation status:
    - "Your commit" - SHA matches current HEAD
    - "In your history" - SHA is ancestor of HEAD
    - "Not in your history" - SHA exists but not reachable from HEAD
    - "Unknown commit" - SHA not found locally

  **Test Plan:**
  1. Test with SHA that matches current HEAD → returns "Your commit"
  2. Test with SHA that is parent of HEAD → returns "In your history"
  3. Test with SHA from a different branch → returns "Not in your history"
  4. Test with SHA that doesn't exist locally → returns "Unknown commit"
  5. Test with malformed SHA → handles gracefully

---

## Chunk 9: Human-Readable Output

- [ ] **Implement human-readable output formatting**

  **Scope:** Format and display build status in human-readable format.

  **Reference:** checkbuild-spec.md → "Output Formats" → "Human-Readable Output"

  **Deliverables:**
  - Implement `format_duration` - convert milliseconds to human format (e.g., "2m 34s")
  - Implement `format_timestamp` - convert epoch to human-readable date
  - Implement `display_success_output` - success build format
  - Implement `display_failure_output` - failure build format with error details
  - Implement `display_building_output` - in-progress build format
  - Include status banner, job info, trigger, commit correlation, console URL

  **Test Plan:**
  1. Test `format_duration` with 154000ms → returns "2m 34s"
  2. Test `format_duration` with 45000ms → returns "45s"
  3. Test `format_timestamp` → returns formatted date
  4. Test `display_success_output` → matches spec format with banner
  5. Test `display_failure_output` → includes Failed Jobs tree and Error Logs sections
  6. Test `display_failure_output` → includes Build Info section (user, agent, pipeline)
  7. Test `display_building_output` → shows elapsed time and current stage

---

## Chunk 10: JSON Output Mode

- [ ] **Implement JSON output mode**

  **Scope:** Format and output build status as JSON when --json flag is provided.

  **Reference:** checkbuild-spec.md → "Output Formats" → "JSON Output"

  **Deliverables:**
  - Parse `--json` command line argument
  - Implement `output_json` function
  - Build JSON structure with: job, build (number, status, building, duration_seconds, timestamp, url), trigger (type, user), commit (sha, message, in_local_history, reachable_from_head, is_head), console_url
  - For failures, add: failure (failed_jobs, root_cause_job, failed_stage, error_summary), build_info (started_by, agent, pipeline)
  - Use jq for proper JSON formatting

  **Test Plan:**
  1. Run with `--json` flag → outputs valid JSON
  2. Test successful build JSON → contains all required fields
  3. Test failed build JSON → contains failure and build_info objects
  4. Test in-progress build JSON → building=true, status=null
  5. Validate JSON output with jq parser → no syntax errors
  6. Test that human-readable output is not shown when --json is used

---

## Chunk 11: Main Script Orchestration

- [ ] **Implement checkbuild.sh main script flow**

  **Scope:** Main entry point that orchestrates all components.

  **Reference:** checkbuild-spec.md → "Startup Validation", "Error Handling"

  **Deliverables:**
  - Create `jbuildmon/checkbuild.sh`
  - Source shared library from relative path
  - Implement argument parsing (--json flag)
  - Implement startup validation sequence
  - Implement main flow: discover job → get build info → detect trigger → correlate commit → format output
  - Implement proper exit codes: 0 (success), 1 (failure/error), 2 (in progress)
  - Implement retry logic for transient API failures (up to 3 retries)

  **Test Plan:**
  1. Run without JENKINS_URL set → exits 1 with usage message
  2. Run outside git repo → exits 1 with usage message
  3. Run with missing jq → exits 1 with dependency error
  4. Run for successful build → exits 0
  5. Run for failed build → exits 1
  6. Run for in-progress build → exits 2
  7. Test retry on transient failure → retries up to 3 times

---

## Chunk 12: Claude Skill Integration

- [ ] **Create Claude skill for /checkbuild**

  **Scope:** Claude Code skill definition and documentation.

  **Reference:** checkbuild-spec.md → "Claude Skill Integration"

  **Deliverables:**
  - Create skill definition file (location TBD based on Claude Code skill conventions)
  - Skill name: `/checkbuild`
  - Skill takes no arguments
  - Skill invokes `checkbuild.sh` and returns output
  - Update AGENTS.md with skill documentation

  **Test Plan:**
  1. Invoke `/checkbuild` in Claude Code → runs checkbuild.sh
  2. Verify output is displayed to user
  3. Test in Cursor IDE → skill works correctly
  4. Verify AGENTS.md documents the skill usage

---

## Chunk 13: Migrate pushmon.sh to Shared Library

- [ ] **Refactor pushmon.sh to use shared library**

  **Scope:** Update existing pushmon.sh to source and use the shared library.

  **Reference:** checkbuild-spec.md → "Implementation Notes" → Phase 1, item 3

  **Deliverables:**
  - Update pushmon.sh to source `lib/jenkins-common.sh`
  - Remove duplicated code from pushmon.sh that now exists in the library
  - Ensure all existing functionality still works

  **Test Plan:**
  1. Run pushmon.sh with a successful build → behavior unchanged
  2. Run pushmon.sh with a failed build → failure analysis works
  3. Run pushmon.sh with downstream failures → downstream detection works
  4. Verify no regression in any pushmon.sh functionality
  5. Compare output format before/after migration → identical

---

## Implementation Notes

- Chunks are designed to be independent where possible
- Chunks 1-5 (shared library) can be implemented in any order
- Chunks 6-10 depend on the shared library being complete
- Chunk 11 integrates all components
- Chunk 12 can be done after Chunk 11
- Chunk 13 can be done anytime after Chunks 1-5

## References

- Full specification: `jbuildmon/specs/checkbuild-spec.md`
- Existing implementation for reference: `jbuildmon/pushmon.sh`
