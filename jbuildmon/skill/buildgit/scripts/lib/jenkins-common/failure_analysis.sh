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
# Usage: _select_downstream_build_for_stage "Stage Name" "$downstream_lines" "$stage_logs"
# Returns: "job-name build-number" or empty
_downstream_stage_job_match_score() {
    local stage_name="$1"
    local job_name="$2"

    local normalized_stage_name
    normalized_stage_name=$(echo "$stage_name" | tr '[:upper:]' '[:lower:]' | \
        sed -E 's/[^a-z0-9]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')
    [[ -z "$normalized_stage_name" ]] && echo "0" && return

    local job_lc
    job_lc=$(echo "$job_name" | tr '[:upper:]' '[:lower:]')

    # Split job name into segments for word-level matching
    local job_segments
    job_segments=$(echo "$job_lc" | tr '-' ' ')

    local score=0
    local token
    for token in $normalized_stage_name; do
        [[ ${#token} -lt 3 ]] && continue
        case "$token" in
            build|trigger|stage|component|components|parallel|test|tests)
                continue
                ;;
        esac
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

    echo "$score"
}

_select_downstream_build_for_stage() {
    local stage_name="$1"
    local downstream_lines="$2"
    local stage_logs="${3:-}"

    [[ -z "$downstream_lines" ]] && return

    local stage_start_count=0
    if [[ -n "$stage_logs" ]]; then
        stage_start_count=$(printf '%s\n' "$stage_logs" | grep -c '^\[Pipeline\] { (' 2>/dev/null || true)
    fi
    local contaminated_parallel_logs=false
    if [[ "$stage_start_count" -gt 1 ]]; then
        contaminated_parallel_logs=true
    fi

    local line_count
    line_count=$(echo "$downstream_lines" | sed '/^[[:space:]]*$/d' | wc -l | tr -d '[:space:]')
    if [[ "$line_count" -le 1 ]]; then
        local single_line single_job single_score
        single_line=$(echo "$downstream_lines" | sed '/^[[:space:]]*$/d' | head -1)
        single_job=$(echo "$single_line" | awk '{print $1}')
        single_score=$(_downstream_stage_job_match_score "$stage_name" "$single_job")
        if [[ "$single_score" -gt 0 || "$contaminated_parallel_logs" != "true" ]]; then
            echo "$single_line"
        fi
        return
    fi

    local best_line=""
    local best_score=-1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local job build
        job=$(echo "$line" | awk '{print $1}')
        build=$(echo "$line" | awk '{print $2}')
        [[ -z "$job" || -z "$build" ]] && continue

        local score
        score=$(_downstream_stage_job_match_score "$stage_name" "$job")

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

    if [[ -n "$best_line" && "$best_score" -gt 0 ]]; then
        echo "$best_line"
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
            found_parallel_block=0
            nested_same_name_depth=0
        }

        function flush_block(   i) {
            if (has_parallel && !found_parallel_block) {
                for (i = 1; i <= branch_count; i++) {
                    print branch_order[i]
                }
                found_parallel_block=1
            }
            delete branch_seen
            delete branch_order
            branch_count=0
            has_parallel=0
            nested_same_name_depth=0
        }

        # Start a new matching stage block when not already inside one
        /\[Pipeline\] \{ \(/ && index($0, "(" stage ")") && in_stage == 0 && found_parallel_block == 0 {
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

            if (index($0, "(" stage ")") && $0 ~ /\[Pipeline\] \{ \(/ && depth > 0) {
                nested_same_name_depth = depth + 1
                depth++
                next
            }

            if (nested_same_name_depth == 0 && match($0, /\(Branch: [^)]+\)/)) {
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
                if (nested_same_name_depth > 0 && depth < nested_same_name_depth) {
                    nested_same_name_depth=0
                }
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
            if (in_stage == 1 && found_parallel_block == 0) {
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

# Detect ordered named substages contained within each parallel branch block.
# Usage: _detect_branch_substages "$console_output" "wrapper-stage-name"
# Returns: JSON object like {"Branch A":["Setup","Test"],"Branch B":[]}
_detect_branch_substages() {
    local console_output="$1"
    local wrapper_stage="$2"

    local branches_json
    branches_json=$(_detect_parallel_branches "$console_output" "$wrapper_stage")
    if [[ -z "$branches_json" || "$branches_json" == "[]" ]]; then
        echo "{}"
        return 0
    fi

    local result="{}"
    local branch_name
    while IFS= read -r branch_name; do
        [[ -z "$branch_name" ]] && continue

        local branch_logs nested_branch_names substages
        branch_logs=$(extract_stage_logs "$console_output" "$branch_name")
        nested_branch_names=$(printf "%s\n" "$branch_logs" | awk '
            match($0, /\(Branch: [^)]+\)/) {
                branch = substr($0, RSTART + 9, RLENGTH - 10)
                if (!(branch in seen)) {
                    seen[branch] = 1
                    names[++count] = branch
                }
            }

            END {
                for (i = 1; i <= count; i++) {
                    printf "%s%s", names[i], (i < count ? "\034" : "")
                }
            }
        ')
        substages=$(printf "%s\n" "$branch_logs" | awk -v branch="$branch_name" '
            BEGIN {
                depth=0
            }

            /^\[Pipeline\] \{ \(.+\)$/ {
                stage_name = $0
                sub(/^\[Pipeline\] \{ \(/, "", stage_name)
                sub(/\)$/, "", stage_name)

                if (depth > 0 && stage_name != branch && stage_name !~ /^Branch:[[:space:]]+/) {
                    if (!(stage_name in seen)) {
                        seen[stage_name] = 1
                        print stage_name
                    }
                }

                depth++
                next
            }

            /^\[Pipeline\] \{$/ {
                depth++
                next
            }

            /^\[Pipeline\] \}/ {
                if (depth > 0) {
                    depth--
                }
                next
            }
        ')
        if [[ -n "$nested_branch_names" ]]; then
            substages=$(printf "%s\n" "$substages" | awk -v exclude="$nested_branch_names" '
                BEGIN {
                    split(exclude, excluded, "\034")
                    for (i in excluded) {
                        if (excluded[i] != "") {
                            skip[excluded[i]] = 1
                        }
                    }
                }

                {
                    if (!($0 in skip)) {
                        print
                    }
                }
            ')
        fi

        result=$(echo "$result" | jq --arg b "$branch_name" '. + {($b): []}')
        while IFS= read -r substage_name; do
            [[ -z "$substage_name" ]] && continue
            result=$(echo "$result" | jq \
                --arg b "$branch_name" \
                --arg s "$substage_name" \
                '. + {
                    ($b): (
                        (.[$b] // [])
                        + (if ((.[$b] // []) | index($s)) == null then [$s] else [] end)
                    )
                }')
        done <<< "$substages"
    done <<< "$(echo "$branches_json" | jq -r '.[]')"

    echo "$result"
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
        sed -E 's/.*Running on[[:space:]]+(.+)[[:space:]]+in[[:space:]]+\/.*/\1/' || true
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
    local test_results_json test_results_rc=0
    if test_results_json=$(fetch_test_results "$job_name" "$build_number"); then
        test_results_rc=0
    else
        test_results_rc=$?
        test_results_json=""
    fi
    if [[ "$test_results_rc" -eq 2 ]]; then
        _note_test_results_comm_failure "$job_name" "$build_number"
    fi
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
            local downstream_console_url
            downstream_console_url=$(jenkins_console_url "$downstream_job" "$downstream_build")
            if [[ -n "$downstream_console_url" ]]; then
                log_info "Full downstream console: ${downstream_console_url}"
            fi
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
