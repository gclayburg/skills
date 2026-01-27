#!/usr/bin/env bash
#
# jenkins-common.sh - Shared library for Jenkins build tools
#
# This library provides common functionality shared between pushmon.sh and checkbuild.sh
# to avoid code duplication.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib/jenkins-common.sh"
#

# Prevent multiple sourcing
if [[ -n "${_JENKINS_COMMON_LOADED:-}" ]]; then
    return 0
fi
_JENKINS_COMMON_LOADED=1

# =============================================================================
# Color Support
# =============================================================================
# Check if stdout is a terminal and supports colors
# Colors are disabled if:
#   - stdout is not a TTY
#   - tput is not available
#   - terminal reports < 8 colors
#   - TERM is "dumb"
#   - NO_COLOR environment variable is set

_init_colors() {
    if [[ -t 1 ]] && \
       [[ "${TERM:-}" != "dumb" ]] && \
       [[ -z "${NO_COLOR:-}" ]] && \
       command -v tput &>/dev/null && \
       [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
        COLOR_RESET=$(tput sgr0)
        COLOR_BLUE=$(tput setaf 4)
        COLOR_GREEN=$(tput setaf 2)
        COLOR_YELLOW=$(tput setaf 3)
        COLOR_RED=$(tput setaf 1)
        COLOR_CYAN=$(tput setaf 6)
        COLOR_BOLD=$(tput bold)
    else
        COLOR_RESET=""
        COLOR_BLUE=""
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_RED=""
        COLOR_CYAN=""
        COLOR_BOLD=""
    fi
}

# Initialize colors on source
_init_colors

# =============================================================================
# Timestamp Function
# =============================================================================

# Get timestamp in HH:MM:SS format
_timestamp() {
    date "+%H:%M:%S"
}

# =============================================================================
# Logging Functions
# =============================================================================

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
# Usage: log_banner "success" [message]
#        log_banner "failure" [message]
#        log_banner "building" [message]
log_banner() {
    local status="$1"
    local message="${2:-}"
    echo ""
    case "$status" in
        success)
            echo "${COLOR_GREEN}${COLOR_BOLD}╔════════════════════════════════════════╗${COLOR_RESET}"
            echo "${COLOR_GREEN}${COLOR_BOLD}║           BUILD SUCCESSFUL             ║${COLOR_RESET}"
            echo "${COLOR_GREEN}${COLOR_BOLD}╚════════════════════════════════════════╝${COLOR_RESET}"
            ;;
        failure)
            echo "${COLOR_RED}${COLOR_BOLD}╔════════════════════════════════════════╗${COLOR_RESET}"
            echo "${COLOR_RED}${COLOR_BOLD}║             BUILD FAILED               ║${COLOR_RESET}"
            echo "${COLOR_RED}${COLOR_BOLD}╚════════════════════════════════════════╝${COLOR_RESET}"
            ;;
        building|in_progress)
            echo "${COLOR_YELLOW}${COLOR_BOLD}╔════════════════════════════════════════╗${COLOR_RESET}"
            echo "${COLOR_YELLOW}${COLOR_BOLD}║          BUILD IN PROGRESS             ║${COLOR_RESET}"
            echo "${COLOR_YELLOW}${COLOR_BOLD}╚════════════════════════════════════════╝${COLOR_RESET}"
            ;;
        *)
            # Generic banner with custom status text
            local status_upper
            status_upper=$(echo "$status" | tr '[:lower:]' '[:upper:]')
            local padded
            # Center the status text in a 40-char wide box (38 chars inside borders)
            local status_len=${#status_upper}
            local total_pad=$((38 - status_len - 14))  # "BUILD STATUS: " is 14 chars
            local left_pad=$((total_pad / 2))
            local right_pad=$((total_pad - left_pad))
            padded=$(printf "%*s%s%*s" $left_pad "" "BUILD STATUS: ${status_upper}" $right_pad "")
            echo "${COLOR_CYAN}${COLOR_BOLD}╔════════════════════════════════════════╗${COLOR_RESET}"
            echo "${COLOR_CYAN}${COLOR_BOLD}║${padded}║${COLOR_RESET}"
            echo "${COLOR_CYAN}${COLOR_BOLD}╚════════════════════════════════════════╝${COLOR_RESET}"
            ;;
    esac
    echo ""
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate required environment variables
# Checks: JENKINS_URL, JENKINS_USER_ID, JENKINS_API_TOKEN
# Exits with error if any are missing or malformed
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
        log_info "Please set the following environment variables:"
        for var in "${missing[@]}"; do
            log_info "  - $var"
        done
        return 1
    fi

    # Validate JENKINS_URL format
    if [[ ! "$JENKINS_URL" =~ ^https?:// ]]; then
        log_error "JENKINS_URL must begin with http:// or https://"
        log_error "Current value: $JENKINS_URL"
        return 1
    fi

    # Normalize trailing slashes
    JENKINS_URL="${JENKINS_URL%/}"
    return 0
}

# Validate required external dependencies
# Checks: jq, curl
# Exits with error if any are missing
validate_dependencies() {
    local missing=()

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        for dep in "${missing[@]}"; do
            case "$dep" in
                jq)
                    log_info "Install jq: brew install jq (macOS) or apt-get install jq (Linux)"
                    ;;
                curl)
                    log_info "Install curl: brew install curl (macOS) or apt-get install curl (Linux)"
                    ;;
            esac
        done
        return 1
    fi

    return 0
}

