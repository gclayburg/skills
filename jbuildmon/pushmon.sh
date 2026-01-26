#!/usr/bin/env bash
#
# pushmon.sh - Jenkins Build Monitor
# Commits, pushes, and monitors Jenkins builds with real-time feedback
#

set -euo pipefail

# =============================================================================
# Configuration Constants (see spec: Configuration Constants section)
# =============================================================================
BRANCH="${BRANCH:-main}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
MAX_BUILD_TIME="${MAX_BUILD_TIME:-1800}"
BUILD_START_TIMEOUT="${BUILD_START_TIMEOUT:-120}"
MAX_CONSECUTIVE_FAILURES="${MAX_CONSECUTIVE_FAILURES:-5}"

# =============================================================================
# Color Support
# =============================================================================
# Check if stdout is a terminal and supports colors
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    COLOR_RESET=$(tput sgr0)
    COLOR_BLUE=$(tput setaf 4)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_RED=$(tput setaf 1)
    COLOR_BOLD=$(tput bold)
else
    COLOR_RESET=""
    COLOR_BLUE=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_BOLD=""
fi

# =============================================================================
# Global State
# =============================================================================
BUILD_NUMBER=""
JOB_URL=""
HAS_STAGED_CHANGES=false

# =============================================================================
# Logging Functions (see spec: User Feedback Requirements - Logging Levels)
# =============================================================================

# Get timestamp in HH:MM:SS format
_timestamp() {
    date "+%H:%M:%S"
}

# INFO level - General status updates (blue indicator)
log_info() {
    echo "${COLOR_BLUE}[$(_timestamp)] ℹ${COLOR_RESET} $*"
}

# SUCCESS level - Successful operations (green checkmark)
log_success() {
    echo "${COLOR_GREEN}[$(_timestamp)] ✓${COLOR_RESET} $*"
}

# WARNING level - Non-fatal issues (yellow warning)
log_warning() {
    echo "${COLOR_YELLOW}[$(_timestamp)] ⚠${COLOR_RESET} $*"
}

# ERROR level - Fatal errors (red X, output to stderr)
log_error() {
    echo "${COLOR_RED}[$(_timestamp)] ✗${COLOR_RESET} $*" >&2
}

# Banner for major status changes
log_banner() {
    local status="$1"
    local message="$2"
    echo ""
    if [[ "$status" == "success" ]]; then
        echo "${COLOR_GREEN}${COLOR_BOLD}╔════════════════════════════════════════╗${COLOR_RESET}"
        echo "${COLOR_GREEN}${COLOR_BOLD}║           BUILD SUCCESSFUL             ║${COLOR_RESET}"
        echo "${COLOR_GREEN}${COLOR_BOLD}╚════════════════════════════════════════╝${COLOR_RESET}"
    else
        echo "${COLOR_RED}${COLOR_BOLD}╔════════════════════════════════════════╗${COLOR_RESET}"
        echo "${COLOR_RED}${COLOR_BOLD}║             BUILD FAILED               ║${COLOR_RESET}"
        echo "${COLOR_RED}${COLOR_BOLD}╚════════════════════════════════════════╝${COLOR_RESET}"
    fi
    echo ""
}

# =============================================================================
# Interrupt Handler (see spec: Interrupt Handling)
# =============================================================================
cleanup() {
    local exit_code=$?
    echo ""
    log_warning "Script interrupted by user"
    if [[ -n "$BUILD_NUMBER" && -n "$JOB_URL" ]]; then
        log_warning "Jenkins build #${BUILD_NUMBER} may still be running"
        log_info "Monitor manually at: ${JOB_URL}/${BUILD_NUMBER}/console"
    elif [[ -n "$JOB_URL" ]]; then
        log_info "Check job status at: ${JOB_URL}"
    fi
    exit 130
}

trap cleanup SIGINT SIGTERM

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat <<EOF
Usage: $(basename "$0") <job-name> <commit-message>

Arguments:
  job-name        The exact name of the Jenkins job to monitor
  commit-message  The git commit message for staged changes

Required Environment Variables:
  JENKINS_URL       Base URL of the Jenkins server
  JENKINS_USER_ID   Jenkins username for API authentication
  JENKINS_API_TOKEN Jenkins API token for authentication

