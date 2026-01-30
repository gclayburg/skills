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
        (
            [.suites[]?.cases[]? | select(.status == "FAILED")] +
            [.childReports[]?.result?.suites[]?.cases[]? | select(.status == "FAILED")]
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

    # Handle empty input
    if [[ -z "$test_json" ]]; then
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

    # Display header
    echo ""
    echo "${COLOR_YELLOW}=== Test Results ===${COLOR_RESET}"

    # Display summary line
    echo "  Total: ${total} | Passed: ${passed} | Failed: ${failed} | Skipped: ${skipped}"

    # Check if all tests passed but build still failed
    if [[ "$failed" -eq 0 ]]; then
        echo "  ${COLOR_CYAN}(All tests passed - failure may be from other causes)${COLOR_RESET}"
        echo "${COLOR_YELLOW}====================${COLOR_RESET}"
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

    echo "${COLOR_YELLOW}====================${COLOR_RESET}"
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
#
# This function correctly handles nested Pipeline blocks (e.g., dir, withEnv)
# by tracking nesting depth. It only stops when the nesting depth returns to 0,
# ensuring that post-stage actions (like junit) are included in the output.
extract_stage_logs() {
    local console_output="$1"
    local stage_name="$2"

    # Extract content between [Pipeline] { (StageName) and matching [Pipeline] }
    # Tracks nesting depth to handle nested Pipeline blocks
    echo "$console_output" | awk -v stage="$stage_name" '
        BEGIN { nesting_depth=0 }
        # Match stage start: [Pipeline] { (StageName)
        /\[Pipeline\] \{ \(/ && index($0, "(" stage ")") {
            nesting_depth=1
            next
        }
        # Inside stage: track nested blocks and output lines
        nesting_depth > 0 {
            # Handle nested block start: [Pipeline] { (but not another stage start)
            if (/\[Pipeline\] \{/ && !/\[Pipeline\] \{ \(/) {
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
#          Returns 1 if trigger cannot be determined
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
        return 1
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

    # Extract values from build JSON
    local duration timestamp url
    duration=$(echo "$build_json" | jq -r '.duration // 0')
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Format trigger display
    local trigger_display
    if [[ "$trigger_type" == "automated" ]]; then
        trigger_display="Automated (git push)"
    elif [[ "$trigger_type" == "manual" ]]; then
        trigger_display="Manual (started by ${trigger_user})"
    else
        trigger_display="Unknown"
    fi

    # Format commit display
    local commit_display
    if [[ -n "$commit_sha" && "$commit_sha" != "unknown" ]]; then
        local short_sha="${commit_sha:0:7}"
        if [[ -n "$commit_msg" && "$commit_msg" != "unknown" ]]; then
            commit_display="${short_sha} - \"${commit_msg}\""
        else
            commit_display="${short_sha}"
        fi
    else
        commit_display="unknown"
    fi

    # Format correlation display
    local correlation_symbol correlation_desc
    correlation_symbol=$(get_correlation_symbol "$correlation_status")
    correlation_desc=$(describe_commit_correlation "$correlation_status")
    local correlation_color
    if [[ "$correlation_status" == "your_commit" || "$correlation_status" == "in_history" ]]; then
        correlation_color="${COLOR_GREEN}"
    else
        correlation_color="${COLOR_RED}"
    fi

    # Display banner
    log_banner "success"

    # Display build details
    echo "Job:        ${job_name}"
    echo "Build:      #${build_number}"
    echo "Status:     ${COLOR_GREEN}SUCCESS${COLOR_RESET}"
    echo "Trigger:    ${trigger_display}"
    echo "Commit:     ${commit_display}"
    echo "            ${correlation_color}${correlation_symbol} ${correlation_desc}${COLOR_RESET}"
    echo "Duration:   $(format_duration "$duration")"
    echo "Completed:  $(format_timestamp "$timestamp")"
    echo ""
    echo "Console:    ${url}console"
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
    local console_output="$9"

    # Extract values from build JSON
    local result duration timestamp url
    result=$(echo "$build_json" | jq -r '.result // "FAILURE"')
    duration=$(echo "$build_json" | jq -r '.duration // 0')
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Format trigger display
    local trigger_display
    if [[ "$trigger_type" == "automated" ]]; then
        trigger_display="Automated (git push)"
    elif [[ "$trigger_type" == "manual" ]]; then
        trigger_display="Manual (started by ${trigger_user})"
    else
        trigger_display="Unknown"
    fi

    # Format commit display
    local commit_display
    if [[ -n "$commit_sha" && "$commit_sha" != "unknown" ]]; then
        local short_sha="${commit_sha:0:7}"
        if [[ -n "$commit_msg" && "$commit_msg" != "unknown" ]]; then
            commit_display="${short_sha} - \"${commit_msg}\""
        else
            commit_display="${short_sha}"
        fi
    else
        commit_display="unknown"
    fi

    # Format correlation display
    local correlation_symbol correlation_desc
    correlation_symbol=$(get_correlation_symbol "$correlation_status")
    correlation_desc=$(describe_commit_correlation "$correlation_status")
    local correlation_color
    if [[ "$correlation_status" == "your_commit" || "$correlation_status" == "in_history" ]]; then
        correlation_color="${COLOR_GREEN}"
    else
        correlation_color="${COLOR_RED}"
    fi

    # Display banner
    log_banner "failure"

    # Display build details
    echo "Job:        ${job_name}"
    echo "Build:      #${build_number}"
    echo "Status:     ${COLOR_RED}${result}${COLOR_RESET}"
    echo "Trigger:    ${trigger_display}"
    echo "Commit:     ${commit_display}"
    echo "            ${correlation_color}${correlation_symbol} ${correlation_desc}${COLOR_RESET}"
    echo "Duration:   $(format_duration "$duration")"
    echo "Completed:  $(format_timestamp "$timestamp")"

    # Display build metadata (user, agent, pipeline)
    if [[ -n "$console_output" ]]; then
        display_build_metadata "$console_output"
    fi

    # Display failed jobs tree
    _display_failed_jobs_tree "$job_name" "$build_number" "$console_output"

    # Display test results (between Failed Jobs and Error Logs per spec section 6)
    # Spec: test-failure-display-spec.md, Section: Integration Points (5.1)
    local test_results_json
    test_results_json=$(fetch_test_results "$job_name" "$build_number")
    if [[ -n "$test_results_json" ]]; then
        display_test_results "$test_results_json"
    fi

    # Display error logs
    _display_error_logs "$job_name" "$build_number" "$console_output"

    echo ""
    echo "Console:    ${url}console"
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

# Constants for fallback behavior
# Spec: bug1-jenkins-log-truncated-spec.md, Section: Fallback Behavior
STAGE_LOG_MIN_LINES=5        # Minimum lines for extraction to be considered sufficient
STAGE_LOG_FALLBACK_LINES=50  # Lines to show in fallback mode

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

# Display in-progress build output
# Usage: display_building_output "job_name" "build_number" "build_json" "trigger_type" "trigger_user" "commit_sha" "commit_msg" "correlation_status" "current_stage"
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

    # Extract values from build JSON
    local timestamp url
    timestamp=$(echo "$build_json" | jq -r '.timestamp // 0')
    url=$(echo "$build_json" | jq -r '.url // empty')

    # Calculate elapsed time
    local now_ms elapsed_ms
    now_ms=$(($(date +%s) * 1000))
    elapsed_ms=$((now_ms - timestamp))

    # Format trigger display
    local trigger_display
    if [[ "$trigger_type" == "automated" ]]; then
        trigger_display="Automated (git push)"
    elif [[ "$trigger_type" == "manual" ]]; then
        trigger_display="Manual (started by ${trigger_user})"
    else
        trigger_display="Unknown"
    fi

    # Format commit display
    local commit_display
    if [[ -n "$commit_sha" && "$commit_sha" != "unknown" ]]; then
        local short_sha="${commit_sha:0:7}"
        if [[ -n "$commit_msg" && "$commit_msg" != "unknown" ]]; then
            commit_display="${short_sha} - \"${commit_msg}\""
        else
            commit_display="${short_sha}"
        fi
    else
        commit_display="unknown"
    fi

    # Format correlation display
    local correlation_symbol correlation_desc
    correlation_symbol=$(get_correlation_symbol "$correlation_status")
    correlation_desc=$(describe_commit_correlation "$correlation_status")
    local correlation_color
    if [[ "$correlation_status" == "your_commit" || "$correlation_status" == "in_history" ]]; then
        correlation_color="${COLOR_GREEN}"
    else
        correlation_color="${COLOR_RED}"
    fi

    # Display banner
    log_banner "building"

    # Display build details
    echo "Job:        ${job_name}"
    echo "Build:      #${build_number}"
    echo "Status:     ${COLOR_YELLOW}BUILDING${COLOR_RESET}"
    if [[ -n "$current_stage" ]]; then
        echo "Stage:      ${current_stage}"
    fi
    echo "Trigger:    ${trigger_display}"
    echo "Commit:     ${commit_display}"
    echo "            ${correlation_color}${correlation_symbol} ${correlation_desc}${COLOR_RESET}"
    echo "Started:    $(format_timestamp "$timestamp")"
    echo "Elapsed:    $(format_duration "$elapsed_ms")"
    echo ""
    echo "Console:    ${url}console"
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
# Also returns 0 on success, 1 if SHA is invalid/malformed
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
        return 1
    fi

    # Get current HEAD SHA for comparison
    local head_sha
    head_sha=$(git rev-parse HEAD 2>/dev/null) || {
        echo "unknown"
        return 1
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

    # Determine if build is failed
    local is_failed=false
    if [[ "$result" == "FAILURE" || "$result" == "UNSTABLE" || "$result" == "ABORTED" ]]; then
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

    # Add test results if available (for failed builds)
    # Spec: test-failure-display-spec.md, Section: Integration Points (5.1)
    # The test_results field appears after failure, before build_info in JSON
    if [[ "$is_failed" == "true" ]]; then
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
        fi
    fi

    echo "$json_output"
}

# Build failure JSON object
# Usage: _build_failure_json "job_name" "build_number" "console_output"
# Returns: JSON object with failed_jobs, root_cause_job, failed_stage, error_summary
_build_failure_json() {
    local job_name="$1"
    local build_number="$2"
    local console_output="$3"

    local failed_jobs=()
    local root_cause_job="$job_name"
    local failed_stage=""
    local error_summary=""

    # Start with root job
    failed_jobs+=("$job_name")

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

        # Get error summary from root cause
        if [[ -n "$current_console" ]]; then
            error_summary=$(_extract_error_summary "$current_console")
        fi
    else
        # No downstream - get error summary from main console
        error_summary=$(_extract_error_summary "$console_output")
    fi

    # Build JSON array for failed_jobs
    local failed_jobs_json
    failed_jobs_json=$(printf '%s\n' "${failed_jobs[@]}" | jq -R . | jq -s .)

    jq -n \
        --argjson failed_jobs "$failed_jobs_json" \
        --arg root_cause_job "$root_cause_job" \
        --arg failed_stage "$failed_stage" \
        --arg error_summary "$error_summary" \
        '{
            failed_jobs: $failed_jobs,
            root_cause_job: $root_cause_job,
            failed_stage: (if $failed_stage == "" then null else $failed_stage end),
            error_summary: (if $error_summary == "" then null else $error_summary end)
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

    # Extract user who started the build
    local started_by
    started_by=$(echo "$console_output" | grep -m1 "^Started by user " | sed 's/^Started by user //') || true

    # Extract Jenkins agent
    local agent
    agent=$(echo "$console_output" | grep -m1 "^Running on " | sed 's/^Running on \([^ ]*\).*/\1/') || true

    # Extract pipeline source
    local pipeline
    pipeline=$(echo "$console_output" | grep -m1 "^Obtained .* from git " | sed 's|^Obtained ||') || true

    jq -n \
        --arg started_by "$started_by" \
        --arg agent "$agent" \
        --arg pipeline "$pipeline" \
        '{
            started_by: (if $started_by == "" then null else $started_by end),
            agent: (if $agent == "" then null else $agent end),
            pipeline: (if $pipeline == "" then null else $pipeline end)
        }'
}
