_parse_agents_options() {
    AGENTS_JSON=false
    AGENTS_LABEL=""
    AGENTS_VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                AGENTS_JSON=true
                shift
                ;;
            --label)
                shift
                if [[ -z "${1:-}" ]]; then
                    _usage_error "--label requires a label name"
                fi
                AGENTS_LABEL="$1"
                shift
                ;;
            --label=*)
                AGENTS_LABEL="${1#--label=}"
                if [[ -z "$AGENTS_LABEL" ]]; then
                    _usage_error "--label requires a label name"
                fi
                shift
                ;;
            -v|--verbose)
                AGENTS_VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                _usage_error "Unknown option for agents command: $1"
                ;;
        esac
    done
}

_fetch_computers() {
    jenkins_api "/computer/api/json?tree=computer[displayName,assignedLabels[name],numExecutors,idle,offline,temporarilyOffline,executors[currentExecutable[url]]]"
}

_fetch_label_info() {
    local label_name="$1"
    local encoded_label
    encoded_label=$(jq -rn --arg value "$label_name" '$value|@uri')
    jenkins_api "/label/${encoded_label}/api/json"
}

_build_agents_data() {
    local label_filter="${1:-}"
    local computers_json
    computers_json=$(_fetch_computers)

    if [[ -z "$computers_json" ]]; then
        printf '{"labels":[],"totalExecutors":0,"totalBusy":0,"totalIdle":0}\n'
        return 0
    fi

    local labels_json
    if [[ -n "$label_filter" ]]; then
        labels_json=$(jq -cn --arg label "$label_filter" '[$label]')
    else
        labels_json=$(printf '%s\n' "$computers_json" | jq -c '
            [
              .computer[]?.assignedLabels[]?.name?
              | select(type == "string" and length > 0)
            ]
            | unique
        ')
    fi

    local labels_output='[]'
    local label_name
    while IFS= read -r label_name; do
        [[ -n "$label_name" ]] || continue

        local label_info
        label_info=$(_fetch_label_info "$label_name")
        if [[ -z "$label_info" ]]; then
            label_info='{}'
        fi

        local label_entry
        label_entry=$(jq -cn \
            --argjson computers "$computers_json" \
            --argjson labelInfo "$label_info" \
            --arg label "$label_name" '
            def label_nodes:
              [
                $computers.computer[]?
                | select(any(.assignedLabels[]?.name?; . == $label))
              ];
            def node_busy($node):
              if ($node.offline // false) then
                0
              else
                [ $node.executors[]? | select(.currentExecutable.url? != null) ] | length
              end;
            def node_idle($node):
              (($node.numExecutors // 0) - node_busy($node));

            {
              name: $label,
              totalExecutors: (
                $labelInfo.totalExecutors
                // ([label_nodes[] | (.numExecutors // 0)] | add // 0)
              ),
              busyExecutors: (
                $labelInfo.busyExecutors
                // ([label_nodes[] | node_busy(.)] | add // 0)
              ),
              idleExecutors: (
                $labelInfo.idleExecutors
                // ([label_nodes[] | node_idle(.)] | add // 0)
              ),
              nodes: [
                label_nodes[]
                | {
                    name: (.displayName // .id // "unknown"),
                    executors: (.numExecutors // 0),
                    busyExecutors: node_busy(.),
                    idleExecutors: node_idle(.),
                    online: ((.offline // false) | not),
                    offline: (.offline // false),
                    temporarilyOffline: (.temporarilyOffline // false),
                    runningJobs: (
                      if (.offline // false) then
                        []
                      else
                        [.executors[]?.currentExecutable.url? | select(. != null)]
                      end
                    )
                  }
              ]
            }
        ')

        labels_output=$(jq -cn \
            --argjson labels "$labels_output" \
            --argjson entry "$label_entry" \
            '$labels + [$entry]')
    done < <(printf '%s\n' "$labels_json" | jq -r '.[]?')

    local totals_json
    if [[ -n "$label_filter" ]]; then
        totals_json=$(jq -cn --argjson labels "$labels_output" '
            {
              totalExecutors: ([ $labels[]?.totalExecutors ] | add // 0),
              totalBusy: ([ $labels[]?.busyExecutors ] | add // 0),
              totalIdle: ([ $labels[]?.idleExecutors ] | add // 0)
            }
        ')
    else
        totals_json=$(printf '%s\n' "$computers_json" | jq -c '
            {
              totalExecutors: ([ .computer[]? | (.numExecutors // 0) ] | add // 0),
              totalBusy: (
                [
                  .computer[]?
                  | if (.offline // false) then
                      0
                    else
                      [ .executors[]? | select(.currentExecutable.url? != null) ] | length
                    end
                ]
                | add // 0
              )
            }
            | .totalIdle = (.totalExecutors - .totalBusy)
        ')
    fi

    jq -cn \
        --argjson labels "$labels_output" \
        --argjson totals "$totals_json" '
        {
          labels: ($labels | sort_by(.name)),
          totalExecutors: ($totals.totalExecutors // 0),
          totalBusy: ($totals.totalBusy // 0),
          totalIdle: ($totals.totalIdle // 0)
        }
    '
}

_agents_pluralize() {
    local count="$1"
    local singular="$2"
    local plural="${3:-${singular}s}"

    if [[ "$count" == "1" ]]; then
        printf '%s %s' "$count" "$singular"
    else
        printf '%s %s' "$count" "$plural"
    fi
}

_render_agents_human() {
    local agents_json="$1"
    local label_count
    label_count=$(printf '%s\n' "$agents_json" | jq -r '.labels | length')

    if [[ "$label_count" -eq 0 ]]; then
        if [[ -n "$AGENTS_LABEL" ]]; then
            echo "No nodes found for label: ${AGENTS_LABEL}"
        else
            echo "No nodes found"
        fi
        return 0
    fi

    local first_label=true
    local label_payload
    while IFS= read -r label_payload; do
        [[ -n "$label_payload" ]] || continue

        if [[ "$first_label" != "true" ]]; then
            echo ""
        fi
        first_label=false

        local label_name node_count total busy idle
        label_name=$(printf '%s' "$label_payload" | base64 --decode | jq -r '.name')
        node_count=$(printf '%s' "$label_payload" | base64 --decode | jq -r '.nodes | length')
        total=$(printf '%s' "$label_payload" | base64 --decode | jq -r '.totalExecutors')
        busy=$(printf '%s' "$label_payload" | base64 --decode | jq -r '.busyExecutors')
        idle=$(printf '%s' "$label_payload" | base64 --decode | jq -r '.idleExecutors')

        echo "Label: ${label_name}"
        echo "  Nodes: ${node_count}"
        echo "  Executors: ${total} total, ${busy} busy, ${idle} idle"
        echo "  Node details:"

        local node_payload
        while IFS= read -r node_payload; do
            [[ -n "$node_payload" ]] || continue
            local node_json node_name node_executors node_busy node_status
            node_json=$(printf '%s' "$node_payload" | base64 --decode)
            node_name=$(printf '%s\n' "$node_json" | jq -r '.name')
            node_executors=$(printf '%s\n' "$node_json" | jq -r '.executors')
            node_busy=$(printf '%s\n' "$node_json" | jq -r '.busyExecutors')
            node_status=$(printf '%s\n' "$node_json" | jq -r 'if .offline then "offline" else "online" end')

            printf '    %s  %s  %s busy  %s\n' \
                "$node_name" \
                "$(_agents_pluralize "$node_executors" "executor")" \
                "$node_busy" \
                "$node_status"

            if [[ "$AGENTS_VERBOSE" == "true" ]]; then
                local job_url
                while IFS= read -r job_url; do
                    [[ -n "$job_url" ]] || continue
                    printf '      Job: %s\n' "$job_url"
                done < <(printf '%s\n' "$node_json" | jq -r '.runningJobs[]?')
            fi
        done < <(printf '%s\n' "$label_payload" | base64 --decode | jq -r '.nodes[] | @base64')
    done < <(printf '%s\n' "$agents_json" | jq -r '.labels[] | @base64')
}

_render_agents_json() {
    local agents_json="$1"
    printf '%s\n' "$agents_json" | jq '.'
}

cmd_agents() {
    _parse_agents_options "$@"

    if ! validate_dependencies; then
        bg_log_error "Cannot inspect Jenkins agents - missing dependencies (jq, curl)"
        bg_log_essential "Suggestion: Install jq and curl, then retry"
        return 1
    fi

    if ! validate_environment; then
        bg_log_error "Cannot inspect Jenkins agents - environment not configured"
        bg_log_essential "Suggestion: Set JENKINS_URL, JENKINS_USER_ID, and JENKINS_API_TOKEN"
        return 1
    fi

    bg_log_info "Verifying Jenkins connectivity..."
    if ! verify_jenkins_connection; then
        bg_log_error "Cannot inspect Jenkins agents - cannot connect to Jenkins"
        bg_log_essential "Suggestion: Check JENKINS_URL and credentials"
        return 1
    fi

    local agents_json
    agents_json=$(_build_agents_data "$AGENTS_LABEL")

    if [[ "$AGENTS_JSON" == "true" ]]; then
        _render_agents_json "$agents_json"
    else
        _render_agents_human "$agents_json"
    fi
}