Exit Codes:
  0   Build completed successfully
  1   Build failed or an error occurred
  130 Script was interrupted by user (Ctrl+C)
EOF
}

# =============================================================================
# Argument Validation (see spec: Section 1 - Startup Validation)
# =============================================================================
validate_arguments() {
    if [[ $# -lt 2 ]]; then
        log_error "Missing required arguments"
        usage
        exit 1
    fi
}

# =============================================================================
# Environment Variable Validation (see spec: Prerequisites)
# =============================================================================
validate_environment() {
    local missing=()

    if [[ -z "${JENKINS_URL:-}" ]]; then
        missing+=("JENKINS_URL")
    fi
    if [[ -z "${JENKINS_USER_ID:-}" ]]; then
        missing+=("JENKINS_USER_ID")
    fi
    if [[ -z "${JENKINS_API_TOKEN:-}" ]]; then
        missing+=("JENKINS_API_TOKEN")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        log_info "Set these variables before running the script"
        exit 1
    fi

    # Validate JENKINS_URL format (see spec: Section 1.3)
    if [[ ! "$JENKINS_URL" =~ ^https?:// ]]; then
        log_error "JENKINS_URL must begin with http:// or https://"
        log_error "Current value: $JENKINS_URL"
        exit 1
    fi

    # Normalize trailing slashes
    JENKINS_URL="${JENKINS_URL%/}"
}

# =============================================================================
# Git Repository Validation (see spec: Section 1.4-1.5)
# =============================================================================
validate_git_repository() {
    if ! git rev-parse --git-dir &>/dev/null; then
        log_error "Not a git repository"
        log_info "Run this command from within a git repository"
        exit 1
    fi

    if ! git remote get-url origin &>/dev/null; then
        log_error "No 'origin' remote configured"
        log_info "Add an origin remote: git remote add origin <url>"
        exit 1
    fi
}

# =============================================================================
# JSON Parser Check (see spec: Section 1.6)
# =============================================================================
validate_dependencies() {
    if ! command -v jq &>/dev/null; then
        log_error "Required dependency 'jq' not found"
        log_info "Install jq: brew install jq (macOS) or apt-get install jq (Linux)"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        log_error "Required dependency 'curl' not found"
        exit 1
    fi
}

# =============================================================================
# Jenkins API Helper
# =============================================================================
jenkins_api() {
    local endpoint="$1"
    local url="${JENKINS_URL}${endpoint}"

    curl -s -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url"
}

jenkins_api_with_status() {
    local endpoint="$1"
    local url="${JENKINS_URL}${endpoint}"

    curl -s -w "\n%{http_code}" -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url"
}

# =============================================================================
# Jenkins Connectivity Verification (see spec: Section 2)
# =============================================================================
verify_jenkins_connection() {
    log_info "Verifying Jenkins connectivity..."

    local response
    local http_code

    # Test basic connectivity
    response=$(jenkins_api_with_status "/api/json")
    http_code=$(echo "$response" | tail -1)

    case "$http_code" in
        200)
            log_success "Connected to Jenkins"
            ;;
        401)
            log_error "Jenkins authentication failed (401)"
            log_info "Check JENKINS_USER_ID and JENKINS_API_TOKEN"
            exit 1
            ;;
        403)
            log_error "Jenkins permission denied (403)"
            log_info "User may not have required permissions"
            exit 1
            ;;
        *)
            log_error "Failed to connect to Jenkins (HTTP $http_code)"
            log_info "Check JENKINS_URL: $JENKINS_URL"
            exit 1
            ;;
    esac
}

# =============================================================================
# Job Existence Verification (see spec: Section 2.3)
# =============================================================================
verify_job_exists() {
    local job_name="$1"
    log_info "Verifying job '$job_name' exists..."

    local response
    local http_code

    response=$(jenkins_api_with_status "/job/${job_name}/api/json")
    http_code=$(echo "$response" | tail -1)

    case "$http_code" in
        200)
            log_success "Job '$job_name' found"
            JOB_URL="${JENKINS_URL}/job/${job_name}"
            ;;
        404)
            log_error "Jenkins job '$job_name' not found"
            log_info "Verify the job name is correct"
            exit 1
            ;;
        *)
            log_error "Failed to verify job (HTTP $http_code)"
            exit 1
            ;;
    esac
}

