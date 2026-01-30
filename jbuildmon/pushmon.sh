#!/usr/bin/env bash
#
# pushmon.sh - Jenkins Build Monitor
# Commits, pushes, and monitors Jenkins builds with real-time feedback
#

set -euo pipefail

# =============================================================================
# Source Shared Library
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/jenkins-common.sh"

# =============================================================================
# Configuration Constants (see spec: Configuration Constants section)
# =============================================================================
BRANCH="${BRANCH:-main}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
MAX_BUILD_TIME="${MAX_BUILD_TIME:-1800}"
BUILD_START_TIMEOUT="${BUILD_START_TIMEOUT:-120}"
MAX_CONSECUTIVE_FAILURES="${MAX_CONSECUTIVE_FAILURES:-5}"

# =============================================================================
# Global State
# =============================================================================
BUILD_NUMBER=""
# JOB_URL is provided by jenkins-common.sh
HAS_STAGED_CHANGES=false

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
Usage: $(basename "$0") [OPTIONS]

Options:
  -j, --job <job>     Specify Jenkins job name (overrides auto-detection)
  -m, --msg <message> Git commit message (required if staged changes exist)
  -h, --help          Show this help message

If --job is not specified, the job name is auto-detected from:
  1. JOB_NAME=<value> in AGENTS.md
  2. Git origin URL

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
# Argument Parsing (see spec: fixjobflags-spec.md Section 3)
# =============================================================================
parse_arguments() {
    JOB_NAME=""
    COMMIT_MESSAGE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--job)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires a job name"
                    exit 1
                fi
                JOB_NAME="$2"
                shift 2
                ;;
            -m|--msg)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option $1 requires a commit message"
                    exit 1
                fi
                COMMIT_MESSAGE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
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

# get_last_build_number is provided by jenkins-common.sh

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

# get_build_info and get_current_stage are provided by jenkins-common.sh

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
# All failure analysis functions are provided by jenkins-common.sh:
#   get_failed_stage, get_console_output, detect_all_downstream_builds,
#   check_build_failed, find_failed_downstream_build, extract_error_lines,
#   extract_stage_logs, display_build_metadata, analyze_failure
# =============================================================================

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
    # Parse arguments
    parse_arguments "$@"

    # Validate environment and dependencies (library functions return 1 on failure)
    validate_environment || exit 1
    validate_dependencies || exit 1
    validate_git_repository || exit 1

    # Resolve job name
    local job_name
    if [[ -n "$JOB_NAME" ]]; then
        job_name="$JOB_NAME"
        log_info "Using specified job: $job_name"
    else
        log_info "Discovering Jenkins job name..."
        if ! job_name=$(discover_job_name); then
            log_error "Could not determine Jenkins job name"
            log_info "To fix this, either:"
            log_info "  1. Add JOB_NAME=<job-name> to AGENTS.md in your repository root"
            log_info "  2. Use the --job <job> or -j <job> flag"
            exit 1
        fi
        log_success "Job name: $job_name"
    fi

    # Display configuration
    display_config_summary "$job_name"

    # Verify Jenkins connectivity (library functions return 1 on failure)
    verify_jenkins_connection || exit 1
    verify_job_exists "$job_name" || exit 1

    # Git operations
    check_for_changes

    # Validate commit message for staged changes
    if [[ "$HAS_STAGED_CHANGES" == true && -z "$COMMIT_MESSAGE" ]]; then
        log_error "Staged changes found but no commit message provided"
        log_info "Use -m or --msg to specify a commit message"
        exit 1
    fi

    if [[ "$HAS_STAGED_CHANGES" == true ]]; then
        commit_changes "$COMMIT_MESSAGE"
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
