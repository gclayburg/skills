#!/usr/bin/env bash
#
# checkbuild.sh - Jenkins Build Status Checker
#
# Queries the Jenkins build server to report the current status of the last build
# for the job associated with the current git repository. Correlates the triggering
# commit with local git history to determine if the build was triggered by a known
# change or by someone else.
#
# Usage:
#   checkbuild [--json]
#
# Exit Codes:
#   0 - Last build was successful
#   1 - Last build failed, or an error occurred during execution
#   2 - Build is currently in progress
#

set -euo pipefail

# =============================================================================
# Script Setup
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/jenkins-common.sh"

# Configuration
MAX_RETRIES=3
RETRY_DELAY=2

# =============================================================================
# Argument Parsing
# =============================================================================

parse_arguments() {
    JSON_OUTPUT_MODE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT_MODE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    export JSON_OUTPUT_MODE
}

show_usage() {
    cat <<EOF
Usage: checkbuild [--json]

Query Jenkins for the current build status of this repository's job.

Options:
  --json    Output results in JSON format for machine parsing
  --help    Show this help message

Required Environment Variables:
  JENKINS_URL        Base URL of the Jenkins server
  JENKINS_USER_ID    Jenkins username for API authentication
  JENKINS_API_TOKEN  Jenkins API token for authentication

Exit Codes:
  0  Last build was successful
  1  Last build failed, or an error occurred
  2  Build is currently in progress
EOF
}

# =============================================================================
# Retry Logic
# =============================================================================

# Execute a function with retry logic for transient failures
# Usage: with_retry function_name [args...]
# Returns: Result of the function call, or exits on persistent failure
with_retry() {
    local func="$1"
    shift
    local attempt=1
    local result

    while [[ $attempt -le $MAX_RETRIES ]]; do
        if result=$("$func" "$@" 2>&1); then
            echo "$result"
            return 0
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_warning "Attempt $attempt failed, retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi

        ((attempt++))
    done

    log_error "Operation failed after $MAX_RETRIES attempts"
    return 1
}

# =============================================================================
# Main Flow Functions
# =============================================================================

# Startup validation sequence
# Returns: 0 on success, exits with error message on failure
startup_validation() {
    # Check dependencies first (before we need them)
    if ! validate_dependencies; then
        exit 1
    fi

    # Check environment variables
    if ! validate_environment; then
        exit 1
    fi

    # Check git repository
    if ! validate_git_repository; then
        exit 1
    fi

    return 0
}

# Get build information with retry
# Usage: fetch_build_info "job_name" "build_number"
# Returns: Build JSON on stdout
fetch_build_info() {
    local job_name="$1"
    local build_number="$2"

    local build_info
    build_info=$(get_build_info "$job_name" "$build_number")

    if [[ -z "$build_info" ]]; then
        return 1
    fi

    echo "$build_info"
}

# Main orchestration function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Run startup validation
    startup_validation

    # Discover job name
    log_info "Discovering Jenkins job name..."
    local job_name
    if ! job_name=$(discover_job_name); then
        exit 1
    fi
    log_success "Job name: $job_name"

    # Verify Jenkins connectivity
    if ! verify_jenkins_connection; then
        exit 1
    fi

    # Verify job exists
    if ! verify_job_exists "$job_name"; then
        exit 1
    fi

    # Get last build number
    log_info "Fetching last build information..."
    local build_number
    build_number=$(get_last_build_number "$job_name")

    if [[ "$build_number" == "0" || -z "$build_number" ]]; then
        log_error "No builds found for job '$job_name'"
        exit 1
    fi

    # Get build info with retry
    local build_json
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        build_json=$(fetch_build_info "$job_name" "$build_number" 2>/dev/null) || true

        if [[ -n "$build_json" ]]; then
            break
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_warning "Failed to fetch build info, retrying in ${RETRY_DELAY}s... (attempt $attempt/$MAX_RETRIES)"
            sleep "$RETRY_DELAY"
        fi

        ((attempt++))
    done

    if [[ -z "$build_json" ]]; then
        log_error "Failed to fetch build information after $MAX_RETRIES attempts"
        exit 1
    fi

    # Extract build status
    local result building
    result=$(echo "$build_json" | jq -r '.result // "null"')
    building=$(echo "$build_json" | jq -r '.building // false')

    log_success "Build #$build_number found"

    # Get console output for trigger detection and commit extraction
    log_info "Analyzing build details..."
    local console_output
    console_output=$(get_console_output "$job_name" "$build_number" 2>/dev/null) || true

    # Detect trigger type
    local trigger_type trigger_user
    if [[ -n "$console_output" ]]; then
        local trigger_info
        trigger_info=$(detect_trigger_type "$console_output")
        trigger_type=$(echo "$trigger_info" | head -1)
        trigger_user=$(echo "$trigger_info" | tail -1)
    else
        trigger_type="unknown"
        trigger_user="unknown"
    fi

    # Extract triggering commit
    local commit_info commit_sha commit_msg
    commit_info=$(extract_triggering_commit "$job_name" "$build_number" "$console_output")
    commit_sha=$(echo "$commit_info" | head -1)
    commit_msg=$(echo "$commit_info" | tail -1)

    # Correlate commit with local history
    local correlation_status
    correlation_status=$(correlate_commit "$commit_sha")

    # Determine output based on build status
    local exit_code

    if [[ "$building" == "true" ]]; then
        # Build is in progress
        local current_stage
        current_stage=$(get_current_stage "$job_name" "$build_number" 2>/dev/null) || true

        if [[ "$JSON_OUTPUT_MODE" == "true" ]]; then
            output_json "$job_name" "$build_number" "$build_json" \
                "$trigger_type" "$trigger_user" \
                "$commit_sha" "$commit_msg" \
                "$correlation_status" "$console_output"
        else
            display_building_output "$job_name" "$build_number" "$build_json" \
                "$trigger_type" "$trigger_user" \
                "$commit_sha" "$commit_msg" \
                "$correlation_status" "$current_stage"
        fi
        exit_code=2

    elif [[ "$result" == "SUCCESS" ]]; then
        # Build succeeded
        if [[ "$JSON_OUTPUT_MODE" == "true" ]]; then
            output_json "$job_name" "$build_number" "$build_json" \
                "$trigger_type" "$trigger_user" \
                "$commit_sha" "$commit_msg" \
                "$correlation_status" "$console_output"
        else
            display_success_output "$job_name" "$build_number" "$build_json" \
                "$trigger_type" "$trigger_user" \
                "$commit_sha" "$commit_msg" \
                "$correlation_status"
        fi
        exit_code=0

    else
        # Build failed (FAILURE, UNSTABLE, ABORTED, or other)
        if [[ "$JSON_OUTPUT_MODE" == "true" ]]; then
            output_json "$job_name" "$build_number" "$build_json" \
                "$trigger_type" "$trigger_user" \
                "$commit_sha" "$commit_msg" \
                "$correlation_status" "$console_output"
        else
            display_failure_output "$job_name" "$build_number" "$build_json" \
                "$trigger_type" "$trigger_user" \
                "$commit_sha" "$commit_msg" \
                "$correlation_status" "$console_output"
        fi
        exit_code=1
    fi

    exit "$exit_code"
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"
