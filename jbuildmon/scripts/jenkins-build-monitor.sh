#!/bin/bash

# Jenkins Build Monitor Script
# Commits staged changes, pushes to main, monitors Jenkins build, and shows failed stage logs

set -euo pipefail

# Configuration
BRANCH="main"
POLL_INTERVAL=5
MAX_BUILD_TIME=1800  # 30 minutes in seconds

# Trap to handle script interruption
trap 'handle_interrupt' INT TERM

handle_interrupt() {
    echo ""
    log_warning "Script interrupted by user"
    log_info "Jenkins build may still be running at: ${JENKINS_URL}/job/${JOB_NAME}/"
    exit 130
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print colored messages
log_info() {
    echo -e "[$(get_timestamp)] ${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "[$(get_timestamp)] ${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "[$(get_timestamp)] ${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "[$(get_timestamp)] ${RED}✗${NC} $1" >&2
}

# Function to check required environment variables
check_env_vars() {
    local missing_vars=()
    
    if [[ -z "${JENKINS_URL:-}" ]]; then
        missing_vars+=("JENKINS_URL")
    fi
    
    if [[ -z "${JENKINS_USER_ID:-}" ]]; then
        missing_vars+=("JENKINS_USER_ID")
    fi
    
    if [[ -z "${JENKINS_API_TOKEN:-}" ]]; then
        missing_vars+=("JENKINS_API_TOKEN")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please set the following environment variables:"
        log_error "  export JENKINS_URL=http://your-jenkins-server:8080"
        log_error "  export JENKINS_USER_ID=your-username"
        log_error "  export JENKINS_API_TOKEN=your-api-token"
        exit 1
    fi
    
    # Validate Jenkins URL format
    if [[ ! "$JENKINS_URL" =~ ^https?:// ]]; then
        log_error "JENKINS_URL must start with http:// or https://"
        log_error "Current value: ${JENKINS_URL}"
        exit 1
    fi
    
    # Remove trailing slash from JENKINS_URL if present
    JENKINS_URL="${JENKINS_URL%/}"
}

# Function to check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Please install it:"
        log_error "  macOS: brew install jq"
        log_error "  Ubuntu/Debian: sudo apt-get install jq"
        exit 1
    fi
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        log_error "Please run this script from within a git repository"
        exit 1
    fi
    
    # Check if remote 'origin' exists
    if ! git remote get-url origin > /dev/null 2>&1; then
        log_error "No 'origin' remote configured"
        log_error "Please add a remote with: git remote add origin <url>"
        exit 1
    fi
}

# Function to test Jenkins connectivity
test_jenkins_connection() {
    log_info "Testing Jenkins connectivity..."
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "${JENKINS_URL}/api/json" 2>/dev/null || echo "000")
    
    case "$response" in
        200)
            log_success "Connected to Jenkins"
            ;;
        401)
            log_error "Authentication failed. Check JENKINS_USER_ID and JENKINS_API_TOKEN"
            exit 1
            ;;
        403)
            log_error "Access forbidden. Check user permissions"
            exit 1
            ;;
        404)
            log_error "Jenkins URL not found. Check JENKINS_URL"
            exit 1
            ;;
        000)
            log_error "Cannot connect to Jenkins. Check JENKINS_URL and network connection"
            exit 1
            ;;
        *)
            log_warning "Unexpected response from Jenkins (HTTP ${response}), continuing anyway..."
            ;;
    esac
}

# Function to verify Jenkins job exists
verify_job_exists() {
    local job_name="$1"
    
    log_info "Verifying Jenkins job '${job_name}' exists..."
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "${JENKINS_URL}/job/${job_name}/api/json" 2>/dev/null || echo "000")
    
    case "$response" in
        200)
            log_success "Jenkins job '${job_name}' found"
            return 0
            ;;
        404)
            log_error "Jenkins job '${job_name}' does not exist"
            log_error "Please check the job name and try again"
            log_info "Available jobs at: ${JENKINS_URL}/api/json?tree=jobs[name]"
            exit 1
            ;;
        401|403)
            log_error "Access denied to job '${job_name}'"
            log_error "Check that your Jenkins user has permission to view this job"
            exit 1
            ;;
        000)
            log_error "Cannot connect to Jenkins to verify job"
            log_error "Check JENKINS_URL and network connection"
            exit 1
            ;;
        *)
            log_warning "Unexpected response (HTTP ${response}) when checking job, continuing anyway..."
            return 0
            ;;
    esac
}