# Validate we're in a git repository with an origin remote
# Exits with error if not in a git repo or no origin remote
validate_git_repository() {
    if ! git rev-parse --git-dir &>/dev/null; then
        log_error "Not a git repository"
        log_info "Run this command from within a git repository"
        return 1
    fi

    if ! git remote get-url origin &>/dev/null; then
        log_error "No 'origin' remote found"
        log_info "This repository must have an 'origin' remote configured"
        return 1
    fi

    return 0
}

# =============================================================================
# Jenkins API Functions
# =============================================================================

# Global variable set by verify_job_exists
JOB_URL=""

# Make authenticated GET request to Jenkins API
# Usage: jenkins_api "/job/myjob/api/json"
# Returns: Response body (or empty string on failure)
# Note: Uses -f flag so curl returns non-zero on HTTP errors
jenkins_api() {
    local endpoint="$1"
    local url="${JENKINS_URL}${endpoint}"

    curl -s -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url"
}

# Make authenticated GET request and return body with HTTP status code
# Usage: jenkins_api_with_status "/job/myjob/api/json"
# Returns: Response body followed by newline and HTTP status code
# Example output:
#   {"_class":"hudson.model.FreeStyleProject",...}
#   200
jenkins_api_with_status() {
    local endpoint="$1"
    local url="${JENKINS_URL}${endpoint}"

    curl -s -w "\n%{http_code}" -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url"
}

# Verify Jenkins connectivity and authentication
# Tests connection to Jenkins root API endpoint
# Returns: 0 on success, 1 on failure (with error logged)
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
            return 0
            ;;
        401)
            log_error "Jenkins authentication failed (401)"
            log_info "Check JENKINS_USER_ID and JENKINS_API_TOKEN"
            return 1
            ;;
        403)
            log_error "Jenkins permission denied (403)"
            log_info "User may not have required permissions"
            return 1
            ;;
        *)
            log_error "Failed to connect to Jenkins (HTTP $http_code)"
            log_info "Check JENKINS_URL: $JENKINS_URL"
            return 1
            ;;
    esac
}

# Verify that a Jenkins job exists and set JOB_URL global
# Usage: verify_job_exists "my-job-name"
# Sets: JOB_URL global variable to the full job URL
# Returns: 0 on success, 1 on failure (with error logged)
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
            return 0
            ;;
        404)
            log_error "Jenkins job '$job_name' not found"
            log_info "Verify the job name is correct"
            return 1
            ;;
        *)
            log_error "Failed to verify job (HTTP $http_code)"
            return 1
            ;;
    esac
}

# =============================================================================
# Build Information Functions
# =============================================================================

# Get build information as JSON from Jenkins API
# Usage: get_build_info "job-name" "build-number"
# Returns: JSON with number, result, building, timestamp, duration, url fields
#          Empty string on failure
get_build_info() {
    local job_name="$1"
    local build_number="$2"

    jenkins_api "/job/${job_name}/${build_number}/api/json" 2>/dev/null || echo ""
}

# Get console text output for a build
# Usage: get_console_output "job-name" "build-number"
# Returns: Console text, empty string on failure
get_console_output() {
    local job_name="$1"
    local build_number="$2"

    jenkins_api "/job/${job_name}/${build_number}/consoleText" 2>/dev/null || echo ""
}

# Get currently executing stage name from workflow API
# Usage: get_current_stage "job-name" "build-number"
# Returns: Stage name if a stage is IN_PROGRESS, empty string otherwise
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