# =============================================================================
# Git Operations (see spec: Section 3)
# =============================================================================

# Check for changes (see spec: Section 3.1)
# Sets global HAS_STAGED_CHANGES=true if there are staged changes to commit
check_for_changes() {
    HAS_STAGED_CHANGES=false
    local has_unpushed=false

    # Check for staged changes
    if ! git diff --cached --quiet 2>/dev/null; then
        HAS_STAGED_CHANGES=true
        log_info "Found staged changes to commit"
    fi

    # Check for unpushed commits
    local local_ref
    local remote_ref
    local_ref=$(git rev-parse HEAD 2>/dev/null || echo "")
    remote_ref=$(git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "")

    if [[ -n "$local_ref" && "$local_ref" != "$remote_ref" ]]; then
        local ahead
        ahead=$(git rev-list --count "origin/${BRANCH}..HEAD" 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            has_unpushed=true
            log_info "Found $ahead unpushed commit(s)"
        fi
    fi

    if [[ "$HAS_STAGED_CHANGES" == false && "$has_unpushed" == false ]]; then
        log_error "No staged changes and no unpushed commits"
        log_info "Stage changes with: git add <files>"
        exit 1
    fi
}

# Commit changes (see spec: Section 3.2)
commit_changes() {
    local message="$1"
    log_info "Creating commit..."

    if ! git commit -m "$message"; then
        log_error "Git commit failed"
        exit 1
    fi

    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)
    log_success "Created commit: $commit_hash"
}

# Sync with remote (see spec: Section 3.3)
sync_with_remote() {
    log_info "Fetching from origin/${BRANCH}..."

    if ! git fetch origin "$BRANCH" 2>/dev/null; then
        log_warning "Could not fetch origin/${BRANCH} - branch may not exist on remote yet"
        return 0
    fi

    # Check if we're behind
    local behind
    behind=$(git rev-list --count "HEAD..origin/${BRANCH}" 2>/dev/null || echo "0")

    if [[ "$behind" -gt 0 ]]; then
        log_info "Local branch is $behind commit(s) behind origin/${BRANCH}"
        log_info "Rebasing..."

        if ! git rebase "origin/${BRANCH}"; then
            log_error "Rebase failed due to conflicts"
            log_info "Resolve conflicts manually:"
            log_info "  1. Fix conflicts in the listed files"
            log_info "  2. git add <resolved-files>"
            log_info "  3. git rebase --continue"
            log_info "Or abort with: git rebase --abort"
            git rebase --abort 2>/dev/null || true
            exit 1
        fi

        log_success "Rebase completed successfully"
    fi
}

# Push changes (see spec: Section 3.4)
push_changes() {
    log_info "Pushing to origin/${BRANCH}..."

    if ! git push origin "$BRANCH" 2>&1; then
        log_error "Git push failed"
        log_info "If the push was rejected after a rebase, try:"
        log_info "  git push --force-with-lease origin ${BRANCH}"
        exit 1
    fi

    log_success "Pushed to origin/${BRANCH}"
}

# =============================================================================
# Build Detection (see spec: Section 4)
# =============================================================================

