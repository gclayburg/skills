_parse_timing_options() {
    TIMING_BUILD_NUMBER=""
    TIMING_BUILD_SET=false
    TIMING_JSON=false
    TIMING_COUNT=1
    TIMING_TESTS=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                TIMING_JSON=true
                shift
                ;;
            --tests)
                TIMING_TESTS=true
                shift
                ;;
            -n)
                if [[ -z "${2:-}" ]]; then
                    _usage_error "-n requires a value"
                fi
                if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                    _usage_error "-n value must be a positive integer"
                fi
                TIMING_COUNT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                _usage_error "Unknown option for timing command: $1"
                ;;
            *)
                if [[ "$TIMING_BUILD_SET" == "true" ]]; then
                    _usage_error "timing accepts at most one build number"
                fi
                TIMING_BUILD_NUMBER="$1"
                TIMING_BUILD_SET=true
                shift
                ;;
        esac
    done
}

_resolve_timing_build_number() {
    local job_name="$1"
    local requested_build="${2:-}"

    if [[ -n "$requested_build" && "$requested_build" != "0" ]]; then
        printf '%s\n' "$requested_build"
        return 0
    fi

    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        return 1
    fi

    local build_number
    build_number=$(jenkins_api "${job_path}/lastSuccessfulBuild/buildNumber" 2>/dev/null) || build_number=""
    build_number=$(printf '%s' "$build_number" | tr -d '\r\n[:space:]')

    if [[ ! "$build_number" =~ ^[0-9]+$ ]] || [[ "$build_number" == "0" ]]; then
        return 1
    fi

    printf '%s\n' "$build_number"
}

_fetch_test_report_timing() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo ""
        return 1
    fi

    local response http_code body
    response=$(jenkins_api_with_status "${job_path}/${build_number}/testReport/api/json?tree=duration,suites[name,duration,cases[className,name,duration,status]]" || true)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            printf '%s\n' "$body"
            return 0
            ;;
        404)
            echo ""
            return 0
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

