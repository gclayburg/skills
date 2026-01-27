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
