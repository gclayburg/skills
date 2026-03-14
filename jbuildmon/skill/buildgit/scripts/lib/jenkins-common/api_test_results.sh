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

    curl -s -f -g -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url"
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

    curl -s -g -w "\n%{http_code}" -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" "$url"
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
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        log_error "Invalid Jenkins job name: '$job_name'"
        return 1
    fi

    response=$(jenkins_api_with_status "${job_path}/api/json")
    http_code=$(echo "$response" | tail -1)

    case "$http_code" in
        200)
            bg_log_success "Job '$job_name' found"
            JOB_URL="${JENKINS_URL}${job_path}"
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
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        log_error "Invalid Jenkins job name: '$job_name'"
        return 1
    fi

    local response http_code location_header

    # POST to the build endpoint
    # Use -D to capture headers to a temp file
    local header_file
    header_file=$(mktemp)

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
        -D "$header_file" \
        "${JENKINS_URL}${job_path}/build")

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
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo ""
        return 0
    fi
    jenkins_api "${job_path}/${build_number}/api/json" 2>/dev/null || echo ""
}

# Get console text output for a build
# Usage: get_console_output "job-name" "build-number"
# Returns: Console text, empty string on failure
get_console_output() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo ""
        return 0
    fi
    jenkins_api "${job_path}/${build_number}/consoleText" 2>/dev/null || echo ""
}

_STAGE_CONSOLE_AVAILABLE_STAGES=""
_STAGE_CONSOLE_AMBIGUOUS_STAGES=""

_normalize_stage_name_for_lookup() {
    local stage_name="$1"
    printf '%s\n' "${stage_name#Branch: }"
}

_stage_lookup_label() {
    local stage_name="$1"
    printf '%s\n' "$stage_name" | tr '[:upper:]' '[:lower:]'
}