# Usage message
usage() {
    echo "Usage: $0 <job-name> <commit-message>"
    echo ""
    echo "Arguments:"
    echo "  job-name        - Jenkins job name to monitor"
    echo "  commit-message  - Git commit message"
    echo ""
    echo "Example:"
    echo "  $0 my-project-build \"Fix authentication bug\""
    echo ""
    echo "Environment variables required:"
    echo "  JENKINS_URL        - Jenkins server URL (e.g., http://jenkins.example.com:8080)"
    echo "  JENKINS_USER_ID    - Jenkins username"
    echo "  JENKINS_API_TOKEN  - Jenkins API token"
    exit 1
}

# Main script starts here
main() {
    log_info "Jenkins Build Monitor starting..."
    echo ""
    
    # Check if job name and commit message provided
    if [[ $# -lt 2 ]]; then
        log_error "Job name and commit message are required"
        usage
    fi
    
    JOB_NAME="$1"
    local commit_message="$2"
    
    # Validate environment
    check_env_vars
    check_jq
    check_git_repo
    
    test_jenkins_connection
    verify_job_exists "$JOB_NAME"
    
    echo ""
    
    log_info "Configuration:"
    log_info "  Jenkins URL: ${JENKINS_URL}"
    log_info "  Job Name: ${JOB_NAME}"
    log_info "  Branch: ${BRANCH}"
    log_info "  Repository: $(git remote get-url origin)"
    echo ""
    
    # Step 1: Commit and push
    commit_and_push "$commit_message"
    
    # Step 2: Wait for build to start
    local build_number
    build_number=$(wait_for_build_start)
    
    # Step 3: Monitor build progress
    local build_result
    build_result=$(monitor_build "$build_number")
    
    # Step 4: Handle build result
    if [[ "$build_result" == "SUCCESS" ]]; then
        echo ""
        echo "========================================"
        log_success "BUILD SUCCESSFUL"
        echo "========================================"
        log_info "Build: #${build_number}"
        log_info "URL: ${JENKINS_URL}/job/${JOB_NAME}/${build_number}/"
        echo ""
        exit 0
    else
        echo ""
        echo "========================================"
        log_error "BUILD FAILED"
        echo "========================================"
        log_error "Build: #${build_number}"
        log_error "Result: ${build_result}"
        log_info "Analyzing failure..."
        echo ""
        
        # Find failed stage and show its logs
        analyze_failure "$build_number"
        
        echo ""
        echo "========================================"
        log_info "To view full build output:"
        echo "${JENKINS_URL}/job/${JOB_NAME}/${build_number}/console"
        echo "========================================"
        exit 1
    fi
}

# Function to commit and push changes
commit_and_push() {
    local commit_message="$1"
    local has_staged_changes=false
    local has_unpushed_commits=false
    
    log_info "Checking for staged changes..."
    
    # Check if there are staged changes
    if ! git diff --cached --quiet; then
        has_staged_changes=true
        log_success "Found staged changes"
    else
        log_info "No staged changes found"
        
        # Check for unpushed commits
        log_info "Checking for unpushed commits..."
        
        # Fetch remote to get latest state
        if ! git fetch origin "${BRANCH}" 2>/dev/null; then
            log_warning "Failed to fetch from origin"
        fi
        
        # Check if we have commits that haven't been pushed
        local local_commit=$(git rev-parse HEAD 2>/dev/null)
        local remote_commit=$(git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "")
        
        if [[ -n "$remote_commit" ]]; then
            # Check if local is ahead of remote
            local ahead_count=$(git rev-list --count "origin/${BRANCH}..HEAD" 2>/dev/null || echo "0")
            
            if [[ "$ahead_count" -gt 0 ]]; then
                has_unpushed_commits=true
                log_success "Found ${ahead_count} unpushed commit(s)"
            else
                log_info "No unpushed commits found"
            fi
        else
            log_warning "Could not determine remote state"
        fi
    fi
    
    # Fail if we have neither staged changes nor unpushed commits
    if [[ "$has_staged_changes" == "false" && "$has_unpushed_commits" == "false" ]]; then
        log_error "Nothing to commit or push"
        log_error "Please either:"
        log_error "  - Stage changes with: git add <files>"
        log_error "  - Or ensure you have unpushed commits"
        exit 1
    fi
    
    # Commit staged changes if we have them
    if [[ "$has_staged_changes" == "true" ]]; then
        # Commit the changes first
        log_info "Committing changes..."
        if git commit -m "$commit_message"; then
            log_success "Committed: $commit_message"
        else
            log_error "Failed to commit changes"
            exit 1
        fi
    else
        log_info "Skipping commit (no staged changes, will push existing commits)"
    fi
    
    # Get the commit hash for reference
    local commit_hash=$(git rev-parse HEAD)
    local short_hash=$(git rev-parse --short HEAD)
    log_info "Commit hash: ${short_hash}"
    
    # Fetch remote changes to check if we're behind
    log_info "Fetching remote changes..."
    if ! git fetch origin "${BRANCH}" 2>/dev/null; then
        log_warning "Failed to fetch from origin, continuing anyway..."
    fi
    
    # Check if local branch is behind remote
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "")
    
    if [[ -n "$remote_commit" ]]; then
        # Check if we're behind (remote has commits we don't have)
        if ! git merge-base --is-ancestor "origin/${BRANCH}" HEAD 2>/dev/null; then
            log_warning "Local branch is behind origin/${BRANCH}"
            log_info "Rebasing your commit on top of remote changes..."
            
            # Try to rebase our commit on top of remote
            if git rebase "origin/${BRANCH}"; then
                log_success "Successfully rebased on origin/${BRANCH}"
                # Update short hash after rebase
                short_hash=$(git rev-parse --short HEAD)
                log_info "New commit hash after rebase: ${short_hash}"
            else
                log_error "Rebase failed - there may be conflicts"
                log_error "Your commit is still local but needs manual conflict resolution"
                log_error "Please resolve manually:"
                log_error "  1. Fix conflicts"
                log_error "  2. git add <resolved-files>"
                log_error "  3. git rebase --continue"
                log_error "  4. Then run: git push origin ${BRANCH}"
                log_error "  Or abort with: git rebase --abort && git reset HEAD~1"
                exit 1
            fi
        fi
    fi
    
    # Push to origin
    log_info "Pushing to origin/${BRANCH}..."
    if git push origin "${BRANCH}"; then
        log_success "Pushed to origin/${BRANCH}"
    else
        log_error "Failed to push to origin/${BRANCH}"
        log_error "This is unexpected after rebase. Manual intervention needed."
        log_error "Try: git push origin ${BRANCH} --force-with-lease"
        exit 1
    fi
    
    echo ""
    log_success "Code pushed successfully!"
    log_info "Commit: ${short_hash} - ${commit_message}"
    echo ""
}

# Function to make Jenkins API calls with HTTP status code
# Returns JSON response and HTTP code via stdout
jenkins_api_call_with_status() {
    local endpoint="$1"
    local url="${JENKINS_URL}${endpoint}"
    
    # Create temp file for response body
    local temp_response=$(mktemp)
    
    # Make request and capture HTTP code
    local http_code
    http_code=$(curl -s -w "%{http_code}" -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url" -o "$temp_response" 2>/dev/null || echo "000")
    
    local response_body=""
    if [[ -f "$temp_response" ]]; then
        response_body=$(cat "$temp_response")
        rm -f "$temp_response"
    fi
    
    # Output format: HTTP_CODE|RESPONSE_BODY
    echo "${http_code}|${response_body}"
}

# Function to make Jenkins API calls
# Returns empty string on failure (caller should check)
jenkins_api_call() {
    local endpoint="$1"
    local url="${JENKINS_URL}${endpoint}"
    
    # Use -f to fail on HTTP errors, but capture the output
    # Return empty on failure so callers can detect and handle
    local response
    response=$(curl -s -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url" 2>/dev/null) || return 1
    echo "$response"
}

# Function to wait for build to start
# Note: All log messages go to stderr so they're displayed while stdout is captured for return value
wait_for_build_start() {
    log_info "Waiting for Jenkins build to start..." >&2
    
    # Get the current last build number before we start
    local last_build_before
    local api_response
    local result
    result=$(jenkins_api_call_with_status "/job/${JOB_NAME}/lastBuild/api/json")
    local http_code="${result%%|*}"
    local response_body="${result#*|}"
    
    if [[ "$http_code" == "404" ]]; then
        log_error "Job '${JOB_NAME}' not found on Jenkins server" >&2
        log_error "This job was verified to exist earlier but now returns 404" >&2
        log_error "Please check the job name and Jenkins configuration" >&2
        exit 1
    elif [[ "$http_code" == "200" ]]; then
        last_build_before=$(echo "$response_body" | jq -r '.number // 0' 2>/dev/null || echo "0")
    else
        log_warning "No previous builds found (HTTP ${http_code})" >&2
        last_build_before=0
    fi
    
    log_info "Last build number before push: ${last_build_before}" >&2
    
    # Wait for a new build to appear
    local max_wait=120  # 2 minutes
    local elapsed=0
    local new_build_number=0
    local shown_queue_message=false
    local consecutive_failures=0
    local max_consecutive_failures=5
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Check if there's a new build
        local current_last_build
        result=$(jenkins_api_call_with_status "/job/${JOB_NAME}/lastBuild/api/json")
        http_code="${result%%|*}"
        response_body="${result#*|}"
        
        if [[ "$http_code" == "404" ]]; then
            log_error "Job '${JOB_NAME}' not found (HTTP 404)" >&2
            log_error "The job may have been deleted or renamed" >&2
            exit 1
        elif [[ "$http_code" != "200" ]]; then
            consecutive_failures=$((consecutive_failures + 1))
            if [[ $consecutive_failures -ge $max_consecutive_failures ]]; then
                log_error "Too many consecutive API failures (${consecutive_failures} attempts, HTTP ${http_code})" >&2
                log_error "Jenkins may be experiencing issues or the job may not be accessible" >&2
                log_error "Last HTTP status: ${http_code}" >&2
                exit 1
            fi
            log_warning "API call failed (HTTP ${http_code}), retrying... (${consecutive_failures}/${max_consecutive_failures})" >&2
            sleep "$POLL_INTERVAL"
            elapsed=$((elapsed + POLL_INTERVAL))
            continue
        fi
        
        # Reset failure counter on success
        consecutive_failures=0
        
        current_last_build=$(echo "$response_body" | jq -r '.number // 0' 2>/dev/null || echo "0")
        
        if [[ $current_last_build -gt $last_build_before ]]; then
            new_build_number=$current_last_build
            log_success "Build #${new_build_number} detected" >&2
            echo "$new_build_number"
            return 0
        fi
        
        # Check if build is in queue
        local queue_info
        result=$(jenkins_api_call_with_status "/queue/api/json")
        http_code="${result%%|*}"
        response_body="${result#*|}"
        
        if [[ "$http_code" == "200" ]]; then
            local in_queue
            # Add || true to prevent pipefail from causing script exit if items array is empty
            in_queue=$(echo "$response_body" | jq -r "(.items // [])[] | select(.task.name == \"${JOB_NAME}\") | .id" 2>/dev/null | head -1 || true)
            
            if [[ -n "$in_queue" && "$shown_queue_message" == "false" ]]; then
                log_info "Build queued (waiting for executor)..." >&2
                shown_queue_message=true
            fi
        fi
        
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
        
        # Show progress every 15 seconds
        if (( elapsed % 15 == 0 )); then
            log_info "Still waiting for build... (${elapsed}s elapsed)" >&2
        fi
    done
    
    echo "" >&2
    log_error "Timeout waiting for build to start (waited ${max_wait}s)" >&2
    log_error "No new build detected after push" >&2
    log_error "This could mean:" >&2
    log_error "  - Jenkins webhook/polling is not configured for this job" >&2
    log_error "  - The job's SCM settings don't match the branch pushed (${BRANCH})" >&2
    log_error "  - Jenkins is too busy to start the build" >&2
    log_info "Check Jenkins job manually: ${JENKINS_URL}/job/${JOB_NAME}/" >&2
    exit 1
}

# Function to monitor build progress
# Note: All log messages go to stderr so they're displayed while stdout is captured for return value
monitor_build() {
    local build_number="$1"
    
    log_info "Monitoring build #${build_number}..." >&2
    log_info "Build URL: ${JENKINS_URL}/job/${JOB_NAME}/${build_number}/" >&2
    
    local elapsed=0
    local last_stage=""
    
    while [[ $elapsed -lt $MAX_BUILD_TIME ]]; do
        # Get build status
        local build_info
        build_info=$(jenkins_api_call "/job/${JOB_NAME}/${build_number}/api/json" || echo "")
        
        if [[ -z "$build_info" ]]; then
            log_warning "Failed to fetch build info (retry)" >&2
            sleep "$POLL_INTERVAL"
            elapsed=$((elapsed + POLL_INTERVAL))
            continue
        fi
        
        local building
        building=$(echo "$build_info" | jq -r '.building' 2>/dev/null || echo "true")
        
        local result
        result=$(echo "$build_info" | jq -r '.result // "null"' 2>/dev/null || echo "null")
        
        # Try to get current stage information
        local stage_info
        stage_info=$(jenkins_api_call "/job/${JOB_NAME}/${build_number}/wfapi/describe" 2>/dev/null || echo "{}")
        
        if [[ "$stage_info" != "{}" ]]; then
            local current_stage
            # Use (.stages // []) to handle case where stages array doesn't exist
            # Add || true to prevent pipefail from causing script exit
            current_stage=$(echo "$stage_info" | jq -r '(.stages // [])[] | select(.status == "IN_PROGRESS") | .name' 2>/dev/null | head -1 || true)
            
            if [[ -n "$current_stage" && "$current_stage" != "$last_stage" ]]; then
                log_info "Stage: ${current_stage}" >&2
                last_stage="$current_stage"
            fi
        fi
        
        # Check if build is complete
        if [[ "$building" == "false" ]]; then
            log_info "Build completed with result: ${result}" >&2
            echo "$result"
            return 0
        fi
        
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
        
        # Print progress dots
        if (( elapsed % 30 == 0 )); then
            log_info "Build still running... (${elapsed}s elapsed)" >&2
        fi
    done
    
    log_error "Build timeout (${MAX_BUILD_TIME}s exceeded)" >&2
    echo "TIMEOUT"
    return 1
}

# Function to find the failed stage
# Note: All log messages go to stderr so they're displayed while stdout is captured for return value
find_failed_stage() {
    local build_number="$1"
    
    # Get pipeline stage information
    local stage_info
    stage_info=$(jenkins_api_call "/job/${JOB_NAME}/${build_number}/wfapi/describe" || echo "")
    
    if [[ -z "$stage_info" ]]; then
        log_error "Failed to fetch stage information" >&2
        return 1
    fi
    
    # Find the first failed stage
    # Use (.stages // []) to handle case where stages array doesn't exist (build failed before any stage)
    # Add || true to prevent pipefail from causing script exit
    local failed_stage
    failed_stage=$(echo "$stage_info" | jq -r '(.stages // [])[] | select(.status == "FAILED" or .status == "UNSTABLE") | .name' 2>/dev/null | head -1 || true)
    
    if [[ -z "$failed_stage" ]]; then
        log_warning "No specific failed stage found" >&2
        echo ""
        return 1
    fi
    
    echo "$failed_stage"
    return 0
}

# Function to get console output using API or jenkins-cli fallback
get_console_output() {
    local build_number="$1"
    local console_text=""
    
    # Try API first
    console_text=$(jenkins_api_call "/job/${JOB_NAME}/${build_number}/consoleText" || true)
    
    if [[ -n "$console_text" ]]; then
        echo "$console_text"
        return 0
    fi
    
    # Try jenkins-cli as fallback if available
    if command -v jenkins-cli &> /dev/null; then
        log_info "API failed, trying jenkins-cli..." >&2
        console_text=$(jenkins-cli console "${JOB_NAME}" "${build_number}" 2>/dev/null || true)
        if [[ -n "$console_text" ]]; then
            echo "$console_text"
            return 0
        fi
    fi
    
    return 1
}

# Function to analyze build failure
analyze_failure() {
    local build_number="$1"
    
    # Find which stage failed
    # Use || true to prevent set -e from exiting when find_failed_stage returns 1
    local failed_stage
    failed_stage=$(find_failed_stage "$build_number" || true)
    
    if [[ -z "$failed_stage" ]]; then
        log_warning "Could not determine which stage failed (build may have failed before reaching any stage)"
        log_info "This typically happens with Jenkinsfile syntax errors or immediate failures"
        echo ""
        log_info "Showing full console output:"
        echo ""
        echo "=========================================="
        
        # Get and display full console output
        local console_text
        console_text=$(get_console_output "$build_number" || true)
        
        if [[ -n "$console_text" ]]; then
            echo "$console_text"
        else
            log_error "Failed to fetch console output via API or jenkins-cli"
            log_info "Try manually viewing: ${JENKINS_URL}/job/${JOB_NAME}/${build_number}/console"
        fi
        
        echo "=========================================="
        return 0
    fi
    
    log_error "Failed stage: ${failed_stage}"
    echo ""
    
    # Check if this stage failure is from a downstream build
    check_downstream_failure "$build_number" "$failed_stage"
}

# Function to show full console output (called when build fails without identifiable stage)
show_full_console() {
    local build_number="$1"
    
    log_info "Fetching full console output..."
    
    local console_text
    console_text=$(jenkins_api_call "/job/${JOB_NAME}/${build_number}/consoleText" || echo "")
    
    if [[ -z "$console_text" ]]; then
        log_error "Failed to fetch console output"
        log_info "Try manually viewing: ${JENKINS_URL}/job/${JOB_NAME}/${build_number}/console"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "CONSOLE OUTPUT"
    echo "=========================================="
    echo "$console_text"
    echo "=========================================="
    
    return 0
}

# Function to check if the stage failure is from a downstream build
# If so, fetch and display logs from the downstream build instead
check_downstream_failure() {
    local build_number="$1"
    local stage_name="$2"
    
    # Get full console output to check for downstream builds
    local console_text
    console_text=$(get_console_output "$build_number" || true)
    
    if [[ -z "$console_text" ]]; then
        log_error "Failed to fetch console output"
        log_info "Try manually viewing: ${JENKINS_URL}/job/${JOB_NAME}/${build_number}/console"
        return 1
    fi
    
    # Look for downstream build patterns in Jenkins console output
    # Instead of extracting stage logs with awk (which is complex with parallel stages),
    # search for "Starting building: " pattern in context around the stage name
    
    # Get lines around the stage to find downstream build references
    local stage_context
    stage_context=$(echo "$console_text" | grep -A 50 "{ (${stage_name})" | head -60 || true)
    
    # Search for downstream build trigger patterns
    local downstream_job
    local downstream_build_num
    
    # Pattern: "Starting building: job-name #123"
    if [[ "$stage_context" =~ Starting\ building:\ ([a-zA-Z0-9_-]+)\ \#([0-9]+) ]]; then
        downstream_job="${BASH_REMATCH[1]}"
        downstream_build_num="${BASH_REMATCH[2]}"
    fi
    
    if [[ -n "$downstream_job" && -n "$downstream_build_num" ]]; then
        log_info "Detected downstream build failure: ${downstream_job} #${downstream_build_num}"
        echo ""
        
        # Fetch and display console output from downstream build
        log_info "Fetching logs from downstream build..."
        echo ""
        echo "=========================================="
        echo "DOWNSTREAM BUILD: ${downstream_job} #${downstream_build_num}"
        echo "=========================================="
        
        local downstream_console
        downstream_console=$(curl -s -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
            "${JENKINS_URL}/job/${downstream_job}/${downstream_build_num}/consoleText" 2>/dev/null || true)
        
        if [[ -n "$downstream_console" ]]; then
            # Show error context from the downstream build
            # Look for common error patterns and show surrounding context
            local has_error=false
            local error_context=""
            
            # Search for error indicators
            error_context=$(echo "$downstream_console" | grep -B 15 -A 5 -iE "(ERROR|Exception|FAILURE|failed|error response)" || true)
            
            if [[ -n "$error_context" ]]; then
                echo "$error_context"
                has_error=true
            else
                # No specific errors found, show last 100 lines which usually contain the failure
                log_info "No specific error pattern found, showing last 100 lines:"
                echo "$downstream_console" | tail -100
            fi
            
            echo ""
            echo "=========================================="
            log_info "Downstream build URL:"
            echo "${JENKINS_URL}/job/${downstream_job}/${downstream_build_num}/console"
        else
            log_error "Failed to fetch downstream build console output"
            log_info "View manually: ${JENKINS_URL}/job/${downstream_job}/${downstream_build_num}/console"
            
            # Fallback: show parent stage logs
            echo ""
            log_info "Showing parent stage logs as fallback:"
            extract_stage_logs "$build_number" "$stage_name"
        fi
    else
        # No downstream build detected, show stage logs from parent build
        extract_stage_logs "$build_number" "$stage_name"
    fi
}

# Function to extract logs for a specific stage
extract_stage_logs() {
    local build_number="$1"
    local stage_name="$2"
    
    log_info "Extracting console logs for stage: ${stage_name}"
    echo ""
    
    # Get full console output using the helper function
    local console_text
    console_text=$(get_console_output "$build_number" || true)
    
    if [[ -z "$console_text" ]]; then
        log_error "Failed to fetch console output"
        log_info "Try manually viewing: ${JENKINS_URL}/job/${JOB_NAME}/${build_number}/console"
        return 0
    fi
    
    # Parse console log to extract stage-specific lines
    # Jenkins pipeline logs have markers like:
    # [Pipeline] stage
    # [Pipeline] { (StageName)
    # ... stage content ...
    # [Pipeline] }
    
    # Create a pattern to match the stage
    # We need to handle stage names with spaces and special characters
    local stage_pattern="\\[Pipeline\\] { (${stage_name})"
    
    # Use awk to extract lines between stage start and end markers
    echo "$console_text" | awk -v stage="$stage_name" '
    BEGIN {
        in_stage = 0
        stage_found = 0
    }
    
    # Match stage start: [Pipeline] { (StageName)
    /\[Pipeline\] \{ \(/ {
        # Extract stage name from the line using sub() instead of match()
        # This works with both BSD awk and GNU awk
        temp = $0
        sub(/.*\[Pipeline\] \{ \(/, "", temp)
        sub(/\).*/, "", temp)
        current_stage = temp
        
        if (current_stage == stage) {
            in_stage = 1
            stage_found = 1
            print $0
            next
        } else if (in_stage) {
            # We hit a new stage, stop printing
            in_stage = 0
        }
    }
    
    # Match stage end: [Pipeline] }
    /\[Pipeline\] \}/ {
        if (in_stage) {
            print $0
            in_stage = 0
        }
        next
    }
    
    # Print lines that are within the stage
    {
        if (in_stage) {
            print $0
        }
    }
    
    END {
        if (!stage_found) {
            print "[ERROR] Stage not found in console output" > "/dev/stderr"
            exit 1
        }
    }
    '
    
    local awk_result=$?
    
    echo ""
    
    if [[ $awk_result -ne 0 ]]; then
        log_warning "Could not extract stage-specific logs using pattern matching"
        log_info "Attempting alternative extraction method..."
        
        # Alternative: Show last N lines which likely contain the error
        echo ""
        log_info "Last 100 lines of console output:"
        echo "----------------------------------------"
        echo "$console_text" | tail -100
        echo "----------------------------------------"
    fi
    
    echo ""
    log_info "Full console output available at:"
    echo "${JENKINS_URL}/job/${JOB_NAME}/${build_number}/console"
}

# Run main function with all arguments
main "$@"