# Get current build number baseline (see spec: Section 4.1)
get_last_build_number() {
    local job_name="$1"
    local response

    response=$(jenkins_api "/job/${job_name}/api/json" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.lastBuild.number // 0'
    else
        echo "0"
    fi
}

# Check if job is queued (see spec: Section 4.2.4)
check_job_queued() {
    local job_name="$1"
    local response

    response=$(jenkins_api "/queue/api/json" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        echo "$response" | jq -r --arg job "$job_name" \
            '.items[] | select(.task.name == $job) | .id' 2>/dev/null | head -1
    fi
}

# Wait for new build to start (see spec: Section 4.2)
wait_for_build_start() {
    local job_name="$1"
    local baseline="$2"
    local elapsed=0
    local queued_notified=false

    log_info "Waiting for Jenkins build to start..."

    while [[ $elapsed -lt $BUILD_START_TIMEOUT ]]; do
        local current
        current=$(get_last_build_number "$job_name")

        if [[ "$current" -gt "$baseline" ]]; then
            BUILD_NUMBER="$current"
            log_success "Build #${BUILD_NUMBER} started"
            return 0
        fi

        # Check if queued
        if [[ "$queued_notified" == false ]]; then
            local queue_id
            queue_id=$(check_job_queued "$job_name")
            if [[ -n "$queue_id" ]]; then
                log_info "Job is queued, waiting for executor..."
                queued_notified=true
            fi
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    # Timeout (see spec: Section 4.3)
    log_error "Timeout: No build started within ${BUILD_START_TIMEOUT} seconds"
    log_info "Possible causes:"
    log_info "  - Webhook or SCM polling not configured"
    log_info "  - SCM settings may not match branch '${BRANCH}'"
    log_info "Check job configuration: ${JOB_URL}/configure"
    exit 1
}

# =============================================================================
# Build Monitoring (see spec: Section 5)
# =============================================================================

# Get build info
get_build_info() {
    local job_name="$1"
    local build_number="$2"

    jenkins_api "/job/${job_name}/${build_number}/api/json" 2>/dev/null || echo ""
}

# Get current stage from workflow API (see spec: Section 5.1.3)
get_current_stage() {
    local job_name="$1"
    local build_number="$2"

    local response
    response=$(jenkins_api "/job/${job_name}/${build_number}/wfapi/describe" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        # Find the currently executing stage (status IN_PROGRESS)
        echo "$response" | jq -r '.stages[] | select(.status == "IN_PROGRESS") | .name' 2>/dev/null | head -1
    fi
}

# Monitor build until completion (see spec: Section 5)
monitor_build() {
    local job_name="$1"
    local build_number="$2"
    local elapsed=0
    local last_stage=""
    local consecutive_failures=0
    local last_time_report=0

    log_info "Monitoring build #${build_number}..."

    while [[ $elapsed -lt $MAX_BUILD_TIME ]]; do
        local build_info
        build_info=$(get_build_info "$job_name" "$build_number")

        if [[ -z "$build_info" ]]; then
            consecutive_failures=$((consecutive_failures + 1))
            if [[ $consecutive_failures -ge $MAX_CONSECUTIVE_FAILURES ]]; then
                log_error "Too many consecutive API failures ($consecutive_failures)"
                exit 1
            fi
            log_warning "API request failed, retrying... ($consecutive_failures/$MAX_CONSECUTIVE_FAILURES)"
            sleep "$POLL_INTERVAL"
            elapsed=$((elapsed + POLL_INTERVAL))
            continue
        fi

        consecutive_failures=0

        local building
        local result
        building=$(echo "$build_info" | jq -r '.building')
        result=$(echo "$build_info" | jq -r '.result // empty')

        # Check completion (see spec: Section 5.2)
        if [[ "$building" == "false" && -n "$result" ]]; then
            return 0
        fi

        # Show current stage
        local current_stage
        current_stage=$(get_current_stage "$job_name" "$build_number")
        if [[ -n "$current_stage" && "$current_stage" != "$last_stage" ]]; then
            log_info "Stage: $current_stage"
            last_stage="$current_stage"
        fi

        # Periodic elapsed time update (see spec: Section 5.1.4)
        if [[ $((elapsed - last_time_report)) -ge 30 ]]; then
            log_info "Build in progress... (${elapsed}s elapsed)"
            last_time_report=$elapsed
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    log_error "Build timeout: exceeded ${MAX_BUILD_TIME} seconds"
    log_info "Build may still be running: ${JOB_URL}/${build_number}/console"
    exit 1
}

# =============================================================================
# Result Handling (see spec: Section 6)
# =============================================================================
handle_build_result() {
    local job_name="$1"
    local build_number="$2"

    local build_info
    build_info=$(get_build_info "$job_name" "$build_number")

    local result
    result=$(echo "$build_info" | jq -r '.result')

    case "$result" in
        SUCCESS)
            log_banner "success"
            log_success "Build #${build_number} completed successfully"
            log_info "Build URL: ${JOB_URL}/${build_number}"
            return 0
            ;;
        FAILURE|UNSTABLE|ABORTED)
            log_banner "failure"
            log_error "Build #${build_number} result: $result"
            analyze_failure "$job_name" "$build_number"
            return 1
            ;;
        *)
            log_warning "Build #${build_number} result: $result"
            log_info "Build URL: ${JOB_URL}/${build_number}"
            return 1
            ;;
    esac
}