_find_stage_console_match() {
    local stages_json="$1"
    local requested_stage_name="$2"
    local normalized_requested requested_lower normalized_lower

    normalized_requested=$(_normalize_stage_name_for_lookup "$requested_stage_name")
    requested_lower=$(_stage_lookup_label "$requested_stage_name")
    normalized_lower=$(_stage_lookup_label "$normalized_requested")
    _STAGE_CONSOLE_AMBIGUOUS_STAGES=""

    if [[ -z "$stages_json" || "$stages_json" == "[]" ]]; then
        return 1
    fi

    local match_json
    match_json=$(echo "$stages_json" | jq -c \
        --arg requested "$requested_stage_name" \
        --arg normalized "$normalized_requested" \
        --arg requested_lower "$requested_lower" \
        --arg normalized_lower "$normalized_lower" '
        def normalized_name($name): ($name | sub("^Branch: "; ""));
        def lowered($value): ($value | ascii_downcase);
        def exact_match:
            map(select((.name // "") == $requested or normalized_name(.name // "") == $normalized));
        def exact_ci_match:
            map(select(lowered(.name // "") == $requested_lower or lowered(normalized_name(.name // "")) == $normalized_lower));
        def contains_ci_match:
            map(select(
                lowered(.name // "") | contains($requested_lower) or contains($normalized_lower)
            ));
        def best_match:
            (exact_match) as $exact
            | if ($exact | length) > 0 then $exact
              else
                (exact_ci_match) as $exact_ci
                | if ($exact_ci | length) > 0 then $exact_ci else contains_ci_match end
              end;

        (best_match) as $matches
        | if ($matches | length) == 1 then
            {status: "ok", match: $matches[0]}
          elif ($matches | length) > 1 then
            {status: "ambiguous", matches: ($matches | map(.name))}
          else
            {status: "missing"}
          end
    ' 2>/dev/null) || return 1

    local match_status
    match_status=$(echo "$match_json" | jq -r '.status // "missing"' 2>/dev/null)
    case "$match_status" in
        ok)
            echo "$match_json" | jq -c '.match' 2>/dev/null
            return 0
            ;;
        ambiguous)
            _STAGE_CONSOLE_AMBIGUOUS_STAGES=$(echo "$match_json" | jq -r '.matches[]' 2>/dev/null || true)
            return 4
            ;;
        *)
            return 1
            ;;
    esac
}

_get_stage_console_descendants() {
    local stages_json="$1"
    local blue_nodes_json="$2"
    local root_stage_id="$3"

    if [[ -z "$stages_json" || "$stages_json" == "[]" || -z "$blue_nodes_json" || "$blue_nodes_json" == "[]" || -z "$root_stage_id" ]]; then
        echo "[]"
        return 0
    fi

    echo "$stages_json" | jq -c \
        --arg root_id "$root_stage_id" \
        --argjson nodes "$blue_nodes_json" '
        def node_by_id($id):
            first($nodes[] | select((.id // "" | tostring) == ($id | tostring)));
        def is_descendant_of($id):
            if ($id | tostring) == ($root_id | tostring) then
                true
            else
                (node_by_id($id)) as $node
                | if ($node == null) then
                    false
                  else
                    ($node.firstParent // "") as $parent
                    | if $parent == "" then
                        false
                      else
                        is_descendant_of($parent)
                      end
                  end
            end;

        [ .[] | select((.id // "") != "" and is_descendant_of(.id)) ]
    ' 2>/dev/null || echo "[]"
}

_get_stage_console_log_text() {
    local job_path="$1"
    local build_number="$2"
    local stage_id="$3"

    local response http_code body
    response=$(jenkins_api_with_status "${job_path}/${build_number}/execution/node/${stage_id}/wfapi/log" || true)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        return 1
    fi

    local body_type log_text
    body_type=$(echo "$body" | jq -r 'type // empty' 2>/dev/null) || true
    log_text=$(echo "$body" | jq -r 'if type == "object" then (.text // "") else empty end' 2>/dev/null) || true
    if [[ "$body_type" == "object" ]]; then
        printf '%s' "$log_text" | perl -0pe 's/<[^>]+>//g; s/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/\r//g'
    else
        printf '%s' "$body"
    fi
}

_get_stage_console_flow_nodes() {
    local job_path="$1"
    local build_number="$2"
    local stage_id="$3"

    if [[ -z "$job_path" || -z "$build_number" || -z "$stage_id" ]]; then
        echo "[]"
        return 0
    fi

    local response
    response=$(jenkins_api "${job_path}/${build_number}/execution/node/${stage_id}/wfapi/describe" 2>/dev/null) || true
    if [[ -z "$response" ]]; then
        echo "[]"
        return 0
    fi

    echo "$response" | jq -c '
        def flatten_nodes($nodes):
            [
                $nodes[]?
                | {id: (.id // ""), name: (.name // "")},
                  ((.stageFlowNodes // []) | flatten_nodes(.))[]
            ];
        flatten_nodes(.stageFlowNodes // [])
    ' 2>/dev/null || echo "[]"
}

_get_stage_console_candidate_nodes() {
    local job_path="$1"
    local build_number="$2"
    local stages_json="$3"
    local blue_nodes_json="$4"
    local root_stage_id="$5"

    local result_json descendant_stages_json descendant_count descendant_index
    result_json=$(_get_stage_console_flow_nodes "$job_path" "$build_number" "$root_stage_id")
    descendant_stages_json=$(_get_stage_console_descendants "$stages_json" "$blue_nodes_json" "$root_stage_id")
    descendant_count=$(echo "$descendant_stages_json" | jq 'length' 2>/dev/null || echo 0)
    descendant_index=0

    while [[ "$descendant_index" -lt "$descendant_count" ]]; do
        local descendant_json descendant_id descendant_flow_nodes_json
        descendant_json=$(echo "$descendant_stages_json" | jq -c ".[$descendant_index]" 2>/dev/null)
        descendant_id=$(echo "$descendant_json" | jq -r '.id // empty' 2>/dev/null)
        descendant_index=$((descendant_index + 1))

        if [[ -z "$descendant_id" || "$descendant_id" == "$root_stage_id" ]]; then
            continue
        fi

        descendant_flow_nodes_json=$(_get_stage_console_flow_nodes "$job_path" "$build_number" "$descendant_id")
        result_json=$(jq -cs '
            add
            | reduce .[] as $node (
                [];
                if (($node.id // "") == "") then
                    .
                elif any(.[]; (.id // "") == ($node.id // "")) then
                    .
                else
                    . + [$node]
                end
            )
        ' \
            <(printf '%s\n' "$result_json") \
            <(printf '%s\n' "[$descendant_json]") \
            <(printf '%s\n' "$descendant_flow_nodes_json") 2>/dev/null)
    done

    printf '%s\n' "${result_json:-[]}"
}

get_console_output_raw() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        return 1
    fi

    local response http_code body
    response=$(jenkins_api_with_status "${job_path}/${build_number}/consoleText" || true)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]]; then
        printf '%s\n' "$body"
        return 0
    fi
    return 1
}

get_stage_console_output() {
    local job_name="$1"
    local build_number="$2"
    local requested_stage_name="$3"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        return 1
    fi

    local stages_json blue_nodes_json matched_stage_json matched_stage_id matched_stage_name
    stages_json=$(get_all_stages "$job_name" "$build_number")
    _STAGE_CONSOLE_AVAILABLE_STAGES=$(echo "$stages_json" | jq -r '.[].name' 2>/dev/null || true)
    matched_stage_json=$(_find_stage_console_match "$stages_json" "$requested_stage_name") || {
        local match_rc=$?
        if [[ "$match_rc" -eq 4 ]]; then
            return 4
        fi
        return 3
    }

    matched_stage_id=$(echo "$matched_stage_json" | jq -r '.id // empty' 2>/dev/null)
    matched_stage_name=$(echo "$matched_stage_json" | jq -r '.name // empty' 2>/dev/null)
    if [[ -z "$matched_stage_id" ]]; then
        return 3
    fi

    local direct_log_text
    if ! direct_log_text=$(_get_stage_console_log_text "$job_path" "$build_number" "$matched_stage_id"); then
        return 1
    fi

    if [[ -n "${direct_log_text//[$' \t\r\n']}" ]]; then
        printf '%s\n' "$direct_log_text"
        return 0
    fi

    blue_nodes_json=$(get_blue_ocean_nodes "$job_name" "$build_number" 2>/dev/null) || blue_nodes_json="[]"

    local candidate_nodes_json
    candidate_nodes_json=$(_get_stage_console_candidate_nodes "$job_path" "$build_number" "$stages_json" "$blue_nodes_json" "$matched_stage_id")

    local candidate_count candidate_index combined_output
    candidate_count=$(echo "$candidate_nodes_json" | jq 'length' 2>/dev/null || echo 0)
    if [[ "$candidate_count" -eq 0 ]]; then
        printf '%s\n' "$direct_log_text"
        return 0
    fi

    combined_output=""
    candidate_index=0
    while [[ "$candidate_index" -lt "$candidate_count" ]]; do
        local candidate_id candidate_name candidate_log
        candidate_id=$(echo "$candidate_nodes_json" | jq -r ".[$candidate_index].id // empty" 2>/dev/null)
        candidate_name=$(echo "$candidate_nodes_json" | jq -r ".[$candidate_index].name // empty" 2>/dev/null)
        candidate_index=$((candidate_index + 1))
        [[ -z "$candidate_id" || "$candidate_id" == "$matched_stage_id" ]] && continue
        if ! candidate_log=$(_get_stage_console_log_text "$job_path" "$build_number" "$candidate_id"); then
            return 1
        fi
        if [[ -z "${candidate_log//[$' \t\r\n']}" ]]; then
            continue
        fi
        combined_output+=$'\n'"===== ${matched_stage_name} -> ${candidate_name} ====="$'\n'
        combined_output+="$candidate_log"
        combined_output+=$'\n'
    done

    if [[ -n "${combined_output//[$' \t\r\n']}" ]]; then
        printf '%s' "$combined_output"
    else
        printf '%s\n' "$direct_log_text"
    fi
    return 0
}

# Get currently executing stage name from workflow API
# Usage: get_current_stage "job-name" "build-number"
# Returns: Stage name if a stage is IN_PROGRESS, empty string otherwise
get_current_stage() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        return 0
    fi

    local response
    response=$(jenkins_api "${job_path}/${build_number}/wfapi/describe" 2>/dev/null) || true

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
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo "[]"
        return 0
    fi

    local response
    response=$(jenkins_api "${job_path}/${build_number}/wfapi/describe" 2>/dev/null) || true

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
            id: (.id // ""),
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

get_blue_ocean_nodes() {
    local job_name="$1"
    local build_number="$2"

    local response endpoint
    if [[ "$job_name" == */* ]]; then
        local top_job branch_job encoded_top encoded_branch
        top_job="${job_name%%/*}"
        branch_job="${job_name#*/}"
        encoded_top=$(printf '%s' "$top_job" | jq -sRr @uri)
        encoded_branch=$(printf '%s' "$branch_job" | jq -sRr @uri)
        endpoint="/blue/rest/organizations/jenkins/pipelines/${encoded_top}/branches/${encoded_branch}/runs/${build_number}/nodes/"
    else
        local encoded_job
        encoded_job=$(printf '%s' "$job_name" | jq -sRr @uri)
        endpoint="/blue/rest/organizations/jenkins/pipelines/${encoded_job}/runs/${build_number}/nodes/"
    fi

    response=$(jenkins_api "$endpoint" 2>/dev/null) || true
    if [[ -z "$response" ]]; then
        echo "[]"
        return 0
    fi

    echo "$response" | jq -c '
        map({
            id: (.id // ""),
            name: (.displayName // .name // ""),
            type: (.type // ""),
            firstParent: (.firstParent // ""),
            startTime: (.startTime // ""),
            durationMillis: (.durationInMillis // 0)
        })
    ' 2>/dev/null || echo "[]"
}

get_blue_ocean_node_steps() {
    local job_name="$1"
    local build_number="$2"
    local node_id="$3"

    local response endpoint
    if [[ "$job_name" == */* ]]; then
        local top_job branch_job encoded_top encoded_branch
        top_job="${job_name%%/*}"
        branch_job="${job_name#*/}"
        encoded_top=$(printf '%s' "$top_job" | jq -sRr @uri)
        encoded_branch=$(printf '%s' "$branch_job" | jq -sRr @uri)
        endpoint="/blue/rest/organizations/jenkins/pipelines/${encoded_top}/branches/${encoded_branch}/runs/${build_number}/nodes/${node_id}/steps/"
    else
        local encoded_job
        encoded_job=$(printf '%s' "$job_name" | jq -sRr @uri)
        endpoint="/blue/rest/organizations/jenkins/pipelines/${encoded_job}/runs/${build_number}/nodes/${node_id}/steps/"
    fi

    response=$(jenkins_api "$endpoint" 2>/dev/null) || true
    if [[ -z "$response" ]]; then
        echo "[]"
        return 0
    fi

    echo "$response" | jq -c '
        map({
            displayName: (.displayName // ""),
            displayDescription: (.displayDescription // "")
        })
    ' 2>/dev/null || echo "[]"
}

# Get first failed stage name from workflow API
# Usage: get_failed_stage "job-name" "build-number"
# Returns: Stage name if a stage is FAILED or UNSTABLE, empty string otherwise
get_failed_stage() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        return 0
    fi

    local response
    response=$(jenkins_api "${job_path}/${build_number}/wfapi/describe" 2>/dev/null) || true

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
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo "0"
        return 0
    fi
    response=$(jenkins_api "${job_path}/api/json" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.lastBuild.number // 0'
    else
        echo "0"
    fi
}

# =============================================================================
# Test Results Functions
# =============================================================================

# Track builds that already emitted a test-results communication warning.
_TEST_RESULTS_WARNED_BUILDS=""

_test_results_warn_key() {
    local job_name="$1"
    local build_number="$2"
    echo "${job_name}#${build_number}"
}

_note_test_results_comm_failure() {
    local job_name="$1"
    local build_number="$2"
    local key
    key=$(_test_results_warn_key "$job_name" "$build_number")
    if [[ ",${_TEST_RESULTS_WARNED_BUILDS}," == *",${key},"* ]]; then
        return 0
    fi
    _TEST_RESULTS_WARNED_BUILDS="${_TEST_RESULTS_WARNED_BUILDS},${key}"
    log_error "Could not retrieve test results (communication error)"
}

display_test_results_comm_error() {
    local warning_text="⚠ Communication error retrieving test results"
    if [[ -n "${COLOR_YELLOW}" ]]; then
        warning_text="${COLOR_YELLOW}${warning_text}${COLOR_RESET}"
    fi
    echo ""
    echo "Test Results: ${warning_text}"
}

# Fetch test results from Jenkins test report API
# Usage: fetch_test_results "job-name" "build-number"
# Returns: JSON test report on success, empty string if not available
# Spec: test-failure-display-spec.md, Section: Test Report Detection (1.1-1.2)
fetch_test_results() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo ""
        return 0
    fi

    local response
    local http_code
    local body

    # Query the test report API
    response=$(jenkins_api_with_status "${job_path}/${build_number}/testReport/api/json" || true)

    # Split response into body and status code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
        http_code="000"
    fi

    case "$http_code" in
        200)
            # Test report available - return the JSON
            echo "$body"
            return 0
            ;;
        404)
            # No test report available - silently return empty
            # This is expected for builds without junit results
            echo ""
            return 0
            ;;
        000)
            # Communication failure (DNS/network/sandbox/connection issue)
            echo ""
            return 2
            ;;
        *)
            # Other HTTP errors are treated as communication failures
            echo ""
            return 2
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
    local max_error_lines="${MAX_ERROR_LINES:-5}"
    local verbose_mode=false
    if [[ "${VERBOSE_MODE:-false}" == "true" ]]; then
        verbose_mode=true
    fi

    echo "$test_json" | jq -r \
        --argjson max_display "$max_display" \
        --argjson max_error_len "$max_error_len" \
        --argjson max_error_lines "$max_error_lines" \
        --argjson verbose "$verbose_mode" '
        def maybe_truncate_text($value):
            if $value == null then
                null
            elif $verbose then
                ($value | tostring)
            else
                (($value | tostring)[:$max_error_len])
            end;

        def maybe_truncate_lines($value):
            if $value == null or ($value | tostring) == "" then
                null
            elif $verbose then
                ($value | tostring)
            else
                (($value | tostring | split("\n")) as $lines |
                    if ($lines | length) <= $max_error_lines then
                        ($value | tostring)
                    else
                        (($lines[:$max_error_lines] | join("\n")) + "\n...")
                    end)
            end;

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
                    maybe_truncate_text(.errorDetails)
                else
                    null
                end
            ),
            errorStackTrace: maybe_truncate_lines(.errorStackTrace // null),
            duration: (.duration // 0),
            age: (.age // 0),
            stdout: (if $verbose then (.stdout // null) else null end)
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
    local verbose_mode=false
    if [[ "${VERBOSE_MODE:-false}" == "true" ]]; then
        verbose_mode=true
    fi

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
        local class_name test_name error_details error_stack stdout_text age

        class_name=$(echo "$failed_tests" | jq -r ".[$i].className")
        test_name=$(echo "$failed_tests" | jq -r ".[$i].name")
        error_details=$(echo "$failed_tests" | jq -r ".[$i].errorDetails // empty")
        error_stack=$(echo "$failed_tests" | jq -r ".[$i].errorStackTrace // empty")
        stdout_text=$(echo "$failed_tests" | jq -r ".[$i].stdout // empty")
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

            if [[ "$verbose_mode" == "true" || "$line_count" -le "$max_error_lines" ]]; then
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

        if [[ "$verbose_mode" == "true" && -n "$stdout_text" && "$stdout_text" != "null" ]]; then
            echo "    Stdout:"
            echo "$stdout_text" | while IFS= read -r line; do
                echo "      ${line}"
            done
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
    local verbose_mode=false
    if [[ "${VERBOSE_MODE:-false}" == "true" ]]; then
        verbose_mode=true
    fi

    transformed_failed_tests=$(echo "$failed_tests_array" | jq --argjson verbose "$verbose_mode" '
        map(
            {
                class_name: .className,
                test_name: .name,
                duration_seconds: .duration,
                age: .age,
                error_details: .errorDetails,
                error_stack_trace: .errorStackTrace
            } + (if $verbose then {stdout: .stdout} else {} end)
        )
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