# Get first failed stage name from workflow API
# Usage: get_failed_stage "job-name" "build-number"
# Returns: Stage name if a stage is FAILED or UNSTABLE, empty string otherwise
get_failed_stage() {
    local job_name="$1"
    local build_number="$2"

    local response
    response=$(jenkins_api "/job/${job_name}/${build_number}/wfapi/describe" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.stages[] | select(.status == "FAILED" or .status == "UNSTABLE") | .name' 2>/dev/null | head -1
    fi
}

# Get the last build number for a job
# Usage: get_last_build_number "job-name"
# Returns: Build number (numeric), or 0 if no builds exist or on error
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

# =============================================================================
# Failure Analysis Functions
# =============================================================================

# Check if a build result indicates failure
# Usage: check_build_failed "job-name" "build-number"
# Returns: 0 if build failed (FAILURE, UNSTABLE, ABORTED), 1 otherwise
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

# Detect all downstream builds from console output
# Usage: detect_all_downstream_builds "$console_output"
# Returns: Space-separated pairs on each line: "job-name build-number"
detect_all_downstream_builds() {
    local console_output="$1"

    # Search for pattern: Starting building: <job-name> #<build-number>
    echo "$console_output" | grep -oE 'Starting building: [^ ]+ #[0-9]+' 2>/dev/null | \
        sed -E 's/Starting building: ([^ ]+) #([0-9]+)/\1 \2/' || true
}

# Find the failed downstream build from console output
# For parallel stages, checks each downstream build's status
# Usage: find_failed_downstream_build "$console_output"
# Returns: "job-name build-number" of the failed downstream build, or empty
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

# Extract error lines from console output
# Usage: extract_error_lines "$console_output" [max_lines]
# Returns: Lines matching error patterns, or last N lines as fallback
extract_error_lines() {
    local console_output="$1"
    local max_lines="${2:-50}"

    local error_lines
    error_lines=$(echo "$console_output" | grep -iE '(ERROR|Exception|FAILURE|failed|FATAL)' 2>/dev/null | tail -"$max_lines") || true

    if [[ -n "$error_lines" ]]; then
        echo "$error_lines"
    else
        # Fallback: show last 100 lines
        echo "$console_output" | tail -100
    fi
}

# Extract logs for a specific pipeline stage
# Usage: extract_stage_logs "$console_output" "stage-name"
# Returns: Console output lines for the specified stage
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

# Display build metadata from console output (user, agent, pipeline)
# Usage: display_build_metadata "$console_output"
# Outputs: Formatted build info section
display_build_metadata() {
    local console_output="$1"

    # Extract user who started the build
    local started_by
    started_by=$(echo "$console_output" | grep -m1 "^Started by user " | sed 's/^Started by user //') || true

    # Extract Jenkins agent
    local agent
    agent=$(echo "$console_output" | grep -m1 "^Running on " | sed 's/^Running on \([^ ]*\).*/\1/') || true

    # Extract pipeline source (pipeline name + git URL)
    # Format: "Obtained <pipeline-name> from git <url>"
    local pipeline
    pipeline=$(echo "$console_output" | grep -m1 "^Obtained .* from git " | sed 's|^Obtained ||') || true

    echo ""
    echo "${COLOR_CYAN}=== Build Info ===${COLOR_RESET}"
    [[ -n "$started_by" ]] && echo "  Started by:  $started_by"
    [[ -n "$agent" ]] && echo "  Agent:       $agent"
    [[ -n "$pipeline" ]] && echo "  Pipeline:    $pipeline"
    echo "${COLOR_CYAN}==================${COLOR_RESET}"
}

# Full failure analysis orchestration
# Usage: analyze_failure "job-name" "build-number"
# Outputs: Detailed failure report with error logs and metadata
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

    # Display build metadata (user, agent, pipeline) for failure context
    display_build_metadata "$console_output"

    # Check for downstream build failure
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

    # Find failed stage
    local failed_stage
    failed_stage=$(get_failed_stage "$job_name" "$build_number")

    if [[ -n "$failed_stage" ]]; then
        log_info "Failed stage: $failed_stage"

        # Try to extract stage-specific logs
        local stage_logs
        stage_logs=$(extract_stage_logs "$console_output" "$failed_stage")

        if [[ -n "$stage_logs" ]]; then
            echo ""
            echo "${COLOR_YELLOW}=== Stage '$failed_stage' Logs ===${COLOR_RESET}"
            extract_error_lines "$stage_logs" 50
            echo "${COLOR_YELLOW}=================================${COLOR_RESET}"
            echo ""
        else
            # Fallback to error extraction from full console
            echo ""
            echo "${COLOR_YELLOW}=== Build Errors ===${COLOR_RESET}"
            extract_error_lines "$console_output" 50
            echo "${COLOR_YELLOW}====================${COLOR_RESET}"
            echo ""
        fi
    else
        # No stage info - might be Jenkinsfile syntax error
        log_warning "Could not identify failed stage (possible Jenkinsfile syntax error)"
        echo ""
        echo "${COLOR_YELLOW}=== Console Output ===${COLOR_RESET}"
        extract_error_lines "$console_output" 100
        echo "${COLOR_YELLOW}======================${COLOR_RESET}"
        echo ""
    fi

    log_info "Full console output: ${JOB_URL}/${build_number}/console"
}
