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
        COLOR_DIM=$(tput dim 2>/dev/null || echo "")
    else
        COLOR_RESET=""
        COLOR_BLUE=""
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_RED=""
        COLOR_CYAN=""
        COLOR_BOLD=""
        COLOR_DIM=""
    fi
}

# Initialize colors on source
_init_colors

# =============================================================================
# Test Results Configuration
# =============================================================================
# Configuration for test failure display (can be overridden via environment)
# Spec: test-failure-display-spec.md, Section: Configuration

: "${MAX_FAILED_TESTS_DISPLAY:=10}"  # Maximum failed tests to show in detail
: "${MAX_ERROR_LINES:=5}"             # Maximum lines per error stack trace
: "${MAX_ERROR_LENGTH:=500}"          # Maximum characters per error message

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

# =============================================================================
# Verbosity-Aware Logging Functions
# =============================================================================
# These wrappers respect the VERBOSE_MODE setting.
# - Informational messages (info, success) are suppressed in quiet mode (default)
# - Warnings, errors, and essential output are always shown
# Spec reference: buildgit-spec.md, Verbosity Behavior

# INFO level - Only output if VERBOSE_MODE=true
# Use for: "Verifying Jenkins connectivity...", "Found job name", etc.
# Note: Output to stderr to avoid corrupting command substitution return values
bg_log_info() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_info "$@" >&2
    fi
}

# SUCCESS level - Only output if VERBOSE_MODE=true
# Use for: "Connected to Jenkins", "Job found", etc.
# Note: Output to stderr to avoid corrupting command substitution return values
bg_log_success() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log_success "$@" >&2
    fi
}

# WARNING level - Always output (warnings are important)
bg_log_warning() {
    log_warning "$@"
}

# ERROR level - Always output (errors are critical)
bg_log_error() {
    log_error "$@"
}

# ESSENTIAL level - Always output regardless of verbosity
# Use for: git command output, build results, test failures, final status
bg_log_essential() {
    echo "$@"
}

# PROGRESS level - Always output for real-time monitoring feedback
# Use for: stage completions, elapsed time updates during monitoring
# Note: Uses stderr to avoid corrupting any command substitution
# Spec reference: bug2026-02-01-buildgit-monitoring-spec.md, Issue 3
bg_log_progress() {
    log_info "$@" >&2
}

# PROGRESS_SUCCESS level - Always output for stage completion messages
# Use for: stage completion messages with checkmark formatting
# Note: Uses stderr to avoid corrupting any command substitution
# Spec reference: bug2026-02-01-buildgit-monitoring-spec.md, Issue 3
bg_log_progress_success() {
    log_success "$@" >&2
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

# Print the final build status line with color
# Usage: print_finished_line "SUCCESS"
# Output: "Finished: SUCCESS" in green (or appropriate color per status)
# Spec: unify-follow-log-spec.md, Section 4 (Build Completion)
print_finished_line() {
    local result="$1"
    local color=""

    case "$result" in
        SUCCESS)   color="${COLOR_GREEN}" ;;
        FAILURE)   color="${COLOR_RED}" ;;
        NOT_BUILT) color="${COLOR_RED}" ;;
        UNSTABLE)  color="${COLOR_YELLOW}" ;;
        ABORTED)   color="${COLOR_DIM}" ;;
        *)         color="${COLOR_RED}" ;;  # Default non-SUCCESS to red
    esac

    if [[ -n "$color" ]]; then
        echo "${color}Finished: ${result}${COLOR_RESET}"
    else
        echo "Finished: ${result}"
    fi
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
# Job Name Discovery Functions
# =============================================================================

# Discover Jenkins job name from AGENTS.md or git origin
# Priority: 1) AGENTS.md JOB_NAME, 2) git origin fallback
# Usage: discover_job_name
# Returns: Job name on stdout, returns 0 on success, 1 on failure
discover_job_name() {
    local job_name=""

    # Try AGENTS.md first
    job_name=$(_discover_job_from_agents_md)
    if [[ -n "$job_name" ]]; then
        echo "$job_name"
        return 0
    fi

    # Fallback to git origin
    job_name=$(_discover_job_from_git_origin)
    if [[ -n "$job_name" ]]; then
        echo "$job_name"
        return 0
    fi

    log_error "Could not determine Jenkins job name"
    log_info "Either create AGENTS.md with JOB_NAME=<job-name> or configure git origin"
    return 1
}

# Parse AGENTS.md for JOB_NAME pattern
# Flexible matching:
#   - JOB_NAME=myjob
#   - JOB_NAME = myjob
#   - - JOB_NAME=myjob
#   - Embedded in text: the job is JOB_NAME=myjob
# Returns: Job name or empty string
_discover_job_from_agents_md() {
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null) || return

    local agents_file="${git_root}/AGENTS.md"
    if [[ ! -f "$agents_file" ]]; then
        return
    fi

    # Extract JOB_NAME value with flexible matching
    # Pattern: JOB_NAME followed by optional whitespace, =, optional whitespace, then the value
    local job_name
    job_name=$(grep -oE 'JOB_NAME[[:space:]]*=[[:space:]]*[^[:space:]]+' "$agents_file" 2>/dev/null | head -1 | \
        sed -E 's/JOB_NAME[[:space:]]*=[[:space:]]*//')

    if [[ -n "$job_name" ]]; then
        echo "$job_name"
    fi
}

# Extract job name from git origin URL
# Supported formats:
#   - git@github.com:org/my-project.git → my-project
#   - https://github.com/org/my-project.git → my-project
#   - ssh://git@server:2233/home/git/ralph1.git → ralph1
#   - git@server:path/to/repo.git → repo
# Returns: Repository name (job name) or empty string
_discover_job_from_git_origin() {
    local origin_url
    origin_url=$(git remote get-url origin 2>/dev/null) || return

    local repo_name=""

    # Handle different URL formats
    if [[ "$origin_url" =~ ^https?:// ]]; then
        # HTTPS URL: https://github.com/org/my-project.git
        repo_name=$(basename "$origin_url")
    elif [[ "$origin_url" =~ ^ssh:// ]]; then
        # SSH URL with explicit protocol: ssh://git@server:2233/home/git/ralph1.git
        repo_name=$(basename "$origin_url")
    elif [[ "$origin_url" =~ ^git@ ]]; then
        # Git SSH shorthand: git@github.com:org/my-project.git or git@server:path/to/repo.git
        # Extract everything after the last / or :
        repo_name=$(echo "$origin_url" | sed -E 's|.*[:/]([^/]+)$|\1|')
    else
        # Unknown format, try basename
        repo_name=$(basename "$origin_url")
    fi

    # Strip .git suffix if present
    repo_name="${repo_name%.git}"

    if [[ -n "$repo_name" ]]; then
        echo "$repo_name"
    fi
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

    local response
    local http_code

    # Test basic connectivity
    response=$(jenkins_api_with_status "/api/json")
    http_code=$(echo "$response" | tail -1)

    case "$http_code" in
        200)
            bg_log_success "Connected to Jenkins"
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
    bg_log_info "Verifying job '$job_name' exists..."

    local response
    local http_code

    response=$(jenkins_api_with_status "/job/${job_name}/api/json")
    http_code=$(echo "$response" | tail -1)

    case "$http_code" in
        200)
            bg_log_success "Job '$job_name' found"
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
# Build Trigger Functions
# =============================================================================

# Trigger a new build for a Jenkins job
# Usage: trigger_build "job-name"
# Returns: 0 on success (build queued), 1 on failure
# Outputs: Queue item URL on stdout if successful
#
# Jenkins returns 201 Created with Location header containing queue item URL
# e.g., Location: http://jenkins/queue/item/123/
trigger_build() {
    local job_name="$1"

    local response http_code location_header

    # POST to the build endpoint
    # Use -D to capture headers to a temp file
    local header_file
    header_file=$(mktemp)

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
        -D "$header_file" \
        "${JENKINS_URL}/job/${job_name}/build")

    case "$http_code" in
        201)
            # Build queued successfully - extract Location header
            location_header=$(grep -i "^Location:" "$header_file" | sed 's/^Location:[[:space:]]*//' | tr -d '\r')
            rm -f "$header_file"

            if [[ -n "$location_header" ]]; then
                echo "$location_header"
            fi
            return 0
            ;;
        403)
            rm -f "$header_file"
            log_error "Permission denied to trigger build (403)"
            log_info "User may not have 'Build' permission for job '$job_name'"
            return 1
            ;;
        404)
            rm -f "$header_file"
            log_error "Job not found (404): $job_name"
            return 1
            ;;
        405)
            rm -f "$header_file"
            log_error "Build cannot be triggered (405)"
            log_info "Job may be disabled or not support builds"
            return 1
            ;;
        *)
            rm -f "$header_file"
            log_error "Failed to trigger build (HTTP $http_code)"
            return 1
            ;;
    esac
}