# =============================================================================
# Failure Analysis (see spec: Section 7)
# =============================================================================

# Find failed stage (see spec: Section 7.1)
get_failed_stage() {
    local job_name="$1"
    local build_number="$2"

    local response
    response=$(jenkins_api "/job/${job_name}/${build_number}/wfapi/describe" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.stages[] | select(.status == "FAILED" or .status == "UNSTABLE") | .name' 2>/dev/null | head -1
    fi
}

# Get console output
get_console_output() {
    local job_name="$1"
    local build_number="$2"

    jenkins_api "/job/${job_name}/${build_number}/consoleText" 2>/dev/null || echo ""
}

# Detect all downstream builds from console output (see spec: Section 7.2)
# Returns space-separated pairs: "job1 build1\njob2 build2\n..."
detect_all_downstream_builds() {
    local console_output="$1"

    # Search for pattern: Starting building: <job-name> #<build-number>
    echo "$console_output" | grep -oE 'Starting building: [^ ]+ #[0-9]+' | \
        sed -E 's/Starting building: ([^ ]+) #([0-9]+)/\1 \2/'
}

# Check if a build failed (returns 0 if failed, 1 otherwise)
check_build_failed() {
    local job_name="$1"
    local build_number="$2"

    local build_info
    build_info=$(get_build_info "$job_name" "$build_number")

    if [[ -n "$build_info" ]]; then
        local result
        result=$(echo "$build_info" | jq -r '.result // empty')
        if [[ "$result" == "FAILURE" || "$result" == "UNSTABLE" || "$result" == "ABORTED" ]]; then
            return 0
        fi
    fi
    return 1
}

# Find the failed downstream build from a list of downstream builds
# For parallel stages, we need to check each one's status
find_failed_downstream_build() {
    local console_output="$1"

    local all_builds
    all_builds=$(detect_all_downstream_builds "$console_output")

    if [[ -z "$all_builds" ]]; then
        return
    fi

    # Check each downstream build to find the one that failed
    while IFS=' ' read -r job_name build_number; do
        if [[ -n "$job_name" && -n "$build_number" ]]; then
            if check_build_failed "$job_name" "$build_number"; then
                echo "$job_name $build_number"
                return
            fi
        fi
    done <<< "$all_builds"

    # If no failed build found, return the last one (fallback)
    echo "$all_builds" | tail -1
}

# Extract error lines from console output (see spec: Section 7.3.1)
extract_error_lines() {
    local console_output="$1"
    local max_lines="${2:-50}"

    local error_lines
    error_lines=$(echo "$console_output" | grep -iE '(ERROR|Exception|FAILURE|failed|FATAL)' | tail -"$max_lines")

    if [[ -n "$error_lines" ]]; then
        echo "$error_lines"
    else
        # Fallback: show last 100 lines
        echo "$console_output" | tail -100
    fi
}

# Extract stage-specific logs (see spec: Section 7.3.2)
extract_stage_logs() {
    local console_output="$1"
    local stage_name="$2"

    # Extract content between [Pipeline] { (StageName) and [Pipeline] }
    echo "$console_output" | awk -v stage="$stage_name" '
        BEGIN { in_stage=0 }
        /\[Pipeline\] \{ \(/ && index($0, "(" stage ")") { in_stage=1; next }
        /\[Pipeline\] \}/ && in_stage { in_stage=0; next }
        in_stage { print }
    '
}

# Analyze build failure (see spec: Section 7)
analyze_failure() {
    local job_name="$1"
    local build_number="$2"

    log_info "Analyzing failure..."

    # Get console output
    local console_output
    console_output=$(get_console_output "$job_name" "$build_number")

    if [[ -z "$console_output" ]]; then
        log_warning "Could not retrieve console output"
        log_info "View full console: ${JOB_URL}/${build_number}/console"
        return
    fi

    # Check for downstream build failure (see spec: Section 7.2)
    # For parallel stages, find the specific downstream build that failed
    local downstream
    downstream=$(find_failed_downstream_build "$console_output")

    if [[ -n "$downstream" ]]; then
        local downstream_job downstream_build
        downstream_job=$(echo "$downstream" | cut -d' ' -f1)
        downstream_build=$(echo "$downstream" | cut -d' ' -f2)

        log_info "Failure originated from downstream build: ${downstream_job} #${downstream_build}"

        local downstream_console
        downstream_console=$(get_console_output "$downstream_job" "$downstream_build")

        if [[ -n "$downstream_console" ]]; then
            echo ""
            echo "${COLOR_YELLOW}=== Downstream Build Errors ===${COLOR_RESET}"
            extract_error_lines "$downstream_console" 50
            echo "${COLOR_YELLOW}===============================${COLOR_RESET}"
            echo ""
            log_info "Full downstream console: ${JENKINS_URL}/job/${downstream_job}/${downstream_build}/console"
        fi
        return
    fi

    # Find failed stage (see spec: Section 7.1)
    local failed_stage
    failed_stage=$(get_failed_stage "$job_name" "$build_number")

    if [[ -n "$failed_stage" ]]; then
        log_info "Failed stage: $failed_stage"

        # Try to extract stage-specific logs (see spec: Section 7.3.2)
        local stage_logs
        stage_logs=$(extract_stage_logs "$console_output" "$failed_stage")

        if [[ -n "$stage_logs" ]]; then
            echo ""
            echo "${COLOR_YELLOW}=== Stage '$failed_stage' Logs ===${COLOR_RESET}"
            extract_error_lines "$stage_logs" 50
            echo "${COLOR_YELLOW}=================================${COLOR_RESET}"
            echo ""
        else
            # Fallback to error extraction from full console (see spec: Section 7.3.4)
            echo ""
            echo "${COLOR_YELLOW}=== Build Errors ===${COLOR_RESET}"
            extract_error_lines "$console_output" 50
            echo "${COLOR_YELLOW}====================${COLOR_RESET}"
            echo ""
        fi
    else
        # No stage info - might be Jenkinsfile syntax error (see spec: Section 7.3.3)
        log_warning "Could not identify failed stage (possible Jenkinsfile syntax error)"
        echo ""
        echo "${COLOR_YELLOW}=== Console Output ===${COLOR_RESET}"
        extract_error_lines "$console_output" 100
        echo "${COLOR_YELLOW}======================${COLOR_RESET}"
        echo ""
    fi

    log_info "Full console output: ${JOB_URL}/${build_number}/console"
}

# =============================================================================
# Configuration Summary (see spec: User Feedback Requirements)
# =============================================================================
display_config_summary() {
    local job_name="$1"
    local repo_url

    repo_url=$(git remote get-url origin 2>/dev/null || echo "unknown")

    echo ""
    echo "${COLOR_BOLD}Jenkins Build Monitor${COLOR_RESET}"
    echo "─────────────────────────────────────────"
    echo "  Jenkins:    $JENKINS_URL"
    echo "  Job:        $job_name"
    echo "  Branch:     $BRANCH"
    echo "  Repository: $repo_url"
    echo "─────────────────────────────────────────"
    echo ""
}

# =============================================================================
# Main Execution Flow (see spec: Phase 10)
# =============================================================================
main() {
    # Validate arguments
    validate_arguments "$@"

    local job_name="$1"
    local commit_message="$2"

    # Validate environment and dependencies
    validate_environment
    validate_dependencies
    validate_git_repository

    # Display configuration
    display_config_summary "$job_name"

    # Verify Jenkins connectivity
    verify_jenkins_connection
    verify_job_exists "$job_name"

    # Git operations
    check_for_changes

    if [[ "$HAS_STAGED_CHANGES" == true ]]; then
        commit_changes "$commit_message"
    fi

    sync_with_remote
    push_changes

    # Build detection
    local baseline
    baseline=$(get_last_build_number "$job_name")
    log_info "Current build baseline: #${baseline}"

    wait_for_build_start "$job_name" "$baseline"

    # Build monitoring
    monitor_build "$job_name" "$BUILD_NUMBER"

    # Result handling
    if handle_build_result "$job_name" "$BUILD_NUMBER"; then
        exit 0
    else
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