_build_timing_test_suites() {
    local test_report_json="${1:-}"

    if [[ -z "$test_report_json" ]]; then
        echo "[]"
        return 0
    fi

    printf '%s\n' "$test_report_json" | jq -c '
        [
            (.suites // [])[]?
            | {
                name: (.name // "unknown"),
                durationMillis: (
                    ((.duration // 0) | tonumber? // 0) * 1000 | floor
                ),
                testCount: ((.cases // []) | length)
            }
            | if .testCount > 0 then . else . end
        ]
        | sort_by(.durationMillis)
        | reverse
    ' 2>/dev/null || echo "[]"
}

_build_timing_stages_json() {
    local stages_json="$1"
    local stage_agent_map_json="$2"
    local test_suites_json="${3:-[]}"

    printf '%s\n' "$stages_json" | jq -c \
        --argjson agent_map "$stage_agent_map_json" \
        --argjson test_suites "$test_suites_json" '
        [
            .[]?
            | . + {
                agent: ($agent_map[.name] // "")
            }
        ]
    ' 2>/dev/null || echo "[]"
}

_build_parallel_groups() {
    local stages_json="$1"
    local blue_nodes_json="$2"

    jq -n \
        --argjson stages "$stages_json" \
        --argjson nodes "$blue_nodes_json" '
        def node_by_name($name):
            first($nodes[]? | select((.name // "") == $name));
        def node_name_by_id($id):
            first($nodes[]? | select((.id // "" | tostring) == ($id | tostring))) | (.name // "");
        def raw_parallel_group($stage):
            (node_by_name($stage.name)) as $node
            | if $node == null or ($node.firstParent // "") == "" then
                ""
              else
                node_name_by_id($node.firstParent)
              end;
        def is_parallel_group_name($name):
            if $name == "" then
                false
            else
                ([$stages[]? | select(raw_parallel_group(.) == $name)] | length) > 1
            end;

        ($stages | map(
            . + {
                parallelGroup: (
                    (raw_parallel_group(.)) as $group
                    | if is_parallel_group_name($group) then $group else null end
                )
            }
        )) as $enriched
        | {
            stages: $enriched,
            parallelGroups: (
                $enriched
                | map(select(.parallelGroup != null))
                | group_by(.parallelGroup)
                | map({
                    name: .[0].parallelGroup,
                    wallDurationMillis: (map(.durationMillis // 0) | max // 0),
                    bottleneck: (max_by(.durationMillis // 0) | .name),
                    stages: map({
                        name,
                        status,
                        durationMillis,
                        agent
                    })
                })
            )
        }
    ' 2>/dev/null || echo '{"stages":[],"parallelGroups":[]}'
}

_get_parallel_group_for_stage() {
    local stage_name="$1"
    local groups_json="$2"

    printf '%s\n' "$groups_json" | jq -r \
        --arg stage_name "$stage_name" '
        first(
            .parallelGroups[]?
            | select(any(.stages[]?; (.name // "") == $stage_name))
            | .name
        ) // ""
    ' 2>/dev/null || echo ""
}

_identify_bottleneck() {
    local group_json="$1"

    printf '%s\n' "$group_json" | jq -r '.bottleneck // ""' 2>/dev/null || echo ""
}

_format_timing_stage_line() {
    local stage_json="$1"
    local slowest_stage="${2:-}"
    local include_tests="${3:-false}"

    local stage_name duration_ms agent file_count test_count suffix
    stage_name=$(printf '%s\n' "$stage_json" | jq -r '.name // "unknown"')
    duration_ms=$(printf '%s\n' "$stage_json" | jq -r '.durationMillis // 0')
    agent=$(printf '%s\n' "$stage_json" | jq -r '.agent // empty')
    file_count=$(printf '%s\n' "$stage_json" | jq -r '.fileCount // 0')
    test_count=$(printf '%s\n' "$stage_json" | jq -r '.testCount // 0')
    suffix=""

    if [[ -n "$agent" ]]; then
        suffix="  ${agent}"
    fi

    if [[ "$include_tests" == "true" && ( "$file_count" -gt 0 || "$test_count" -gt 0 ) ]]; then
        suffix="${suffix}  (${file_count} files, ${test_count} tests)"
    fi

    if [[ -n "$slowest_stage" && "$stage_name" == "$slowest_stage" ]]; then
        suffix="${suffix}  <- slowest"
    fi

    printf '  %s  %s%s\n' "$stage_name" "$(format_stage_duration "$duration_ms")" "$suffix"
}

_render_timing_human() {
    local timing_json="$1"
    local include_tests="${2:-false}"

    local build_number total_duration sequential_count group_count
    build_number=$(printf '%s\n' "$timing_json" | jq -r '.build.number // 0')
    total_duration=$(printf '%s\n' "$timing_json" | jq -r '.build.totalDurationMillis // 0')
    sequential_count=$(printf '%s\n' "$timing_json" | jq -r '[.stages[]? | select(.parallelGroup == null)] | length')
    group_count=$(printf '%s\n' "$timing_json" | jq -r '.parallelGroups | length')

    printf 'Build #%s - total %s\n' "$build_number" "$(format_duration "$total_duration")"

    if [[ "$sequential_count" -gt 0 ]]; then
        echo "Sequential stages:"
        while IFS= read -r stage_json; do
            [[ -n "$stage_json" ]] || continue
            _format_timing_stage_line "$stage_json" "" "$include_tests"
        done < <(printf '%s\n' "$timing_json" | jq -c '.stages[]? | select(.parallelGroup == null)')
    fi

    if [[ "$group_count" -gt 0 ]]; then
        while IFS= read -r group_json; do
            [[ -n "$group_json" ]] || continue
            local group_name wall_duration bottleneck
            group_name=$(printf '%s\n' "$group_json" | jq -r '.name // "Parallel"')
            wall_duration=$(printf '%s\n' "$group_json" | jq -r '.wallDurationMillis // 0')
            bottleneck=$(_identify_bottleneck "$group_json")
            printf 'Parallel group: %s (wall %s, bottleneck: %s)\n' \
                "$group_name" "$(format_stage_duration "$wall_duration")" "$bottleneck"
            while IFS= read -r stage_json; do
                [[ -n "$stage_json" ]] || continue
                _format_timing_stage_line "$stage_json" "$bottleneck" "$include_tests"
            done < <(printf '%s\n' "$timing_json" | jq -c --arg group_name "$group_name" '
                .stages[]? | select((.parallelGroup // "") == $group_name)
            ')
        done < <(printf '%s\n' "$timing_json" | jq -c '.parallelGroups[]?')
    fi

    if [[ "$include_tests" == "true" ]]; then
        local test_suite_count
        test_suite_count=$(printf '%s\n' "$timing_json" | jq -r '.testSuites | length')
        if [[ "$test_suite_count" -gt 0 ]]; then
            echo "Test suite timing (top 10 slowest):"
            printf '%s\n' "$timing_json" | jq -c '.testSuites[:10][]?' | while IFS= read -r suite_json; do
                local suite_name suite_duration suite_tests
                suite_name=$(printf '%s\n' "$suite_json" | jq -r '.name // "unknown"')
                suite_duration=$(printf '%s\n' "$suite_json" | jq -r '.durationMillis // 0')
                suite_tests=$(printf '%s\n' "$suite_json" | jq -r '.testCount // 0')
                printf '  %s  %s  (%s tests)\n' "$suite_name" "$(format_stage_duration "$suite_duration")" "$suite_tests"
            done
        fi
    fi
}

_render_timing_json() {
    local timing_json="$1"
    printf '%s\n' "$timing_json" | jq '.'
}

_render_timing_for_build() {
    local job_name="$1"
    local build_number="$2"

    local build_info_json total_duration stages_json blue_nodes_json console_output
    local stage_agent_map_json test_report_json test_suites_json grouped_json timing_json

    build_info_json=$(get_build_info "$job_name" "$build_number")
    total_duration=$(printf '%s\n' "$build_info_json" | jq -r '.duration // 0' 2>/dev/null) || total_duration=0
    stages_json=$(get_all_stages "$job_name" "$build_number")
    blue_nodes_json=$(get_blue_ocean_nodes "$job_name" "$build_number")
    console_output=$(get_console_output "$job_name" "$build_number")
    stage_agent_map_json=$(_build_stage_agent_map "$console_output")

    test_report_json=""
    if [[ "$TIMING_TESTS" == "true" || "$TIMING_JSON" == "true" ]]; then
        test_report_json=$(_fetch_test_report_timing "$job_name" "$build_number" 2>/dev/null) || test_report_json=""
    fi
    test_suites_json=$(_build_timing_test_suites "$test_report_json")
    stages_json=$(_build_timing_stages_json "$stages_json" "$stage_agent_map_json" "$test_suites_json")
    grouped_json=$(_build_parallel_groups "$stages_json" "$blue_nodes_json")

    timing_json=$(jq -n \
        --argjson build_number "$build_number" \
        --argjson total_duration "$total_duration" \
        --argjson stages "$(printf '%s\n' "$grouped_json" | jq '.stages // []')" \
        --argjson parallel_groups "$(printf '%s\n' "$grouped_json" | jq '.parallelGroups // []')" \
        --argjson test_suites "$test_suites_json" '
        {
            build: {
                number: $build_number,
                totalDurationMillis: $total_duration
            },
            stages: $stages,
            parallelGroups: $parallel_groups,
            testSuites: $test_suites
        }
    ')

    if [[ "$TIMING_JSON" == "true" ]]; then
        _render_timing_json "$timing_json"
    else
        _render_timing_human "$timing_json" "$TIMING_TESTS"
    fi
}

cmd_timing() {
    _parse_timing_options "$@"

    if ! _validate_jenkins_setup "inspect Jenkins build timing" "status"; then
        return 1
    fi

    local resolved_build
    if ! resolved_build=$(_resolve_timing_build_number "$_VALIDATED_JOB_NAME" "$TIMING_BUILD_NUMBER"); then
        bg_log_error "Cannot inspect Jenkins build timing - could not resolve build number"
        return 1
    fi

    local start_build end_build
    end_build="$resolved_build"
    start_build=$((end_build - TIMING_COUNT + 1))
    if [[ "$start_build" -lt 1 ]]; then
        start_build=1
    fi

    local rendered_json="[]"
    local build_number first_output=true
    for ((build_number = start_build; build_number <= end_build; build_number++)); do
        local build_render
        build_render=$(_render_timing_for_build "$_VALIDATED_JOB_NAME" "$build_number") || return 1

        if [[ "$TIMING_JSON" == "true" ]]; then
            rendered_json=$(printf '%s\n' "$rendered_json" | jq \
                --argjson build_render "$build_render" '. + [$build_render]')
        else
            if [[ "$first_output" != "true" ]]; then
                echo ""
            fi
            printf '%s\n' "$build_render"
        fi

        first_output=false
    done

    if [[ "$TIMING_JSON" == "true" ]]; then
        if [[ "$TIMING_COUNT" -eq 1 ]]; then
            printf '%s\n' "$rendered_json" | jq '.[0]'
        else
            printf '%s\n' "$rendered_json" | jq '.'
        fi
    fi
}