# Wait for a queued build to start executing
# Usage: wait_for_queue_item "queue-item-url" [timeout_seconds]
# Returns: Build number on stdout when build starts, or exits on timeout
# Polls the queue item API until the build starts
wait_for_queue_item() {
    local queue_url="$1"
    local timeout="${2:-120}"
    local expected_build_number="${3:-}"
    local elapsed=0
    local poll_interval=2
    local queue_confirmed=false
    local queue_line_active=false
    WAIT_FOR_QUEUE_ITEM_WHY=""
    WAIT_FOR_QUEUE_ITEM_IN_QUEUE_SINCE=""
    WAIT_FOR_QUEUE_ITEM_ID=""

    # Extract queue item ID from URL and construct API endpoint
    local queue_api_url
    if [[ "$queue_url" =~ /queue/item/([0-9]+) ]]; then
        queue_api_url="${JENKINS_URL}/queue/item/${BASH_REMATCH[1]}/api/json"
    else
        # Assume it's already a full URL, append /api/json
        queue_api_url="${queue_url%/}/api/json"
    fi

    while true; do
        local response
        response=$(curl -s -f -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$queue_api_url" 2>/dev/null) || true

        if [[ -n "$response" ]]; then
            queue_confirmed=true
            WAIT_FOR_QUEUE_ITEM_WHY=$(echo "$response" | jq -r '.why // empty' 2>/dev/null)
            WAIT_FOR_QUEUE_ITEM_IN_QUEUE_SINCE=$(echo "$response" | jq -r '.inQueueSince // empty' 2>/dev/null)
            WAIT_FOR_QUEUE_ITEM_ID=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)

            # Check if build has started (has executable.number)
            local build_number
            build_number=$(echo "$response" | jq -r '.executable.number // empty' 2>/dev/null)

            if [[ -n "$build_number" && "$build_number" != "null" ]]; then
                if [[ "$queue_line_active" == "true" ]]; then
                    printf '\r\033[K\n' >&2
                fi
                echo "$build_number"
                return 0
            fi

            # Check if cancelled
            local cancelled
            cancelled=$(echo "$response" | jq -r '.cancelled // false' 2>/dev/null)
            if [[ "$cancelled" == "true" ]]; then
                log_error "Build was cancelled while in queue"
                return 1
            fi

            if [[ -n "$WAIT_FOR_QUEUE_ITEM_WHY" ]]; then
                local msg
                if [[ -n "$expected_build_number" && "$expected_build_number" =~ ^[0-9]+$ ]]; then
                    msg="Build #${expected_build_number} is QUEUED — ${WAIT_FOR_QUEUE_ITEM_WHY}"
                else
                    msg="Build is QUEUED — ${WAIT_FOR_QUEUE_ITEM_WHY}"
                fi
                local queue_is_tty=false
                if [[ "${BUILDGIT_FORCE_TTY:-}" == "1" ]]; then
                    queue_is_tty=true
                elif [[ "${BUILDGIT_FORCE_TTY:-}" != "0" && -t 1 ]]; then
                    queue_is_tty=true
                fi
                if [[ "$queue_is_tty" == "true" ]]; then
                    printf '\r\033[K[%s] ℹ %s' "$(date +%H:%M:%S)" "$msg" >&2
                    queue_line_active=true
                else
                    log_info "$msg" >&2
                fi
            fi
        fi

        if [[ "$queue_confirmed" != "true" && "$elapsed" -ge "$timeout" ]]; then
            log_error "Timeout: Build did not start within ${timeout} seconds"
            return 1
        fi

        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done
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

# Fetch all stages with statuses and timing from wfapi/describe
# Usage: get_all_stages "job-name" "build-number"
# Returns: JSON array of stage objects on stdout
#          Each object has: name, status, startTimeMillis, durationMillis
#          Returns empty array [] on error or if no stages exist
# Spec: full-stage-print-spec.md, Section: API Data Source
get_all_stages() {
    local job_name="$1"
    local build_number="$2"

    local response
    response=$(jenkins_api "/job/${job_name}/${build_number}/wfapi/describe" 2>/dev/null) || true

    if [[ -z "$response" ]]; then
        echo "[]"
        return 0
    fi

    # Extract stages array with required fields
    # Handle missing fields gracefully with defaults
    local stages_json
    stages_json=$(echo "$response" | jq -r '
        .stages // [] |
        map({
            name: (.name // "unknown"),
            status: (.status // "NOT_EXECUTED"),
            startTimeMillis: (.startTimeMillis // 0),
            durationMillis: (.durationMillis // 0)
        })
    ' 2>/dev/null) || true

    if [[ -z "$stages_json" || "$stages_json" == "null" ]]; then
        echo "[]"
        return 0
    fi

    echo "$stages_json"
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
# Test Results Functions
# =============================================================================

# Fetch test results from Jenkins test report API
# Usage: fetch_test_results "job-name" "build-number"
# Returns: JSON test report on success, empty string if not available
# Spec: test-failure-display-spec.md, Section: Test Report Detection (1.1-1.2)
fetch_test_results() {
    local job_name="$1"
    local build_number="$2"

    local response
    local http_code
    local body

    # Query the test report API
    response=$(jenkins_api_with_status "/job/${job_name}/${build_number}/testReport/api/json")

    # Split response into body and status code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            # Test report available - return the JSON
            echo "$body"
            ;;
        404)
            # No test report available - silently return empty
            # This is expected for builds without junit results
            echo ""
            ;;
        *)
            # Other error - log warning and return empty
            log_warning "Failed to fetch test results (HTTP $http_code)"
            echo ""
            ;;
    esac
}

# Parse test report JSON and extract summary statistics
# Usage: parse_test_summary "$test_report_json"
# Returns: Four lines on stdout: total, passed, failed, skipped
# Spec: test-failure-display-spec.md, Section: Summary Statistics (2.1)
parse_test_summary() {
    local test_json="$1"

    # Handle empty or missing input
    if [[ -z "$test_json" ]]; then
        echo "0"
        echo "0"
        echo "0"
        echo "0"
        return 0
    fi

    # Extract counts using jq, defaulting to 0 for missing fields
    local fail_count pass_count skip_count total_count
    fail_count=$(echo "$test_json" | jq -r '.failCount // 0')
    pass_count=$(echo "$test_json" | jq -r '.passCount // 0')
    skip_count=$(echo "$test_json" | jq -r '.skipCount // 0')

    # Handle case where jq returns "null" string
    [[ "$fail_count" == "null" ]] && fail_count=0
    [[ "$pass_count" == "null" ]] && pass_count=0
    [[ "$skip_count" == "null" ]] && skip_count=0

    # Calculate total
    total_count=$((pass_count + fail_count + skip_count))

    # Output four lines
    echo "$total_count"
    echo "$pass_count"
    echo "$fail_count"
    echo "$skip_count"
}

# Parse test report JSON and extract failed test details
# Usage: parse_failed_tests "$test_report_json"
# Returns: JSON array of failed test objects on stdout
# Spec: test-failure-display-spec.md, Section: Failed Test Details (2.2-2.3)
parse_failed_tests() {
    local test_json="$1"

    # Handle empty or missing input
    if [[ -z "$test_json" ]]; then
        echo "[]"
        return 0
    fi

    # Use jq to extract failed tests with all required fields
    # - Iterates through suites[].cases[]
    # - Filters for status == "FAILED"
    # - Extracts className, name, errorDetails, errorStackTrace, duration, age
    # - Handles missing fields with defaults
    # - Limits to MAX_FAILED_TESTS_DISPLAY
    # - Truncates errorDetails to MAX_ERROR_LENGTH
    local max_display="${MAX_FAILED_TESTS_DISPLAY:-10}"
    local max_error_len="${MAX_ERROR_LENGTH:-500}"

    echo "$test_json" | jq -r --argjson max_display "$max_display" --argjson max_error_len "$max_error_len" '
        # Collect failed tests from BOTH direct suites path AND childReports path
        # This handles both freestyle jobs (.suites[].cases[]) and pipeline jobs (.childReports[].result.suites[].cases[])
        # Include both FAILED (recurring) and REGRESSION (newly broken) statuses
        # Spec: bug-no-testfail-stacktrace-shown-spec.md
        (
            [.suites[]?.cases[]? | select(.status == "FAILED" or .status == "REGRESSION")] +
            [.childReports[]?.result?.suites[]?.cases[]? | select(.status == "FAILED" or .status == "REGRESSION")]
        ) |

        # Remove duplicates (in case both paths exist)
        unique_by(.className + .name) |

        # Limit to max_display
        .[:$max_display] |

        # Transform each failed test
        map({
            className: (.className // "unknown"),
            name: (.name // "unknown"),
            errorDetails: (
                if (.errorDetails // "") == "" and (.errorStackTrace // "") == "" then
                    "No error details available"
                elif (.errorDetails // "") != "" then
                    (.errorDetails | tostring | .[:$max_error_len])
                else
                    null
                end
            ),
            errorStackTrace: (.errorStackTrace // null),
            duration: (.duration // 0),
            age: (.age // 0)
        })
    '
}

# Display test results in human-readable format
# Usage: display_test_results "$test_report_json"
# Outputs: Formatted test results section to stdout
# Spec: test-failure-display-spec.md, Section: Human-Readable Output (3.1-3.3)
display_test_results() {
    local test_json="$1"

    # Handle empty input - show placeholder
    # Spec: show-test-results-always-spec.md, Section 3
    if [[ -z "$test_json" ]]; then
        echo ""
        echo "=== Test Results ==="
        echo "  (no test results available)"
        echo "===================="
        return 0
    fi

    # Get summary statistics
    local summary
    summary=$(parse_test_summary "$test_json")

    local total passed failed skipped
    total=$(echo "$summary" | sed -n '1p')
    passed=$(echo "$summary" | sed -n '2p')
    failed=$(echo "$summary" | sed -n '3p')
    skipped=$(echo "$summary" | sed -n '4p')

    # Skip display if no tests at all
    if [[ "$total" -eq 0 ]]; then
        echo ""
        echo "=== Test Results ==="
        echo "  (no test results available)"
        echo "===================="
        return 0
    fi

    # Get failed test details
    local failed_tests
    failed_tests=$(parse_failed_tests "$test_json")

    # Count total failures in the original JSON (may be more than displayed)
    local total_failures
    total_failures=$(echo "$test_json" | jq -r '.failCount // 0')
    [[ "$total_failures" == "null" ]] && total_failures=0

    # Configuration
    local max_display="${MAX_FAILED_TESTS_DISPLAY:-10}"
    local max_error_lines="${MAX_ERROR_LINES:-5}"

    # Choose color based on failure count
    # Spec: show-test-results-always-spec.md, Section 2
    local section_color
    if [[ "$failed" -eq 0 ]]; then
        section_color="${COLOR_GREEN}"
    else
        section_color="${COLOR_YELLOW}"
    fi

    # Display header
    echo ""
    echo "${section_color}=== Test Results ===${COLOR_RESET}"

    # Display summary line
    echo "  ${section_color}Total: ${total} | Passed: ${passed} | Failed: ${failed} | Skipped: ${skipped}${COLOR_RESET}"

    # All tests passed - no failure details needed
    if [[ "$failed" -eq 0 ]]; then
        echo "${section_color}====================${COLOR_RESET}"
        return 0
    fi

    # Display failed tests header
    echo ""
    echo "  ${COLOR_RED}FAILED TESTS:${COLOR_RESET}"

    # Process each failed test
    local test_count
    test_count=$(echo "$failed_tests" | jq 'length')

    local i=0
    while [[ $i -lt $test_count ]]; do
        local class_name test_name error_details error_stack age

        class_name=$(echo "$failed_tests" | jq -r ".[$i].className")
        test_name=$(echo "$failed_tests" | jq -r ".[$i].name")
        error_details=$(echo "$failed_tests" | jq -r ".[$i].errorDetails // empty")
        error_stack=$(echo "$failed_tests" | jq -r ".[$i].errorStackTrace // empty")
        age=$(echo "$failed_tests" | jq -r ".[$i].age // 0")

        # Build test identifier line
        local age_suffix=""
        if [[ "$age" -gt 1 ]]; then
            age_suffix=" ${COLOR_YELLOW}(failing for ${age} builds)${COLOR_RESET}"
        fi

        echo "  ${COLOR_RED}✗${COLOR_RESET} ${class_name}::${test_name}${age_suffix}"

        # Display error details
        if [[ -n "$error_details" && "$error_details" != "null" ]]; then
            echo "    Error: ${error_details}"
        fi

        # Display stack trace (truncated to max lines)
        if [[ -n "$error_stack" && "$error_stack" != "null" ]]; then
            local line_count
            line_count=$(echo "$error_stack" | wc -l | tr -d ' ')

            if [[ "$line_count" -le "$max_error_lines" ]]; then
                # Display all lines with indent
                echo "$error_stack" | while IFS= read -r line; do
                    echo "    ${line}"
                done
            else
                # Display first max_error_lines lines with truncation indicator
                echo "$error_stack" | head -"$max_error_lines" | while IFS= read -r line; do
                    echo "    ${line}"
                done
                echo "    ..."
            fi
        fi

        i=$((i + 1))
    done

    # Show count of additional failures if truncated
    if [[ "$total_failures" -gt "$max_display" ]]; then
        local remaining=$((total_failures - max_display))
        echo "  ${COLOR_YELLOW}... and ${remaining} more failed tests${COLOR_RESET}"
    fi

    echo "${section_color}====================${COLOR_RESET}"
}

# Format test results as JSON for machine-readable output
# Usage: format_test_results_json "$test_report_json"
# Returns: JSON object with test summary and failed tests, or empty string if no data
# Spec: test-failure-display-spec.md, Section: JSON Output Enhancement (4.1-4.3)
format_test_results_json() {
    local test_json="$1"

    # Handle empty input - return empty string (caller should omit field)
    if [[ -z "$test_json" ]]; then
        echo ""
        return 0
    fi

    # Get summary statistics
    local summary
    summary=$(parse_test_summary "$test_json")

    local total passed failed skipped
    total=$(echo "$summary" | sed -n '1p')
    passed=$(echo "$summary" | sed -n '2p')
    failed=$(echo "$summary" | sed -n '3p')
    skipped=$(echo "$summary" | sed -n '4p')

    # Return empty if no tests at all
    if [[ "$total" -eq 0 ]]; then
        echo ""
        return 0
    fi

    # Get failed test details as JSON array
    local failed_tests_array
    failed_tests_array=$(parse_failed_tests "$test_json")

    # Transform the failed tests array to match expected JSON schema
    # Converting: className -> class_name, name -> test_name, duration -> duration_seconds
    local transformed_failed_tests
    transformed_failed_tests=$(echo "$failed_tests_array" | jq '
        map({
            class_name: .className,
            test_name: .name,
            duration_seconds: .duration,
            age: .age,
            error_details: .errorDetails,
            error_stack_trace: .errorStackTrace
        })
    ')

    # Build the final JSON object
    jq -n \
        --argjson total "$total" \
        --argjson passed "$passed" \
        --argjson failed "$failed" \
        --argjson skipped "$skipped" \
        --argjson failed_tests "$transformed_failed_tests" \
        '{
            total: $total,
            passed: $passed,
            failed: $failed,
            skipped: $skipped,
            failed_tests: $failed_tests
        }'
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
        if [[ -n "$result" && "$result" != "SUCCESS" ]]; then
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

# Select the best downstream build match for a given stage when multiple exist.
# This avoids mis-association when stage log extraction contains extra branch lines.
# Usage: _select_downstream_build_for_stage "Stage Name" "$downstream_lines"
# Returns: "job-name build-number" or empty
_select_downstream_build_for_stage() {
    local stage_name="$1"
    local downstream_lines="$2"

    [[ -z "$downstream_lines" ]] && return

    local line_count
    line_count=$(echo "$downstream_lines" | sed '/^[[:space:]]*$/d' | wc -l | tr -d '[:space:]')
    if [[ "$line_count" -le 1 ]]; then
        echo "$downstream_lines" | sed '/^[[:space:]]*$/d' | head -1
        return
    fi

    local stage_tokens
    stage_tokens=$(echo "$stage_name" | tr '[:upper:]' '[:lower:]' | \
        sed -E 's/[^a-z0-9]+/ /g; s/\b(build|trigger|stage|component|components)\b/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')

    local best_line=""
    local best_score=-1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local job build
        job=$(echo "$line" | awk '{print $1}')
        build=$(echo "$line" | awk '{print $2}')
        [[ -z "$job" || -z "$build" ]] && continue

        local job_lc score
        job_lc=$(echo "$job" | tr '[:upper:]' '[:lower:]')
        # Split job name into segments for word-level matching
        local job_segments
        job_segments=$(echo "$job_lc" | tr '-' ' ')
        score=0

        local token
        for token in $stage_tokens; do
            [[ ${#token} -lt 3 ]] && continue
            # Prefer exact segment match (score 2) over substring match (score 1)
            local seg matched_segment=false
            for seg in $job_segments; do
                if [[ "$seg" == "$token" ]]; then
                    matched_segment=true
                    break
                fi
            done
            if [[ "$matched_segment" == "true" ]]; then
                score=$((score + 2))
            elif [[ "$job_lc" == *"$token"* ]]; then
                score=$((score + 1))
            fi
        done

        if [[ "$score" -gt "$best_score" ]]; then
            best_score="$score"
            best_line="$line"
        elif [[ "$score" -eq "$best_score" && -n "$best_line" ]]; then
            local best_build
            best_build=$(echo "$best_line" | awk '{print $2}')
            if [[ "$build" =~ ^[0-9]+$ && "$best_build" =~ ^[0-9]+$ && "$build" -gt "$best_build" ]]; then
                best_line="$line"
            fi
        fi
    done <<< "$downstream_lines"

    if [[ -n "$best_line" ]]; then
        echo "$best_line"
    else
        echo "$downstream_lines" | sed '/^[[:space:]]*$/d' | tail -1
    fi
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
#
# This function correctly handles nested Pipeline blocks (e.g., dir, withEnv)
# by tracking nesting depth. It only stops when the nesting depth returns to 0,
# ensuring that post-stage actions (like junit) are included in the output.
extract_stage_logs() {
    local console_output="$1"
    local stage_name="$2"

    # Extract content between [Pipeline] { (StageName) and matching [Pipeline] }
    # Tracks nesting depth to handle nested Pipeline blocks
    local result
    result=$(echo "$console_output" | awk -v stage="$stage_name" '
        BEGIN { nesting_depth=0 }
        # Match stage start: [Pipeline] { (StageName)
        /\[Pipeline\] \{ \(/ && index($0, "(" stage ")") && nesting_depth == 0 {
            nesting_depth=1
            next
        }
        # Inside stage: track nested blocks and output lines
        nesting_depth > 0 {
            # Handle any block start: [Pipeline] { — including sub-stages and Branch: lines
            if (/\[Pipeline\] \{/) {
                nesting_depth++
                print
                next
            }
            # Handle block end: [Pipeline] }
            if (/\[Pipeline\] \}/) {
                nesting_depth--
                if (nesting_depth == 0) {
                    # Stage complete, stop processing
                    exit
                }
                print
                next
            }
            # Regular line inside stage
            print
        }
    ')

    # If no output, retry with "Branch: " prefix for parallel branch stages
    # Jenkins logs parallel branches as [Pipeline] { (Branch: StageName)
    # Spec: bug-parallel-stages-display-spec.md, Section: Parallel Detection
    if [[ -z "$result" ]]; then
        result=$(echo "$console_output" | awk -v stage="Branch: $stage_name" '
            BEGIN { nesting_depth=0 }
            /\[Pipeline\] \{ \(/ && index($0, "(" stage ")") && nesting_depth == 0 {
                nesting_depth=1
                next
            }
            nesting_depth > 0 {
                if (/\[Pipeline\] \{/) {
                    nesting_depth++
                    print
                    next
                }
                if (/\[Pipeline\] \}/) {
                    nesting_depth--
                    if (nesting_depth == 0) {
                        exit
                    }
                    print
                    next
                }
                print
            }
        ')
    fi

    echo "$result"
}

# Detect parallel branches within a wrapper stage from console output
# Usage: _detect_parallel_branches "$console_output" "wrapper-stage-name"
# Returns: JSON array of branch names, e.g. ["Build Handle", "Build SignalBoot"]
#          Returns empty string if stage is not a parallel wrapper
# Spec: bug-parallel-stages-display-spec.md, Section: Parallel Detection Function
_detect_parallel_branches() {
    local console_output="$1"
    local wrapper_stage="$2"

    # Scan ALL matching stage blocks in console output.
    # Some pipelines reuse stage names in nested/downstream logs; the first match
    # may be a non-parallel block. We only collect branches from blocks that
    # explicitly contain "[Pipeline] parallel".
    local branches
    branches=$(echo "$console_output" | awk -v stage="$wrapper_stage" '
        BEGIN {
            in_stage=0
            depth=0
            has_parallel=0
            branch_count=0
        }

        function flush_block(   i) {
            if (has_parallel) {
                for (i = 1; i <= branch_count; i++) {
                    print branch_order[i]
                }
            }
            delete branch_seen
            delete branch_order
            branch_count=0
            has_parallel=0
        }

        # Start a new matching stage block when not already inside one
        /\[Pipeline\] \{ \(/ && index($0, "(" stage ")") && in_stage == 0 {
            in_stage=1
            depth=1
            has_parallel=0
            branch_count=0
            delete branch_seen
            delete branch_order
            next
        }

        in_stage == 1 {
            if ($0 ~ /^\[Pipeline\] parallel$/) {
                has_parallel=1
            }

            if (match($0, /\(Branch: [^)]+\)/)) {
                branch = substr($0, RSTART + 9, RLENGTH - 10)
                if (!(branch in branch_seen)) {
                    branch_seen[branch]=1
                    branch_order[++branch_count]=branch
                }
            }

            if ($0 ~ /\[Pipeline\] \{/) {
                depth++
                next
            }

            if ($0 ~ /\[Pipeline\] \}/) {
                depth--
                if (depth == 0) {
                    flush_block()
                    in_stage=0
                }
                next
            }
        }

        END {
            # Monitoring mode often reads console output before the wrapper
            # closes. Flush any in-progress matching block so branch numbering
            # is available during live display, not only after completion.
            if (in_stage == 1) {
                flush_block()
            }
        }
    ' | awk '!seen[$0]++')

    if [[ -z "$branches" ]]; then
        echo ""
        return
    fi

    local json_array="[]"
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        json_array=$(echo "$json_array" | jq --arg b "$branch" '. + [$b]')
    done <<< "$branches"

    echo "$json_array"
}

# Parse build metadata from console output
# Usage: _parse_build_metadata "$console_output"
# Sets: _META_STARTED_BY, _META_AGENT, _META_PIPELINE
_extract_running_agent_from_console() {
    local console_output="$1"
    local stripped_console

    # Remove ANSI escape sequences so matching works on colorized console text.
    stripped_console=$(printf "%s\n" "$console_output" | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g')

    printf "%s\n" "$stripped_console" | grep -m1 "Running on " | \
        sed -E 's/.*Running on[[:space:]]+([^[:space:]]+).*/\1/' || true
}

_parse_build_metadata() {
    local console_output="$1"

    # Extract user who started the build
    _META_STARTED_BY=$(echo "$console_output" | grep -m1 "^Started by user " | sed 's/^Started by user //') || true

    # Extract Jenkins agent
    _META_AGENT=$(_extract_running_agent_from_console "$console_output") || true

    # Extract pipeline source (pipeline name + git URL)
    # Format: "Obtained <pipeline-name> from git <url>"
    _META_PIPELINE=$(echo "$console_output" | grep -m1 "^Obtained .* from git " | sed 's|^Obtained ||') || true
}

# Display build metadata from console output (user, agent, pipeline)
# Usage: display_build_metadata "$console_output"
# Outputs: Formatted build info section
display_build_metadata() {
    local console_output="$1"

    _parse_build_metadata "$console_output"

    echo ""
    echo "${COLOR_CYAN}=== Build Info ===${COLOR_RESET}"
    [[ -n "$_META_STARTED_BY" ]] && echo "  Started by:  $_META_STARTED_BY"
    [[ -n "$_META_AGENT" ]] && echo "  Agent:       $_META_AGENT"
    [[ -n "$_META_PIPELINE" ]] && echo "  Pipeline:    $_META_PIPELINE"
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

    # Display test results if available
    # Spec: test-failure-display-spec.md, Section: Integration Points (5.1)
    local test_results_json
    test_results_json=$(fetch_test_results "$job_name" "$build_number")
    if [[ -n "$test_results_json" ]]; then
        display_test_results "$test_results_json"
    fi

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

# =============================================================================
# Trigger Detection Functions
# =============================================================================

# Default trigger user that indicates automated builds (can be overridden)
: "${CHECKBUILD_TRIGGER_USER:=buildtriggerdude}"

# Detect trigger type from console output
# Usage: detect_trigger_type "$console_output"
# Returns: Outputs two lines: type ("automated" or "manual") and username
#          Returns 0 always; outputs 'unknown' if trigger cannot be determined
detect_trigger_type() {
    local console_output="$1"

    # Extract "Started by user <username>" from console
    local started_by_line
    started_by_line=$(echo "$console_output" | grep -m1 "^Started by user " 2>/dev/null) || true

    if [[ -z "$started_by_line" ]]; then
        # Check for other trigger patterns
        if echo "$console_output" | grep -q "^Started by an SCM change" 2>/dev/null; then
            echo "automated"
            echo "scm-trigger"
            return 0
        elif echo "$console_output" | grep -q "^Started by timer" 2>/dev/null; then
            echo "automated"
            echo "timer"
            return 0
        elif echo "$console_output" | grep -q "^Started by upstream project" 2>/dev/null; then
            echo "automated"
            echo "upstream"
            return 0
        fi
        echo "unknown"
        echo "unknown"
        return 0
    fi

    # Extract username
    local username
    username=$(echo "$started_by_line" | sed 's/^Started by user //')

    # Compare against trigger user (case-insensitive, portable)
    local username_lower trigger_lower
    username_lower=$(echo "$username" | tr '[:upper:]' '[:lower:]')
    trigger_lower=$(echo "$CHECKBUILD_TRIGGER_USER" | tr '[:upper:]' '[:lower:]')

    if [[ "$username_lower" == "$trigger_lower" ]]; then
        echo "automated"
        echo "$username"
    else
        echo "manual"
        echo "$username"
    fi
    return 0
}

# Extract triggering commit SHA and message from build
# Usage: extract_triggering_commit "job-name" "build-number" ["$console_output"]
# Returns: Outputs two lines: SHA and commit message (each may be "unknown" if not found)
extract_triggering_commit() {
    local job_name="$1"
    local build_number="$2"
    local console_output="${3:-}"

    local sha=""
    local message=""

    # Method 1: Try to get from build API (lastBuiltRevision.SHA1)
    local build_info
    build_info=$(get_build_info "$job_name" "$build_number")

    if [[ -n "$build_info" ]]; then
        # Look for GitSCM action with lastBuiltRevision
        sha=$(echo "$build_info" | jq -r '
            .actions[]? |
            select(._class? | test("hudson.plugins.git"; "i") // false) |
            .lastBuiltRevision?.SHA1 // .buildsByBranchName?["*/main"]?.revision?.SHA1 // .buildsByBranchName?["*/master"]?.revision?.SHA1 // empty
        ' 2>/dev/null | head -1) || true

        # Also try alternate location for Git action
        if [[ -z "$sha" ]]; then
            sha=$(echo "$build_info" | jq -r '
                .actions[]? |
                select(.lastBuiltRevision?) |
                .lastBuiltRevision.SHA1 // empty
            ' 2>/dev/null | head -1) || true
        fi
    fi

    # Method 2: Parse from console output if not found in API
    if [[ -z "$sha" && -n "$console_output" ]]; then
        # Try "Checking out Revision <sha>"
        sha=$(echo "$console_output" | grep -oE 'Checking out Revision [a-f0-9]{7,40}' 2>/dev/null | head -1 | \
            sed 's/Checking out Revision //') || true
    fi

    if [[ -z "$sha" && -n "$console_output" ]]; then
        # Try "> git checkout -f <sha>"
        sha=$(echo "$console_output" | grep -oE '> git checkout -f [a-f0-9]{7,40}' 2>/dev/null | head -1 | \
            sed 's/> git checkout -f //') || true
    fi

    if [[ -z "$sha" && -n "$console_output" ]]; then
        # Try "Commit <sha>" pattern
        sha=$(echo "$console_output" | grep -oE 'Commit [a-f0-9]{7,40}' 2>/dev/null | head -1 | \
            sed 's/Commit //') || true
    fi

    # If we still don't have console output and need to parse for message, fetch it
    if [[ -z "$console_output" ]]; then
        console_output=$(get_console_output "$job_name" "$build_number")
    fi

    # Extract commit message from console
    if [[ -n "$console_output" ]]; then
        # Try "Commit message: "<message>""
        message=$(echo "$console_output" | grep -m1 'Commit message:' 2>/dev/null | \
            sed -E 's/.*Commit message:[[:space:]]*//' | sed -E 's/^["'"'"'](.*)["'"'"']$/\1/') || true

        # Try to get from git show format if available
        if [[ -z "$message" && -n "$sha" ]]; then
            # Pattern: <sha> <message> in git log style output
            message=$(echo "$console_output" | grep -m1 "^${sha:0:7}" 2>/dev/null | \
                sed -E "s/^[a-f0-9]+[[:space:]]+//") || true
        fi
    fi

    # Output results (unknown if not found)
    echo "${sha:-unknown}"
    echo "${message:-unknown}"
    return 0
}

# =============================================================================
# Output Formatting Functions
# =============================================================================

# Format duration from milliseconds to human-readable format
# Usage: format_duration 154000
# Returns: "2m 34s" or "45s" or "1h 5m 30s"
format_duration() {
    local ms="$1"

    # Handle empty or invalid input
    if [[ -z "$ms" || "$ms" == "null" || ! "$ms" =~ ^[0-9]+$ ]]; then
        echo "unknown"
        return
    fi

    local total_seconds=$((ms / 1000))
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))

    if [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${seconds}s"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Format stage duration from milliseconds to human-readable format
# Extends format_duration with sub-second handling for pipeline stages
# Usage: format_stage_duration 154000
# Returns: "2m 34s", "45s", "<1s", "1h 5m 30s", or "unknown"
# Spec: full-stage-print-spec.md, Section: Duration format
format_stage_duration() {
    local ms="$1"

    # Handle empty or invalid input
    if [[ -z "$ms" || "$ms" == "null" || ! "$ms" =~ ^[0-9]+$ ]]; then
        echo "unknown"
        return
    fi

    # For sub-second durations (< 1000ms), return "<1s"
    if [[ "$ms" -lt 1000 ]]; then
        echo "<1s"
        return
    fi

    # For durations >= 1 second, delegate to format_duration
    format_duration "$ms"
}

# Print a single stage line with appropriate color and format
# Usage: print_stage_line "stage-name" "status" [duration_ms] [indent] [agent_prefix] [parallel_marker]
# status: SUCCESS, FAILED, UNSTABLE, IN_PROGRESS, NOT_EXECUTED, ABORTED
# indent: string of spaces for nesting (e.g., "  " for depth 1)
# agent_prefix: "[agent-name] " prepended to stage name
# parallel_marker: "║ " for parallel branch stages (default empty)
# Output format: [HH:MM:SS] ℹ   Stage: <indent><parallel_marker>[agent] <name> (<duration>)
# Spec: full-stage-print-spec.md, Section: Stage Display Format
# Spec: nested-jobs-display-spec.md, Section: Nested Stage Line Format
# Spec: bug-parallel-stages-display-spec.md, Section: Visual Parallel Stage Indication
_format_agent_prefix() {
    local agent_prefix="${1:-}"
    local agent_name=""

    if [[ "$agent_prefix" =~ ^\[(.*)\][[:space:]]*$ ]]; then
        agent_name="${BASH_REMATCH[1]}"
    elif [[ "$agent_prefix" =~ ^\[(.*)\][[:space:]] ]]; then
        agent_name="${BASH_REMATCH[1]}"
    else
        echo "$agent_prefix"
        return
    fi

    if [[ ${#agent_name} -gt 14 ]]; then
        agent_name="${agent_name:0:14}"
    fi

    printf "[%-14s] " "$agent_name"
}

print_stage_line() {
    local stage_name="$1"
    local status="$2"
    local duration_ms="${3:-}"
    local indent="${4:-}"
    local agent_prefix="${5:-}"
    local parallel_marker="${6:-}"

    local timestamp
    timestamp=$(_timestamp)

    local color=""
    local suffix=""
    local marker=""
    local formatted_agent_prefix
    formatted_agent_prefix=$(_format_agent_prefix "$agent_prefix")

    case "$status" in
        SUCCESS)
            color="${COLOR_GREEN}"
            suffix="$(format_stage_duration "$duration_ms")"
            ;;
        FAILED)
            color="${COLOR_RED}"
            suffix="$(format_stage_duration "$duration_ms")"
            marker="    ${COLOR_RED}← FAILED${COLOR_RESET}"
            ;;
        UNSTABLE)
            color="${COLOR_YELLOW}"
            suffix="$(format_stage_duration "$duration_ms")"
            ;;
        IN_PROGRESS)
            color="${COLOR_CYAN}"
            suffix="running"
            ;;
        NOT_EXECUTED)
            color="${COLOR_DIM}"
            suffix="not executed"
            ;;
        ABORTED)
            color="${COLOR_RED}"
            suffix="aborted"
            ;;
        *)
            # Unknown status - use default
            color=""
            suffix="$(format_stage_duration "$duration_ms")"
            ;;
    esac

    # Build and output the stage line
    # Format: [HH:MM:SS] ℹ   Stage: <indent><parallel_marker>[agent] <name> (<suffix>)
    echo "${color}[${timestamp}] ℹ   Stage: ${indent}${parallel_marker}${formatted_agent_prefix}${stage_name} (${suffix})${COLOR_RESET}${marker}"
}

# Display stages from a build (with nested downstream stage expansion)
# Usage: _display_stages "job-name" "build-number" [--completed-only]
# When --completed-only: skips IN_PROGRESS/NOT_EXECUTED, saves state to _BANNER_STAGES_JSON
# Outputs: Stage lines to stdout in execution order
# Spec: full-stage-print-spec.md, Section: Display Functions
# Spec: bug-show-all-stages.md - never show "(running)" in initial display
# Spec: nested-jobs-display-spec.md - inline nested stage display
_display_stages() {
    local job_name="$1"
    local build_number="$2"
    local completed_only=false
    if [[ "${3:-}" == "--completed-only" ]]; then
        completed_only=true
    fi

    # Get nested stages (includes downstream expansion)
    local nested_stages_json
    nested_stages_json=$(_get_nested_stages "$job_name" "$build_number" 2>/dev/null) || nested_stages_json="[]"

    # Fallback to flat stages if nested fetch fails
    if [[ -z "$nested_stages_json" || "$nested_stages_json" == "[]" || "$nested_stages_json" == "null" ]]; then
        local stages_json
        stages_json=$(get_all_stages "$job_name" "$build_number")

        # Save full stages JSON for monitor initialization when in completed-only mode
        if [[ "$completed_only" == "true" ]]; then
            _BANNER_STAGES_JSON="${stages_json:-[]}"
        fi

        if [[ -z "$stages_json" || "$stages_json" == "[]" || "$stages_json" == "null" ]]; then
            return 0
        fi

        # Display flat stages (backward compatible)
        local stage_count
        stage_count=$(echo "$stages_json" | jq 'length')
        local i=0
        while [[ $i -lt $stage_count ]]; do
            local stage_name status duration_ms
            stage_name=$(echo "$stages_json" | jq -r ".[$i].name")
            status=$(echo "$stages_json" | jq -r ".[$i].status")
            duration_ms=$(echo "$stages_json" | jq -r ".[$i].durationMillis")

            if [[ "$completed_only" == "true" ]]; then
                case "$status" in
                    SUCCESS|FAILED|UNSTABLE|ABORTED)
                        print_stage_line "$stage_name" "$status" "$duration_ms"
                        ;;
                esac
            else
                print_stage_line "$stage_name" "$status" "$duration_ms"
            fi
            i=$((i + 1))
        done
        return 0
    fi

    # Save full stages JSON for monitor initialization when in completed-only mode
    # We save just the parent build's stages for tracking state
    if [[ "$completed_only" == "true" ]]; then
        _BANNER_STAGES_JSON=$(get_all_stages "$job_name" "$build_number") || _BANNER_STAGES_JSON="[]"
    fi

    # Display nested stages with proper indentation and agent prefixes
    _display_nested_stages_json "$nested_stages_json" "$completed_only"
}

# Display nested stages from a pre-built JSON array
# Usage: _display_nested_stages_json "$nested_stages_json" "$completed_only"
# Spec: bug-parallel-stages-display-spec.md, Section: Visual Parallel Stage Indication
_display_nested_stages_json() {
    local nested_stages_json="$1"
    local completed_only="${2:-false}"

    local stage_count
    stage_count=$(echo "$nested_stages_json" | jq 'length')

    local i=0
    while [[ $i -lt $stage_count ]]; do
        local stage_name status duration_ms agent nesting_depth
        stage_name=$(echo "$nested_stages_json" | jq -r ".[$i].name")
        status=$(echo "$nested_stages_json" | jq -r ".[$i].status")
        duration_ms=$(echo "$nested_stages_json" | jq -r ".[$i].durationMillis")
        agent=$(echo "$nested_stages_json" | jq -r ".[$i].agent // empty")
        nesting_depth=$(echo "$nested_stages_json" | jq -r ".[$i].nesting_depth // 0")

        # Check for parallel branch/path annotations
        local parallel_branch
        parallel_branch=$(echo "$nested_stages_json" | jq -r ".[$i].parallel_branch // empty")
        local parallel_path
        parallel_path=$(echo "$nested_stages_json" | jq -r ".[$i].parallel_path // empty")

        # Build indentation (2 spaces per nesting level)
        local indent=""
        local d=0
        while [[ $d -lt $nesting_depth ]]; do
            indent="${indent}  "
            d=$((d + 1))
        done

        # Determine parallel marker
        local parallel_marker=""
        if [[ -n "$parallel_path" ]]; then
            parallel_marker="║${parallel_path} "
            # For parallel branches at depth 0, add indent
            if [[ $nesting_depth -eq 0 ]]; then
                indent="  "
            fi
        elif [[ -n "$parallel_branch" ]]; then
            parallel_marker="║ "
            if [[ $nesting_depth -eq 0 ]]; then
                indent="  "
            fi
        fi

        # Build agent prefix
        local agent_prefix=""
        if [[ -n "$agent" ]]; then
            agent_prefix="[${agent}] "
        fi

        if [[ "$completed_only" == "true" ]]; then
            case "$status" in
                SUCCESS|FAILED|UNSTABLE|ABORTED)
                    print_stage_line "$stage_name" "$status" "$duration_ms" "$indent" "$agent_prefix" "$parallel_marker"
                    ;;
            esac
        else
            print_stage_line "$stage_name" "$status" "$duration_ms" "$indent" "$agent_prefix" "$parallel_marker"
        fi

        i=$((i + 1))
    done
}

# Convenience aliases for backward compatibility in callers
_display_all_stages() {
    _display_stages "$1" "$2"
}

_display_completed_stages() {
    _display_stages "$1" "$2" --completed-only
}

# Track stage state changes and print completed stages
# Usage: new_state=$(track_stage_changes "job-name" "build-number" "$previous_state" "$verbose")
# Returns: Current stages JSON on stdout (capture for next iteration)
# Side effect: Prints completed/running stage lines to stderr
# Spec: full-stage-print-spec.md, Section: Stage Tracking
track_stage_changes() {
    local job_name="$1"
    local build_number="$2"
    local previous_stages_json="${3:-[]}"
    local verbose="${4:-false}"

    # Fetch current stages
    local current_stages_json
    current_stages_json=$(get_all_stages "$job_name" "$build_number")

    # Handle empty or invalid previous state
    if [[ -z "$previous_stages_json" || "$previous_stages_json" == "null" ]]; then
        previous_stages_json="[]"
    fi

    # Handle empty current stages - just return previous state unchanged
    if [[ "$current_stages_json" == "[]" ]]; then
        echo "$previous_stages_json"
        return 0
    fi

    # Process each stage and detect transitions
    local stage_count
    stage_count=$(echo "$current_stages_json" | jq 'length')

    # Check if this is the first poll (previous state was empty)
    local prev_count
    prev_count=$(echo "$previous_stages_json" | jq 'length')

    local i=0

    while [[ $i -lt $stage_count ]]; do
        local stage_name current_status duration_ms
        stage_name=$(echo "$current_stages_json" | jq -r ".[$i].name")
        current_status=$(echo "$current_stages_json" | jq -r ".[$i].status")
        duration_ms=$(echo "$current_stages_json" | jq -r ".[$i].durationMillis")

        # Get previous status for this stage (by name)
        local previous_status
        previous_status=$(echo "$previous_stages_json" | jq -r --arg name "$stage_name" \
            '.[] | select(.name == $name) | .status // "NOT_EXECUTED"')

        # Default to NOT_EXECUTED if stage wasn't in previous state
        if [[ -z "$previous_status" ]]; then
            previous_status="NOT_EXECUTED"
        fi

        # Detect transitions and print completed stages
        case "$current_status" in
            SUCCESS|FAILED|UNSTABLE|ABORTED)
                # Print if stage transitioned from IN_PROGRESS or appeared already completed
                # The NOT_EXECUTED case catches fast stages that complete between polls
                # Spec: bug-show-all-stages.md - all stages must be shown
                if [[ "$previous_status" == "IN_PROGRESS" || "$previous_status" == "NOT_EXECUTED" ]]; then
                    print_stage_line "$stage_name" "$current_status" "$duration_ms" >&2
                fi
                ;;
            IN_PROGRESS)
                # Only print running stage in verbose mode, and only once when it first starts
                # Non-verbose mode: no "(running)" output - only print when stages complete
                if [[ "$verbose" == "true" && "$previous_status" == "NOT_EXECUTED" ]]; then
                    print_stage_line "$stage_name" "IN_PROGRESS" >&2
                fi
                ;;
        esac

        i=$((i + 1))
    done

    # Return current state for next iteration
    echo "$current_stages_json"
}

# Track nested stage changes for monitoring mode
# Wraps track_stage_changes() to also track downstream build stages
# Usage: new_state=$(_track_nested_stage_changes "job-name" "build-number" "$previous_composite_state" "$verbose")
# Returns: Composite state JSON on stdout (capture for next iteration)
# Side effect: Prints completed/running stage lines to stderr (with nesting)
# Spec: nested-jobs-display-spec.md, Section: Monitoring Mode Behavior
# Spec: bug-parallel-stages-display-spec.md, Section: Stage Tracker Changes
_track_nested_stage_changes() {
    local job_name="$1"
    local build_number="$2"
    local previous_composite_state="${3:-}"
    local verbose="${4:-false}"

    local previous_nested="[]"
    local printed_state="{}"
    local prev_type=""
    if [[ -n "$previous_composite_state" && "$previous_composite_state" != "[]" && "$previous_composite_state" != "null" ]]; then
        prev_type=$(echo "$previous_composite_state" | jq -r 'type' 2>/dev/null) || prev_type=""
        if [[ "$prev_type" == "object" ]]; then
            previous_nested=$(echo "$previous_composite_state" | jq '.nested // []')
            printed_state=$(echo "$previous_composite_state" | jq '.printed // {}')
        elif [[ "$prev_type" == "array" ]]; then
            # Backward compatibility: banner snapshot used a flat stage array.
            previous_nested="$previous_composite_state"
        fi
    fi

    # Seed printed-state from previously seen statuses so completed stages that
    # were already shown in the banner are not re-printed during the first poll.
    # Only seed from flat arrays (banner transition); composite objects already
    # carry an accurate .printed state that respects deferral decisions.
    if [[ "$prev_type" != "object" && -n "$previous_nested" && "$previous_nested" != "[]" ]]; then
        local seeded_printed="{}"
        seeded_printed=$(echo "$previous_nested" | jq '
            reduce .[] as $s ({};
                if ($s.status == "SUCCESS" or $s.status == "FAILED" or $s.status == "UNSTABLE" or $s.status == "ABORTED") then
                    . + {($s.name): ((.[$s.name] // {}) + {terminal: true})}
                elif ($s.status == "IN_PROGRESS") then
                    . + {($s.name): ((.[$s.name] // {}) + {running: true})}
                else
                    .
                end
            )' 2>/dev/null) || seeded_printed="{}"
        printed_state=$(echo "$seeded_printed" "$printed_state" | jq -s '.[0] * .[1]' 2>/dev/null) || printed_state="$seeded_printed"
    fi

    local current_parent_stages
    current_parent_stages=$(get_all_stages "$job_name" "$build_number" 2>/dev/null) || current_parent_stages="[]"

    local current_nested
    current_nested=$(_get_nested_stages "$job_name" "$build_number" 2>/dev/null) || current_nested="[]"
    if [[ -z "$current_nested" || "$current_nested" == "null" ]]; then
        current_nested="[]"
    fi

    local stage_count
    stage_count=$(echo "$current_nested" | jq 'length' 2>/dev/null) || stage_count=0
    local i=0
    while [[ $i -lt $stage_count ]]; do
        local stage_name current_status duration_ms agent nesting_depth parallel_path parallel_branch
        stage_name=$(echo "$current_nested" | jq -r ".[$i].name")
        current_status=$(echo "$current_nested" | jq -r ".[$i].status")
        duration_ms=$(echo "$current_nested" | jq -r ".[$i].durationMillis")
        agent=$(echo "$current_nested" | jq -r ".[$i].agent // empty")
        nesting_depth=$(echo "$current_nested" | jq -r ".[$i].nesting_depth // 0")
        parallel_path=$(echo "$current_nested" | jq -r ".[$i].parallel_path // empty")
        parallel_branch=$(echo "$current_nested" | jq -r ".[$i].parallel_branch // empty")

        local previous_status
        previous_status=$(echo "$previous_nested" | jq -r --arg n "$stage_name" '.[] | select(.name == $n) | .status // "NOT_EXECUTED"' 2>/dev/null)
        [[ -z "$previous_status" ]] && previous_status="NOT_EXECUTED"

        local indent=""
        local d=0
        while [[ $d -lt $nesting_depth ]]; do
            indent="${indent}  "
            d=$((d + 1))
        done

        local parallel_marker=""
        if [[ -n "$parallel_path" ]]; then
            parallel_marker="║${parallel_path} "
            if [[ $nesting_depth -eq 0 ]]; then
                indent="  "
            fi
        elif [[ -n "$parallel_branch" ]]; then
            parallel_marker="║ "
            if [[ $nesting_depth -eq 0 ]]; then
                indent="  "
            fi
        fi

        local agent_prefix=""
        if [[ -n "$agent" ]]; then
            agent_prefix="[${agent}] "
        fi

        local printed_terminal printed_running
        printed_terminal=$(echo "$printed_state" | jq -r --arg s "$stage_name" '.[$s].terminal // false' 2>/dev/null)
        printed_running=$(echo "$printed_state" | jq -r --arg s "$stage_name" '.[$s].running // false' 2>/dev/null)
        [[ -z "$printed_terminal" ]] && printed_terminal="false"
        [[ -z "$printed_running" ]] && printed_running="false"

        case "$current_status" in
            SUCCESS|FAILED|UNSTABLE|ABORTED)
                if [[ "$printed_terminal" != "true" ]]; then
                    local allow_print=true
                    if [[ "$verbose" != "true" ]]; then
                        if [[ -z "$duration_ms" || "$duration_ms" == "null" || ! "$duration_ms" =~ ^[0-9]+$ ]]; then
                            allow_print=false
                        fi
                    fi
                    # Defer parallel wrapper until all branches are terminal
                    if [[ "$allow_print" == "true" ]]; then
                        local is_pw has_ds
                        is_pw=$(echo "$current_nested" | jq -r ".[$i].is_parallel_wrapper // false")
                        has_ds=$(echo "$current_nested" | jq -r ".[$i].has_downstream // false")
                        if [[ "$is_pw" == "true" ]]; then
                            local pw_branches pw_all_terminal
                            pw_branches=$(echo "$current_nested" | jq -r ".[$i].parallel_branches // [] | .[]")
                            pw_all_terminal="true"
                            local pw_branch
                            while IFS= read -r pw_branch; do
                                [[ -z "$pw_branch" ]] && continue
                                local pw_branch_status
                                pw_branch_status=$(echo "$current_nested" | jq -r --arg b "$pw_branch" '.[] | select(.name == $b) | .status // "UNKNOWN"')
                                case "$pw_branch_status" in
                                    SUCCESS|FAILED|UNSTABLE|ABORTED) ;;
                                    *) pw_all_terminal="false"; break ;;
                                esac
                            done <<< "$pw_branches"
                            if [[ "$pw_all_terminal" != "true" ]]; then
                                allow_print=false
                            fi
                        fi
                        # Defer downstream parent until at least one child stage appears
                        if [[ "$allow_print" == "true" && "$has_ds" == "true" ]]; then
                            local ds_child_count
                            ds_child_count=$(echo "$current_nested" | jq --arg pfx "${stage_name}->" '[.[] | select(.name | startswith($pfx))] | length')
                            if [[ "$ds_child_count" -eq 0 ]]; then
                                allow_print=false
                            fi
                        fi
                    fi
                    if [[ "$allow_print" == "true" ]]; then
                        print_stage_line "$stage_name" "$current_status" "$duration_ms" "$indent" "$agent_prefix" "$parallel_marker" >&2
                        printed_state=$(echo "$printed_state" | jq --arg s "$stage_name" '.[$s] = ((.[$s] // {}) + {terminal: true})')
                    fi
                fi
                ;;
            IN_PROGRESS)
                if [[ "$verbose" == "true" && "$printed_running" != "true" && "$previous_status" == "NOT_EXECUTED" ]]; then
                    print_stage_line "$stage_name" "IN_PROGRESS" "" "$indent" "$agent_prefix" "$parallel_marker" >&2
                    printed_state=$(echo "$printed_state" | jq --arg s "$stage_name" '.[$s] = ((.[$s] // {}) + {running: true})')
                fi
                ;;
        esac

        i=$((i + 1))
    done

    # Return composite state with legacy keys retained for test/backward compatibility
    jq -n \
        --argjson parent "$current_parent_stages" \
        --argjson downstream "{}" \
        --argjson stage_downstream_map "{}" \
        --argjson parallel_info "{}" \
        --argjson nested "$current_nested" \
        --argjson printed "$printed_state" \
        '{parent: $parent, downstream: $downstream, stage_downstream_map: $stage_downstream_map, parallel_info: $parallel_info, nested: $nested, printed: $printed}'
}

# Format epoch timestamp (milliseconds) to human-readable date
# Usage: format_timestamp 1705329125000
# Returns: "2024-01-15 14:32:05"
format_timestamp() {
    local epoch_ms="$1"

    # Handle empty or invalid input
    if [[ -z "$epoch_ms" || "$epoch_ms" == "null" || ! "$epoch_ms" =~ ^[0-9]+$ ]]; then
        echo "unknown"
        return
    fi

    local epoch_seconds=$((epoch_ms / 1000))

    # Use date command (macOS and Linux compatible)
    if [[ "$(uname)" == "Darwin" ]]; then
        date -r "$epoch_seconds" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown"
    else
        date -d "@$epoch_seconds" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown"
    fi
}

# Format ISO 8601 timestamp from epoch milliseconds (for JSON output)
# Usage: format_timestamp_iso 1705329125000
# Returns: "2024-01-15T14:32:05Z"
format_timestamp_iso() {
    local epoch_ms="$1"

    # Handle empty or invalid input
    if [[ -z "$epoch_ms" || "$epoch_ms" == "null" || ! "$epoch_ms" =~ ^[0-9]+$ ]]; then
        echo "null"
        return
    fi

    local epoch_seconds=$((epoch_ms / 1000))

    # Use date command (macOS and Linux compatible)
    if [[ "$(uname)" == "Darwin" ]]; then
        date -r "$epoch_seconds" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "null"
    else
        date -d "@$epoch_seconds" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "null"
    fi
}

# Format trigger type into display string
# Usage: _format_trigger_display "automated" "username"
# Returns: "Automated (git push)" or "Manual (started by username)" or "Unknown"
_format_trigger_display() {
    local trigger_type="$1"
    local trigger_user="$2"

    if [[ "$trigger_type" == "automated" ]]; then
        echo "Automated (git push)"
    elif [[ "$trigger_type" == "manual" ]]; then
        echo "Manual (started by ${trigger_user})"
    else
        echo "Unknown"
    fi
}

# Format commit SHA and message into display string
# Usage: _format_commit_display "abc1234..." "commit message"
# Returns: "abc1234 - \"commit message\"" or "abc1234" or "unknown"
_format_commit_display() {
    local commit_sha="$1"
    local commit_msg="$2"

    if [[ -n "$commit_sha" && "$commit_sha" != "unknown" ]]; then
        local short_sha="${commit_sha:0:7}"
        if [[ -n "$commit_msg" && "$commit_msg" != "unknown" ]]; then
            echo "${short_sha} - \"${commit_msg}\""
        else
            echo "${short_sha}"
        fi
    else
        echo "unknown"
    fi
}

# Format correlation status into colored display components
# Usage: _format_correlation_display "correlation_status"
# Sets: _CORRELATION_SYMBOL, _CORRELATION_DESC, _CORRELATION_COLOR
_format_correlation_display() {
    local correlation_status="$1"

    _CORRELATION_SYMBOL=$(get_correlation_symbol "$correlation_status")
    _CORRELATION_DESC=$(describe_commit_correlation "$correlation_status")
    if [[ "$correlation_status" == "your_commit" || "$correlation_status" == "in_history" ]]; then
        _CORRELATION_COLOR="${COLOR_GREEN}"
    else
        _CORRELATION_COLOR="${COLOR_RED}"
    fi
}

# Display successful build output
# Usage: display_success_output "job_name" "build_number" "build_json" "trigger_type" "trigger_user" "commit_sha" "commit_msg" "correlation_status"
display_success_output() {
    local job_name="$1"
    local build_number="$2"
    local build_json="$3"
    local trigger_type="$4"
    local trigger_user="$5"
    local commit_sha="$6"
    local commit_msg="$7"
    local correlation_status="$8"
    local console_output="${9:-}"

    # Extract values from build JSON
    local duration timestamp url
    duration=$(echo "$build_json" | jq -r '.duration // 0')
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Format display components
    local trigger_display commit_display
    trigger_display=$(_format_trigger_display "$trigger_type" "$trigger_user")
    commit_display=$(_format_commit_display "$commit_sha" "$commit_msg")
    _format_correlation_display "$correlation_status"

    # Display banner
    log_banner "success"

    # Display build details (header fields first, matching monitored output)
    # Spec: bug-build-monitoring-header-spec.md
    echo "Job:        ${job_name}"
    echo "Build:      #${build_number}"
    echo "Status:     ${COLOR_GREEN}SUCCESS${COLOR_RESET}"
    echo "Trigger:    ${trigger_display}"
    echo "Commit:     ${commit_display}"
    echo "            ${_CORRELATION_COLOR}${_CORRELATION_SYMBOL} ${_CORRELATION_DESC}${COLOR_RESET}"
    echo "Started:    $(format_timestamp "$timestamp")"

    # Display Build Info section if console output is available
    if [[ -n "$console_output" ]]; then
        display_build_metadata "$console_output"
    fi

    echo ""
    echo "Console:    ${url}console"

    # Display all stages
    # Spec: full-stage-print-spec.md, Section: Display Functions
    echo ""
    _display_stages "$job_name" "$build_number"

    # Display test results for SUCCESS builds
    # Spec: show-test-results-always-spec.md, Section 1.1
    local test_results_json
    test_results_json=$(fetch_test_results "$job_name" "$build_number")
    display_test_results "$test_results_json"

    # Finished line and duration
    echo ""
    print_finished_line "SUCCESS"
    if [[ "$duration" != "0" && "$duration" =~ ^[0-9]+$ ]]; then
        log_info "Duration: $(format_duration "$duration")"
    fi
}

# Display failed build output
# Usage: display_failure_output "job_name" "build_number" "build_json" "trigger_type" "trigger_user" "commit_sha" "commit_msg" "correlation_status" "console_output"
display_failure_output() {
    local job_name="$1"
    local build_number="$2"
    local build_json="$3"
    local trigger_type="$4"
    local trigger_user="$5"
    local commit_sha="$6"
    local commit_msg="$7"
    local correlation_status="$8"
    local console_output="${9:-}"

    # Extract values from build JSON
    local result duration timestamp url
    result=$(echo "$build_json" | jq -r '.result // "FAILURE"')
    duration=$(echo "$build_json" | jq -r '.duration // 0')
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Format display components
    local trigger_display commit_display
    trigger_display=$(_format_trigger_display "$trigger_type" "$trigger_user")
    commit_display=$(_format_commit_display "$commit_sha" "$commit_msg")
    _format_correlation_display "$correlation_status"

    # Display banner
    log_banner "failure"

    # Display build details (header fields first, matching monitored output)
    # Spec: bug-build-monitoring-header-spec.md
    echo "Job:        ${job_name}"
    echo "Build:      #${build_number}"
    echo "Status:     ${COLOR_RED}${result}${COLOR_RESET}"
    echo "Trigger:    ${trigger_display}"
    echo "Commit:     ${commit_display}"
    echo "            ${_CORRELATION_COLOR}${_CORRELATION_SYMBOL} ${_CORRELATION_DESC}${COLOR_RESET}"
    echo "Started:    $(format_timestamp "$timestamp")"

    # Display build metadata (user, agent, pipeline)
    if [[ -n "$console_output" ]]; then
        display_build_metadata "$console_output"
    fi

    echo ""
    echo "Console:    ${url}console"

    # Display all stages (includes not-executed stages for failed builds)
    # Spec: full-stage-print-spec.md, Section: Display Functions
    echo ""
    _display_stages "$job_name" "$build_number"

    # Failure diagnostics (shared)
    # Spec: refactor-shared-failure-diagnostics-spec.md
    _display_failure_diagnostics "$job_name" "$build_number" "$console_output"

    # Finished line and duration
    echo ""
    print_finished_line "$result"
    if [[ "$duration" != "0" && "$duration" =~ ^[0-9]+$ ]]; then
        log_info "Duration: $(format_duration "$duration")"
    fi
}

# Display failed jobs tree for failure output
# Usage: _display_failed_jobs_tree "job_name" "build_number" "console_output"
_display_failed_jobs_tree() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    echo ""
    echo "${COLOR_YELLOW}=== Failed Jobs ===${COLOR_RESET}"

    # Get failed stage for the root job
    local failed_stage
    failed_stage=$(get_failed_stage "$job_name" "$build_number")

    local stage_suffix=""
    if [[ -n "$failed_stage" ]]; then
        stage_suffix=" (stage: ${failed_stage})"
    fi

    # Find downstream builds
    local downstream_builds
    downstream_builds=$(detect_all_downstream_builds "$console_output")

    if [[ -z "$downstream_builds" ]]; then
        # No downstream builds - root job failed directly
        echo "  → ${job_name}${stage_suffix}  ${COLOR_RED}← FAILED${COLOR_RESET}"
    else
        # Has downstream builds - find the failed one
        local failed_downstream
        failed_downstream=$(find_failed_downstream_build "$console_output")

        echo "  → ${job_name}${stage_suffix}"

        # Display downstream builds with indentation
        local indent="    "
        while IFS=' ' read -r ds_job ds_build; do
            if [[ -n "$ds_job" && -n "$ds_build" ]]; then
                if check_build_failed "$ds_job" "$ds_build"; then
                    # Check if this failed job has its own downstream builds
                    local ds_console
                    ds_console=$(get_console_output "$ds_job" "$ds_build")
                    local ds_downstream
                    ds_downstream=$(detect_all_downstream_builds "$ds_console")

                    if [[ -n "$ds_downstream" ]]; then
                        echo "${indent}→ ${ds_job}"
                        # Recursively show nested downstream
                        _display_nested_downstream "$ds_job" "$ds_build" "$ds_console" "${indent}  "
                    else
                        echo "${indent}→ ${ds_job}  ${COLOR_RED}← FAILED${COLOR_RESET}"
                    fi
                else
                    echo "${indent}→ ${ds_job}  ✓"
                fi
            fi
        done <<< "$downstream_builds"
    fi

    echo "${COLOR_YELLOW}====================${COLOR_RESET}"
}

# Helper to display nested downstream builds recursively
# Usage: _display_nested_downstream "job_name" "build_number" "console_output" "indent"
_display_nested_downstream() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"
    local indent="$4"

    local downstream_builds
    downstream_builds=$(detect_all_downstream_builds "$console_output")

    while IFS=' ' read -r ds_job ds_build; do
        if [[ -n "$ds_job" && -n "$ds_build" ]]; then
            if check_build_failed "$ds_job" "$ds_build"; then
                local ds_console
                ds_console=$(get_console_output "$ds_job" "$ds_build")
                local ds_downstream
                ds_downstream=$(detect_all_downstream_builds "$ds_console")

                if [[ -n "$ds_downstream" ]]; then
                    echo "${indent}→ ${ds_job}"
                    _display_nested_downstream "$ds_job" "$ds_build" "$ds_console" "${indent}  "
                else
                    echo "${indent}→ ${ds_job}  ${COLOR_RED}← FAILED${COLOR_RESET}"
                fi
            else
                echo "${indent}→ ${ds_job}  ✓"
            fi
        fi
    done <<< "$downstream_builds"
}

# Display full console output for early build failures (no stages ran)
# Usage: _display_early_failure_console "job_name" "build_number" "console_output"
# Returns: 0 if early failure detected and console displayed, 1 if stages exist (caller should use existing logic)
# Spec: buildgit-early-build-failure-spec.md
_display_early_failure_console() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    local stages
    stages=$(get_all_stages "$job_name" "$build_number")

    # Check if stages array is empty (no pipeline stages executed)
    local stage_count
    stage_count=$(echo "$stages" | jq 'length' 2>/dev/null) || stage_count=0

    if [[ "$stage_count" -gt 0 ]]; then
        return 1  # Stages exist, caller should use existing logic
    fi

    # Early failure - display full console output
    echo ""
    echo "${COLOR_YELLOW}=== Console Output ===${COLOR_RESET}"
    if [[ -n "$console_output" ]]; then
        echo "$console_output"
    fi
    echo "${COLOR_YELLOW}======================${COLOR_RESET}"
    return 0
}

# Constants for fallback behavior
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
STAGE_LOG_MIN_LINES=5        # Minimum lines for extraction to be considered sufficient
STAGE_LOG_FALLBACK_LINES=50  # Lines to show in fallback mode

# Shared error log display decision logic
# Decides whether and how to show error logs based on test failure presence and CONSOLE_MODE.
# Used by both _handle_build_completion (monitoring path) and display_failure_output (snapshot path).
# Usage: _display_error_log_section "job_name" "build_number" "console_output" "test_results_json"
# Spec: bug2026-02-12-phandlemono-no-logs-spec.md, Section: Shared error log display logic
_display_error_log_section() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"
    local test_results_json="${4:-}"

    local has_test_failures=false
    if [[ -n "$test_results_json" ]]; then
        local fail_count
        fail_count=$(echo "$test_results_json" | jq -r '.failCount // 0') || fail_count=0
        if [[ "$fail_count" -gt 0 ]]; then
            has_test_failures=true
        fi
    fi

    if [[ "$has_test_failures" == "true" && -z "${CONSOLE_MODE:-}" ]]; then
        # Suppress error logs: test results section is sufficient
        :
    elif [[ "${CONSOLE_MODE:-}" =~ ^[0-9]+$ ]]; then
        # Show last N lines of raw console output
        echo ""
        echo "${COLOR_YELLOW}=== Console Log (last ${CONSOLE_MODE} lines) ===${COLOR_RESET}"
        echo "$console_output" | tail -"${CONSOLE_MODE}"
        echo "${COLOR_YELLOW}================================================${COLOR_RESET}"
    else
        # Default for non-SUCCESS without test failures, or --console auto
        _display_error_logs "$job_name" "$build_number" "$console_output"
    fi
}

# Display error logs section for failure output
# Usage: _display_error_logs "job_name" "build_number" "console_output"
#
# Implements fallback behavior when stage extraction produces insufficient output:
# - If extracted logs have fewer than STAGE_LOG_MIN_LINES lines, triggers fallback
# - Fallback shows last STAGE_LOG_FALLBACK_LINES lines with explanatory message
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
_display_error_logs() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    # Check for early failure (no stages ran) - show full console instead of error extraction
    # Spec: buildgit-early-build-failure-spec.md
    if _display_early_failure_console "$job_name" "$build_number" "$console_output"; then
        return 0
    fi

    echo ""
    echo "${COLOR_YELLOW}=== Error Logs ===${COLOR_RESET}"

    # Check for downstream build failure first
    local downstream
    downstream=$(find_failed_downstream_build "$console_output")

    if [[ -n "$downstream" ]]; then
        local ds_job ds_build
        ds_job=$(echo "$downstream" | cut -d' ' -f1)
        ds_build=$(echo "$downstream" | cut -d' ' -f2)

        local ds_console
        ds_console=$(get_console_output "$ds_job" "$ds_build")

        if [[ -n "$ds_console" ]]; then
            extract_error_lines "$ds_console" 30
        else
            extract_error_lines "$console_output" 30
        fi
    else
        # No downstream - try to get stage-specific logs
        local failed_stage
        failed_stage=$(get_failed_stage "$job_name" "$build_number")

        if [[ -n "$failed_stage" ]]; then
            local stage_logs
            stage_logs=$(extract_stage_logs "$console_output" "$failed_stage")

            # Check if extraction produced sufficient output
            # Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
            local line_count
            line_count=$(echo "$stage_logs" | wc -l | tr -d ' ')

            if [[ -n "$stage_logs" ]] && [[ "$line_count" -ge "$STAGE_LOG_MIN_LINES" ]]; then
                extract_error_lines "$stage_logs" 30
            else
                # Fallback: extraction empty or insufficient
                echo "${COLOR_YELLOW}Stage log extraction may be incomplete. Showing last ${STAGE_LOG_FALLBACK_LINES} lines:${COLOR_RESET}"
                echo ""
                echo "$console_output" | tail -"$STAGE_LOG_FALLBACK_LINES"
            fi
        else
            extract_error_lines "$console_output" 30
        fi
    fi

    echo "${COLOR_YELLOW}==================${COLOR_RESET}"
}

# Display all failure diagnostic sections for human-readable output
# This is the single entry point for failure diagnostics, called by both
# display_failure_output (snapshot path) and _handle_build_completion (monitoring path).
# Usage: _display_failure_diagnostics "job_name" "build_number" "console_output"
# Spec: refactor-shared-failure-diagnostics-spec.md
_display_failure_diagnostics() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    # 1. Early failure (no stages ran) → show full console, return
    if _display_early_failure_console "$job_name" "$build_number" "$console_output"; then
        return 0
    fi

    # 2. Failed jobs tree (with downstream detection)
    _display_failed_jobs_tree "$job_name" "$build_number" "$console_output"

    # 3. Test results (always shown, placeholder if no report)
    # Spec: show-test-results-always-spec.md, Section 1
    local test_results_json
    test_results_json=$(fetch_test_results "$job_name" "$build_number")
    display_test_results "$test_results_json"

    # 4. Error log section (respects --console and test failure suppression)
    _display_error_log_section "$job_name" "$build_number" "$console_output" "$test_results_json"
}

# Display in-progress build output (unified header format)
# Usage: display_building_output "job_name" "build_number" "build_json" "trigger_type" "trigger_user" "commit_sha" "commit_msg" "correlation_status" "current_stage" "console_output" "running_msg"
# Spec: unify-follow-log-spec.md, Section 2 (Build Header)
display_building_output() {
    local job_name="$1"
    local build_number="$2"
    local build_json="$3"
    local trigger_type="$4"
    local trigger_user="$5"
    local commit_sha="$6"
    local commit_msg="$7"
    local correlation_status="$8"
    local current_stage="${9:-}"
    local console_output="${10:-}"
    local running_msg="${11:-}"

    # Extract values from build JSON
    local timestamp url
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Format display components
    local trigger_display commit_display
    trigger_display=$(_format_trigger_display "$trigger_type" "$trigger_user")
    commit_display=$(_format_commit_display "$commit_sha" "$commit_msg")
    _format_correlation_display "$correlation_status"

    # Display banner
    log_banner "building"

    # Display running-time message if provided (status -f joining in-progress build)
    if [[ -n "$running_msg" ]]; then
        echo "$running_msg"
        echo ""
    fi

    # Display build details (before stages, per unified format)
    # Spec: unify-follow-log-spec.md, Section 2 (Build Header)
    echo "Job:        ${job_name}"
    echo "Build:      #${build_number}"
    echo "Status:     ${COLOR_YELLOW}BUILDING${COLOR_RESET}"
    echo "Trigger:    ${trigger_display}"

    # Skip Commit/correlation lines when commit is unknown or empty (deferred header)
    if [[ -n "$commit_sha" && "$commit_sha" != "unknown" ]]; then
        echo "Commit:     ${commit_display}"
        echo "            ${_CORRELATION_COLOR}${_CORRELATION_SYMBOL} ${_CORRELATION_DESC}${COLOR_RESET}"
    fi

    echo "Started:    $(format_timestamp "$timestamp")"

    # Display Build Info section if console output is available
    if [[ -n "$console_output" ]]; then
        display_build_metadata "$console_output"
    fi

    # Display Console URL only when Commit is already known.
    # If Commit is deferred, Console URL is printed later after deferred fields.
    if [[ -n "$commit_sha" && "$commit_sha" != "unknown" ]]; then
        echo ""
        echo "Console:    ${url}console"
    fi
}

# =============================================================================
# Git Commit Correlation Functions
# =============================================================================

# Correlate a commit SHA with the local git history
# Usage: correlate_commit "sha"
# Returns: Outputs a single line with the correlation status:
#   - "your_commit" - SHA matches current HEAD
#   - "in_history" - SHA is an ancestor of HEAD (in your history)
#   - "not_in_history" - SHA exists locally but not reachable from HEAD
#   - "unknown" - SHA not found in local repository
# Always returns 0; outputs 'unknown' for invalid/malformed SHA or git failures
correlate_commit() {
    local sha="$1"

    # Validate input
    if [[ -z "$sha" || "$sha" == "unknown" ]]; then
        echo "unknown"
        return 0
    fi

    # Validate SHA format (7-40 hex characters)
    if [[ ! "$sha" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
        echo "unknown"
        return 0
    fi

    # Get current HEAD SHA for comparison
    local head_sha
    head_sha=$(git rev-parse HEAD 2>/dev/null) || {
        echo "unknown"
        return 0
    }

    # Normalize the input SHA to full form if it exists
    local full_sha
    full_sha=$(git rev-parse "$sha" 2>/dev/null) || true

    # Check 1: Does the commit exist locally?
    if ! git cat-file -t "$sha" &>/dev/null; then
        echo "unknown"
        return 0
    fi

    # Check 2: Is it exactly HEAD?
    # Compare the full SHA forms
    if [[ -n "$full_sha" && "$full_sha" == "$head_sha" ]]; then
        echo "your_commit"
        return 0
    fi

    # Check 3: Is it reachable from HEAD (an ancestor)?
    if git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
        echo "in_history"
        return 0
    fi

    # Commit exists but is not reachable from HEAD
    echo "not_in_history"
    return 0
}

# Get human-readable description of commit correlation status
# Usage: describe_commit_correlation "status"
# Returns: Human-readable description string
describe_commit_correlation() {
    local status="$1"

    case "$status" in
        your_commit)
            echo "Your commit (HEAD)"
            ;;
        in_history)
            echo "In your history (reachable from HEAD)"
            ;;
        not_in_history)
            echo "Not in your history"
            ;;
        unknown|*)
            echo "Unknown commit"
            ;;
    esac
}

# Get symbol for commit correlation status (for display)
# Usage: get_correlation_symbol "status"
# Returns: Symbol (checkmark or X)
get_correlation_symbol() {
    local status="$1"

    case "$status" in
        your_commit|in_history)
            echo "✓"
            ;;
        not_in_history|unknown|*)
            echo "✗"
            ;;
    esac
}

# =============================================================================
# JSON Output Functions
# =============================================================================

# Global flag for JSON output mode
JSON_OUTPUT_MODE="${JSON_OUTPUT_MODE:-false}"

# Output build status as JSON
# Usage: output_json "job_name" "build_number" "build_json" "trigger_type" "trigger_user" "commit_sha" "commit_msg" "correlation_status" ["console_output"]
# For failed builds, also extracts failure info from console_output
output_json() {
    local job_name="$1"
    local build_number="$2"
    local build_json="$3"
    local trigger_type="$4"
    local trigger_user="$5"
    local commit_sha="$6"
    local commit_msg="$7"
    local correlation_status="$8"
    local console_output="${9:-}"

    # Extract values from build JSON
    local result building duration timestamp url
    result=$(echo "$build_json" | jq -r '.result // null')
    building=$(echo "$build_json" | jq -r '.building // false')
    duration=$(echo "$build_json" | jq -r '.duration // 0')
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Calculate duration in seconds
    local duration_seconds=0
    if [[ "$duration" =~ ^[0-9]+$ ]]; then
        duration_seconds=$((duration / 1000))
    fi

    # Determine if build is failed (any non-SUCCESS completed result)
    local is_failed=false
    if [[ "$result" != "SUCCESS" && "$result" != "null" && -n "$result" ]]; then
        is_failed=true
    fi

    # Determine correlation booleans
    local in_local_history=false
    local reachable_from_head=false
    local is_head=false

    case "$correlation_status" in
        your_commit)
            in_local_history=true
            reachable_from_head=true
            is_head=true
            ;;
        in_history)
            in_local_history=true
            reachable_from_head=true
            ;;
        not_in_history)
            in_local_history=true
            ;;
    esac

    # Build base JSON
    local json_output
    json_output=$(jq -n \
        --arg job "$job_name" \
        --argjson build_number "$build_number" \
        --arg status "$result" \
        --argjson building "$building" \
        --argjson duration_seconds "$duration_seconds" \
        --arg timestamp "$(format_timestamp_iso "$timestamp")" \
        --arg url "$url" \
        --arg trigger_type "$trigger_type" \
        --arg trigger_user "$trigger_user" \
        --arg sha "$commit_sha" \
        --arg message "$commit_msg" \
        --argjson in_local_history "$in_local_history" \
        --argjson reachable_from_head "$reachable_from_head" \
        --argjson is_head "$is_head" \
        --arg console_url "${url}console" \
        '{
            job: $job,
            build: {
                number: $build_number,
                status: (if $status == "null" then null else $status end),
                building: $building,
                duration_seconds: $duration_seconds,
                timestamp: (if $timestamp == "null" then null else $timestamp end),
                url: $url
            },
            trigger: {
                type: $trigger_type,
                user: $trigger_user
            },
            commit: {
                sha: $sha,
                message: $message,
                in_local_history: $in_local_history,
                reachable_from_head: $reachable_from_head,
                is_head: $is_head
            },
            console_url: $console_url
        }')

    # Add nested stages array to JSON output
    # Spec: nested-jobs-display-spec.md, Section: JSON Output
    local nested_stages_json
    nested_stages_json=$(_get_nested_stages "$job_name" "$build_number" 2>/dev/null) || nested_stages_json="[]"

    if [[ -n "$nested_stages_json" && "$nested_stages_json" != "[]" ]]; then
        # Transform to match JSON output spec: rename durationMillis to duration_ms
        local stages_for_json
        stages_for_json=$(echo "$nested_stages_json" | jq '
            [.[] | {
                name: .name,
                status: .status,
                duration_ms: .durationMillis,
                agent: .agent
            } + (if .downstream_job then {
                downstream_job: .downstream_job,
                downstream_build: .downstream_build,
                parent_stage: .parent_stage,
                nesting_depth: .nesting_depth
            } else {} end) + (if .has_downstream then {
                has_downstream: true
            } else {} end) + (if .nesting_depth > 0 and (.downstream_job | not) then {
                nesting_depth: .nesting_depth,
                downstream_job: .downstream_job,
                downstream_build: .downstream_build,
                parent_stage: .parent_stage
            } else {} end)
            + (if .is_parallel_wrapper then {
                is_parallel_wrapper: true,
                parallel_branches: .parallel_branches
            } else {} end)
            + (if .parallel_branch then {
                parallel_branch: .parallel_branch
            } + (if .parallel_wrapper then {
                parallel_wrapper: .parallel_wrapper
            } else {} end) else {} end)]
        ' 2>/dev/null) || stages_for_json="[]"

        if [[ -n "$stages_for_json" && "$stages_for_json" != "[]" ]]; then
            json_output=$(echo "$json_output" | jq --argjson stages "$stages_for_json" '. + {stages: $stages}')
        fi
    fi

    # Add failure info if build failed
    if [[ "$is_failed" == "true" && -n "$console_output" ]]; then
        local failure_json
        failure_json=$(_build_failure_json "$job_name" "$build_number" "$console_output")

        local build_info_json
        build_info_json=$(_build_info_json "$console_output")

        # Merge failure and build_info into the output
        json_output=$(echo "$json_output" | jq \
            --argjson failure "$failure_json" \
            --argjson build_info "$build_info_json" \
            '. + {failure: $failure, build_info: $build_info}')
    fi

    # Add test results for all completed builds
    # Spec: show-test-results-always-spec.md, Section 7
    local is_completed=false
    if [[ "$result" != "null" && -n "$result" && "$building" == "false" ]]; then
        is_completed=true
    fi

    if [[ "$is_completed" == "true" ]]; then
        local test_report_json
        test_report_json=$(fetch_test_results "$job_name" "$build_number")

        if [[ -n "$test_report_json" ]]; then
            local test_results_formatted
            test_results_formatted=$(format_test_results_json "$test_report_json")

            if [[ -n "$test_results_formatted" ]]; then
                json_output=$(echo "$json_output" | jq \
                    --argjson test_results "$test_results_formatted" \
                    '. + {test_results: $test_results}')
            fi
        else
            # No test report available - include null sentinel
            # Spec: show-test-results-always-spec.md, Section 3.2
            json_output=$(echo "$json_output" | jq '. + {test_results: null}')
        fi

        # Adjust failure.error_summary and failure.console_log based on CONSOLE_MODE (failures only)
        # Spec: console-on-unstable-spec.md, Section 3 (JSON output)
        if [[ "$is_failed" == "true" ]]; then
            local has_test_failures=false
            if [[ -n "$test_report_json" ]]; then
                local fail_count
                fail_count=$(echo "$test_report_json" | jq -r '.failCount // 0') || fail_count=0
                if [[ "$fail_count" -gt 0 ]]; then
                    has_test_failures=true
                fi
            fi

            if [[ "$has_test_failures" == "true" && -z "${CONSOLE_MODE:-}" ]]; then
                # Suppress error_summary when test failures present and no --console
                json_output=$(echo "$json_output" | jq \
                    'if .failure then .failure.error_summary = null else . end')
            fi

            if [[ "${CONSOLE_MODE:-}" =~ ^[0-9]+$ ]]; then
                # --console N: add console_log with last N lines, null out error_summary
                local console_log_lines
                console_log_lines=$(echo "$console_output" | tail -"${CONSOLE_MODE}")
                json_output=$(echo "$json_output" | jq \
                    --arg console_log "$console_log_lines" \
                    'if .failure then .failure.error_summary = null | .failure.console_log = $console_log else . end')
            fi
        fi
    fi

    echo "$json_output"
}

# Build failure JSON object
# Usage: _build_failure_json "job_name" "build_number" "console_output"
# Returns: JSON object with failed_jobs, root_cause_job, failed_stage, error_summary, console_output
# Spec: bug-status-json-spec.md
_build_failure_json() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    local failed_jobs=()
    local root_cause_job="$job_name"
    local failed_stage=""
    local error_summary=""
    local json_console_output=""

    # Start with root job
    failed_jobs+=("$job_name")

    # Detect early failure: no pipeline stages ran
    # Spec: bug-status-json-spec.md, Detection Criteria
    local stages
    stages=$(get_all_stages "$job_name" "$build_number")
    local stage_count
    stage_count=$(echo "$stages" | jq 'length' 2>/dev/null) || stage_count=0

    if [[ "$stage_count" -eq 0 ]]; then
        # Early failure — include full console output, no error_summary
        json_console_output="$console_output"
    else
        # Stages exist — get failed stage and error details

        # Get failed stage for root job
        failed_stage=$(get_failed_stage "$job_name" "$build_number" 2>/dev/null) || true

        # Find downstream builds and their failure status
        local downstream_builds
        downstream_builds=$(detect_all_downstream_builds "$console_output")

        if [[ -n "$downstream_builds" ]]; then
            # Track the deepest failed job
            local current_console="$console_output"
            local current_job="$job_name"
            local current_build="$build_number"

            while true; do
                local failed_downstream
                failed_downstream=$(find_failed_downstream_build "$current_console")

                if [[ -z "$failed_downstream" ]]; then
                    break
                fi

                local ds_job ds_build
                ds_job=$(echo "$failed_downstream" | cut -d' ' -f1)
                ds_build=$(echo "$failed_downstream" | cut -d' ' -f2)

                if [[ -n "$ds_job" && "$ds_job" != "$current_job" ]]; then
                    failed_jobs+=("$ds_job")
                    root_cause_job="$ds_job"
                    current_job="$ds_job"
                    current_build="$ds_build"

                    # Get console for this downstream build
                    current_console=$(get_console_output "$ds_job" "$ds_build" 2>/dev/null) || break

                    # Update failed stage from root cause job
                    local ds_stage
                    ds_stage=$(get_failed_stage "$ds_job" "$ds_build" 2>/dev/null) || true
                    if [[ -n "$ds_stage" ]]; then
                        failed_stage="$ds_stage"
                    fi
                else
                    break
                fi
            done

            # Get multi-line error summary from root cause (mirrors _display_error_logs)
            # Spec: bug-status-json-spec.md, Technical Requirement 2
            if [[ -n "$current_console" ]]; then
                error_summary=$(extract_error_lines "$current_console" 30)
            fi
        else
            # No downstream — use stage-aware error extraction (mirrors _display_error_logs)
            if [[ -n "$failed_stage" ]]; then
                local stage_logs
                stage_logs=$(extract_stage_logs "$console_output" "$failed_stage")

                local line_count
                line_count=$(echo "$stage_logs" | wc -l | tr -d ' ')

                if [[ -n "$stage_logs" ]] && [[ "$line_count" -ge "$STAGE_LOG_MIN_LINES" ]]; then
                    error_summary=$(extract_error_lines "$stage_logs" 30)
                else
                    # Fallback: stage extraction insufficient
                    error_summary=$(echo "$console_output" | tail -"$STAGE_LOG_FALLBACK_LINES")
                fi
            else
                error_summary=$(extract_error_lines "$console_output" 30)
            fi
        fi
    fi

    # Build JSON array for failed_jobs
    local failed_jobs_json
    failed_jobs_json=$(printf '%s\n' "${failed_jobs[@]}" | jq -R . | jq -s .)

    jq -n \
        --argjson failed_jobs "$failed_jobs_json" \
        --arg root_cause_job "$root_cause_job" \
        --arg failed_stage "$failed_stage" \
        --arg error_summary "$error_summary" \
        --arg console_output "$json_console_output" \
        '{
            failed_jobs: $failed_jobs,
            root_cause_job: $root_cause_job,
            failed_stage: (if $failed_stage == "" then null else $failed_stage end),
            error_summary: (if $error_summary == "" then null else $error_summary end),
            console_output: (if $console_output == "" then null else $console_output end),
            console_log: null
        }'
}

# Extract a brief error summary from console output
# Usage: _extract_error_summary "console_output"
# Returns: Single-line error summary
_extract_error_summary() {
    local console_output="$1"

    # Try to find first meaningful error line
    local error_line
    error_line=$(echo "$console_output" | grep -iE '^(ERROR|FATAL|Exception|.*failed:)' 2>/dev/null | head -1) || true

    if [[ -z "$error_line" ]]; then
        # Try assertion errors
        error_line=$(echo "$console_output" | grep -iE 'AssertionError|assertion failed' 2>/dev/null | head -1) || true
    fi

    if [[ -z "$error_line" ]]; then
        # Try test failures
        error_line=$(echo "$console_output" | grep -iE 'Test.*failed|failed.*test' 2>/dev/null | head -1) || true
    fi

    # Truncate to reasonable length
    if [[ -n "$error_line" ]]; then
        echo "${error_line:0:200}"
    fi
}

# Build build_info JSON object from console output
# Usage: _build_info_json "console_output"
# Returns: JSON object with started_by, agent, pipeline
_build_info_json() {
    local console_output="$1"

    _parse_build_metadata "$console_output"

    jq -n \
        --arg started_by "$_META_STARTED_BY" \
        --arg agent "$_META_AGENT" \
        --arg pipeline "$_META_PIPELINE" \
        '{
            started_by: (if $started_by == "" then null else $started_by end),
            agent: (if $agent == "" then null else $agent end),
            pipeline: (if $pipeline == "" then null else $pipeline end)
        }'
}

# =============================================================================
# Nested/Downstream Stage Display Functions
# =============================================================================
# Spec: nested-jobs-display-spec.md

# Extract agent name from build console output
# Usage: _extract_agent_name "$console_output"
# Returns: agent name string, or empty
_extract_agent_name() {
    local console_output="$1"
    _extract_running_agent_from_console "$console_output" || true
}

# Map parent stages to their downstream builds
# Usage: _map_stages_to_downstream "$console_output" "$stages_json"
# Returns: JSON object mapping stage names to {job, build} pairs
# Example: {"Build Handle": {"job": "downstream-job", "build": 42}}
_map_stages_to_downstream() {
    local console_output="$1"
    local stages_json="$2"

    local result="{}"
    local stage_count
    stage_count=$(echo "$stages_json" | jq 'length' 2>/dev/null) || stage_count=0

    local i=0
    while [[ $i -lt $stage_count ]]; do
        local stage_name
        stage_name=$(echo "$stages_json" | jq -r ".[$i].name")

        # Extract this stage's console logs
        local stage_logs
        stage_logs=$(extract_stage_logs "$console_output" "$stage_name")

        if [[ -n "$stage_logs" ]]; then
            # Check for downstream builds in this stage's logs
            local downstream
            downstream=$(detect_all_downstream_builds "$stage_logs")

            if [[ -n "$downstream" ]]; then
                # Select best downstream match for this stage
                local ds_job ds_build
                local selected_downstream
                selected_downstream=$(_select_downstream_build_for_stage "$stage_name" "$downstream")
                ds_job=$(echo "$selected_downstream" | awk '{print $1}')
                ds_build=$(echo "$selected_downstream" | awk '{print $2}')

                if [[ -n "$ds_job" && -n "$ds_build" ]]; then
                    result=$(echo "$result" | jq \
                        --arg stage "$stage_name" \
                        --arg job "$ds_job" \
                        --argjson build "$ds_build" \
                        '. + {($stage): {"job": $job, "build": $build}}')
                fi
            fi
        fi

        i=$((i + 1))
    done

    echo "$result"
}

# Get nested stages for a build, recursively expanding downstream builds
# Usage: _get_nested_stages "job-name" "build-number" [prefix] [nesting_depth] [parent_stage] [parallel_path]
# Returns: JSON array of stage objects with nested stage metadata
_get_nested_stages() {
    local job_name="$1"
    local build_number="$2"
    local prefix="${3:-}"
    local nesting_depth="${4:-0}"
    local parent_stage_name="${5:-}"
    local inherited_parallel_path="${6:-}"

    local stages_json
    stages_json=$(get_all_stages "$job_name" "$build_number")
    if [[ -z "$stages_json" || "$stages_json" == "[]" ]]; then
        echo "[]"
        return 0
    fi

    local console_output
    console_output=$(get_console_output "$job_name" "$build_number" 2>/dev/null) || true

    local agent=""
    if [[ -n "$console_output" ]]; then
        agent=$(_extract_agent_name "$console_output")
    fi

    local parallel_info="{}"
    local _branch_to_wrapper="{}"
    local _branch_to_path="{}"
    local _wrapper_last_branch_index="{}"
    if [[ -n "$console_output" ]]; then
        local stage_count_for_parallel
        stage_count_for_parallel=$(echo "$stages_json" | jq 'length')
        local pi=0
        while [[ $pi -lt $stage_count_for_parallel ]]; do
            local pi_stage_name
            pi_stage_name=$(echo "$stages_json" | jq -r ".[$pi].name")
            local branches
            branches=$(_detect_parallel_branches "$console_output" "$pi_stage_name")
            if [[ -n "$branches" && "$branches" != "[]" ]]; then
                parallel_info=$(echo "$parallel_info" | jq \
                    --arg s "$pi_stage_name" --argjson b "$branches" '. + {($s): {"branches": $b}}')

                local branch_index=1
                local max_branch_idx=-1
                local branch_name
                while IFS= read -r branch_name; do
                    [[ -z "$branch_name" ]] && continue
                    _branch_to_wrapper=$(echo "$_branch_to_wrapper" | jq \
                        --arg b "$branch_name" --arg w "$pi_stage_name" '. + {($b): $w}')
                    local branch_path="$branch_index"
                    if [[ -n "$inherited_parallel_path" ]]; then
                        branch_path="${inherited_parallel_path}.${branch_index}"
                    fi
                    _branch_to_path=$(echo "$_branch_to_path" | jq \
                        --arg b "$branch_name" --arg p "$branch_path" '. + {($b): $p}')

                    local branch_pos
                    branch_pos=$(echo "$stages_json" | jq -r --arg n "$branch_name" 'to_entries[] | select(.value.name == $n) | .key' | head -1)
                    if [[ "$branch_pos" =~ ^[0-9]+$ && "$branch_pos" -gt "$max_branch_idx" ]]; then
                        max_branch_idx="$branch_pos"
                    fi
                    branch_index=$((branch_index + 1))
                done <<< "$(echo "$branches" | jq -r '.[]')"
                if [[ "$max_branch_idx" -ge 0 ]]; then
                    _wrapper_last_branch_index=$(echo "$_wrapper_last_branch_index" | jq \
                        --arg w "$pi_stage_name" --argjson idx "$max_branch_idx" '. + {($w): $idx}')
                fi
            fi
            pi=$((pi + 1))
        done
    fi

    local stage_downstream_map="{}"
    if [[ -n "$console_output" ]]; then
        local filtered_stages_json
        if [[ "$parallel_info" != "{}" ]]; then
            filtered_stages_json=$(echo "$stages_json" | jq --argjson pi "$parallel_info" \
                '[.[] | select(.name as $n | $pi | has($n) | not)]')
        else
            filtered_stages_json="$stages_json"
        fi
        stage_downstream_map=$(_map_stages_to_downstream "$console_output" "$filtered_stages_json")
    fi

    local result="[]"
    local deferred_wrappers="{}"
    local stage_count
    stage_count=$(echo "$stages_json" | jq 'length')

    local i=0
    while [[ $i -lt $stage_count ]]; do
        local stage_name status duration_ms
        stage_name=$(echo "$stages_json" | jq -r ".[$i].name")
        status=$(echo "$stages_json" | jq -r ".[$i].status")
        duration_ms=$(echo "$stages_json" | jq -r ".[$i].durationMillis")

        local is_parallel_wrapper="false"
        local parallel_branches_json="null"
        local parallel_branch=""
        local parallel_wrapper=""
        local stage_parallel_path="$inherited_parallel_path"

        local wrapper_check
        wrapper_check=$(echo "$parallel_info" | jq -r --arg s "$stage_name" 'has($s)') || wrapper_check="false"
        if [[ "$wrapper_check" == "true" ]]; then
            is_parallel_wrapper="true"
            stage_parallel_path=""
            parallel_branches_json=$(echo "$parallel_info" | jq --arg s "$stage_name" '.[$s].branches')
            local max_branch_dur=0
            local branch_name
            while IFS= read -r branch_name; do
                [[ -z "$branch_name" ]] && continue
                local bd
                bd=$(echo "$stages_json" | jq -r --arg n "$branch_name" '.[] | select(.name == $n) | .durationMillis // 0')
                if [[ "$bd" =~ ^[0-9]+$ && "$bd" -gt "$max_branch_dur" ]]; then
                    max_branch_dur="$bd"
                fi
            done <<< "$(echo "$parallel_branches_json" | jq -r '.[]')"
            if [[ "$duration_ms" =~ ^[0-9]+$ ]]; then
                duration_ms=$((duration_ms + max_branch_dur))
            fi
        fi

        local bw_check
        bw_check=$(echo "$_branch_to_wrapper" | jq -r --arg b "$stage_name" '.[$b] // empty')
        if [[ -n "$bw_check" && "$bw_check" != "null" ]]; then
            parallel_branch="$stage_name"
            parallel_wrapper="$bw_check"
            stage_parallel_path=$(echo "$_branch_to_path" | jq -r --arg b "$stage_name" '.[$b] // empty')
        fi

        local ds_info
        ds_info=$(echo "$stage_downstream_map" | jq -r --arg s "$stage_name" '.[$s] // empty')

        local display_name
        if [[ -n "$prefix" ]]; then
            display_name="${prefix}->${stage_name}"
        else
            display_name="${stage_name}"
        fi

        local nested_stages="[]"
        if [[ -n "$ds_info" && "$ds_info" != "null" ]]; then
            local ds_job ds_build
            ds_job=$(echo "$ds_info" | jq -r '.job')
            ds_build=$(echo "$ds_info" | jq -r '.build')
            nested_stages=$(_get_nested_stages "$ds_job" "$ds_build" "$display_name" "$((nesting_depth + 1))" "$stage_name" "$stage_parallel_path" 2>/dev/null) || nested_stages="[]"

            if [[ -n "$parallel_branch" ]]; then
                nested_stages=$(echo "$nested_stages" | jq --arg pb "$parallel_branch" --arg pp "$stage_parallel_path" \
                    '[.[] |
                        . + (if ((.parallel_branch // "") == "") then {parallel_branch: $pb} else {} end)
                          + (if $pp != "" and ((.parallel_path // "") == "") then {parallel_path: $pp} else {} end)
                    ]')
            fi

            if [[ "$nested_stages" != "[]" ]]; then
                result=$(echo "$result" "$nested_stages" | jq -s '.[0] + .[1]')
            fi
        fi

        local stage_entry
        if [[ $nesting_depth -gt 0 ]]; then
            stage_entry=$(jq -n \
                --arg name "$display_name" \
                --arg status "$status" \
                --argjson duration_ms "$duration_ms" \
                --arg agent "$agent" \
                --argjson nesting_depth "$nesting_depth" \
                --arg downstream_job "$job_name" \
                --argjson downstream_build "$build_number" \
                --arg parent_stage "$parent_stage_name" \
                --arg parallel_branch "${parallel_branch:-}" \
                --arg parallel_wrapper "${parallel_wrapper:-}" \
                --arg parallel_path "${stage_parallel_path:-}" \
                --argjson has_downstream "$(if [[ "$ds_info" != "" && "$ds_info" != "null" ]]; then echo true; else echo false; fi)" \
                '{
                    name: $name,
                    status: $status,
                    durationMillis: $duration_ms,
                    agent: $agent,
                    nesting_depth: $nesting_depth,
                    downstream_job: $downstream_job,
                    downstream_build: $downstream_build,
                    parent_stage: $parent_stage,
                    has_downstream: $has_downstream
                }
                + (if $parallel_branch != "" then {parallel_branch: $parallel_branch} else {} end)
                + (if $parallel_wrapper != "" then {parallel_wrapper: $parallel_wrapper} else {} end)
                + (if $parallel_path != "" then {parallel_path: $parallel_path} else {} end)')
        else
            stage_entry=$(jq -n \
                --arg name "$display_name" \
                --arg status "$status" \
                --argjson duration_ms "$duration_ms" \
                --arg agent "$agent" \
                --argjson nesting_depth "$nesting_depth" \
                --argjson is_parallel_wrapper "$is_parallel_wrapper" \
                --argjson parallel_branches "${parallel_branches_json:-null}" \
                --arg parallel_branch "$parallel_branch" \
                --arg parallel_wrapper "$parallel_wrapper" \
                --arg parallel_path "${stage_parallel_path:-}" \
                --argjson has_downstream "$(if [[ "$ds_info" != "" && "$ds_info" != "null" ]]; then echo true; else echo false; fi)" \
                '{
                    name: $name,
                    status: $status,
                    durationMillis: $duration_ms,
                    agent: $agent,
                    nesting_depth: $nesting_depth,
                    has_downstream: $has_downstream
                }
                + (if $is_parallel_wrapper == true then {is_parallel_wrapper: true, parallel_branches: $parallel_branches} else {} end)
                + (if $parallel_branch != "" then {parallel_branch: $parallel_branch, parallel_wrapper: $parallel_wrapper} else {} end)
                + (if $parallel_path != "" then {parallel_path: $parallel_path} else {} end)')
        fi

        if [[ "$is_parallel_wrapper" == "true" ]]; then
            deferred_wrappers=$(echo "$deferred_wrappers" | jq --arg w "$stage_name" --argjson e "$stage_entry" '. + {($w): $e}')
        else
            result=$(echo "$result" | jq --argjson entry "$stage_entry" '. + [$entry]')
        fi

        local wrappers_to_emit
        wrappers_to_emit=$(echo "$_wrapper_last_branch_index" | jq -r --argjson idx "$i" \
            'to_entries[] | select(.value == $idx) | .key' 2>/dev/null) || true
        while IFS= read -r emit_wrapper; do
            [[ -z "$emit_wrapper" ]] && continue
            local wrapper_entry
            wrapper_entry=$(echo "$deferred_wrappers" | jq -c --arg w "$emit_wrapper" '.[$w] // empty')
            if [[ -n "$wrapper_entry" && "$wrapper_entry" != "null" ]]; then
                result=$(echo "$result" | jq --argjson entry "$wrapper_entry" '. + [$entry]')
                deferred_wrappers=$(echo "$deferred_wrappers" | jq --arg w "$emit_wrapper" 'del(.[$w])')
            fi
        done <<< "$wrappers_to_emit"

        i=$((i + 1))
    done

    local remaining_wrappers
    remaining_wrappers=$(echo "$deferred_wrappers" | jq -r 'keys[]?' 2>/dev/null) || true
    while IFS= read -r rw; do
        [[ -z "$rw" ]] && continue
        local rw_entry
        rw_entry=$(echo "$deferred_wrappers" | jq -c --arg w "$rw" '.[$w] // empty')
        if [[ -n "$rw_entry" && "$rw_entry" != "null" ]]; then
            result=$(echo "$result" | jq --argjson entry "$rw_entry" '. + [$entry]')
        fi
    done <<< "$remaining_wrappers"

    echo "$result"
}
