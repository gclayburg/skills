#!/usr/bin/env bash

# Correlate JUnit suites to their parent wfapi stages.

_fetch_node_test_results() {
    local job_path="$1"
    local build_number="$2"
    local node_id="$3"

    if [[ -z "$job_path" || -z "$build_number" || -z "$node_id" ]]; then
        echo "[]"
        return 0
    fi

    local response http_code body suites_json
    response=$(jenkins_api_with_status "${job_path}/${build_number}/execution/node/${node_id}/wfapi/testResults" || true)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
        echo "[]"
        return 0
    fi

    case "$http_code" in
        200)
            suites_json=$(echo "$body" | jq -c '
                (.testResult.suites // []) |
                map({
                    name: (.name // ""),
                    tests: ((.cases // []) | length),
                    durationMs: ((((.duration // 0) * 1000) | floor)),
                    failures: ((.cases // []) | map(select(.status == "FAILED")) | length)
                })
            ' 2>/dev/null) || true

            if [[ -z "$suites_json" || "$suites_json" == "null" ]]; then
                echo "[]"
                return 0
            fi

            echo "$suites_json"
            return 0
            ;;
        404)
            echo "[]"
            return 0
            ;;
        *)
            echo "[]"
            return 0
            ;;
    esac
}

fetch_stage_test_suites() {
    local job_name="$1"
    local build_number="$2"
    local job_path
    job_path=$(jenkins_job_path "$job_name")
    if [[ -z "$job_path" ]]; then
        echo "{}"
        return 0
    fi

    local stages_json result_json
    stages_json=$(get_all_stages "$job_name" "$build_number")
    if [[ -z "$stages_json" || "$stages_json" == "[]" ]]; then
        echo "{}"
        return 0
    fi

    result_json="{}"

    while IFS= read -r stage_json; do
        local stage_name node_id suites_json
        stage_name=$(echo "$stage_json" | jq -r '.name // empty')
        node_id=$(echo "$stage_json" | jq -r '.id // empty')

        if [[ -z "$stage_name" || -z "$node_id" ]]; then
            continue
        fi

        suites_json=$(_fetch_node_test_results "$job_path" "$build_number" "$node_id")
        if [[ -z "$suites_json" || "$suites_json" == "[]" ]]; then
            continue
        fi

        result_json=$(jq -c \
            --arg stage_name "$stage_name" \
            --argjson suites "$suites_json" \
            '. + {($stage_name): $suites}' <<<"$result_json")
    done < <(echo "$stages_json" | jq -c '.[]?')

    echo "$result_json"
}
