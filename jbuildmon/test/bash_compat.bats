#!/usr/bin/env bats

# Static analysis tests to catch bash 4+ features that break on macOS (bash 3.2).
# These run inside the Linux CI sandbox, catching incompatibilities before merge.

load test_helper

# All .sh files under jbuildmon/ that must be macOS-compatible
_collect_sh_files() {
    local repo_root
    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    find "$repo_root" -name '*.sh' -not -path '*/test/bats/*' -not -path '*/node_modules/*' | sort
}

# Filter grep output to exclude the MACOS_COMPAT_REMINDER string literal
# (it mentions bash 4+ features by name as a warning to codex, not as actual usage)
_filter_false_positives() {
    grep -v 'MACOS_COMPAT_REMINDER' || true
}

@test "bash_compat_no_readarray_or_mapfile" {
    local failures=""
    while IFS= read -r file; do
        local hits
        hits=$(grep -n '\breadarray\b\|[^#]*\bmapfile\b' "$file" 2>/dev/null | grep -v '^\s*#' | _filter_false_positives)
        if [[ -n "$hits" ]]; then
            failures="${failures}${file}:
${hits}
"
        fi
    done < <(_collect_sh_files)
    if [[ -n "$failures" ]]; then
        echo "readarray/mapfile found (bash 4+ only, breaks macOS bash 3.2):"
        echo "$failures"
        false
    fi
}

@test "bash_compat_no_associative_arrays" {
    local failures=""
    while IFS= read -r file; do
        local hits
        hits=$(grep -n 'declare[[:space:]]\+-A\b' "$file" 2>/dev/null | grep -v '^\s*#' | _filter_false_positives)
        if [[ -n "$hits" ]]; then
            failures="${failures}${file}:
${hits}
"
        fi
    done < <(_collect_sh_files)
    if [[ -n "$failures" ]]; then
        echo "declare -A found (bash 4+ only, breaks macOS bash 3.2):"
        echo "$failures"
        false
    fi
}

@test "bash_compat_no_case_conversion" {
    local failures=""
    while IFS= read -r file; do
        local hits
        # Match ${var,,} ${var^^} ${var,} ${var^} but not inside comments
        hits=$(grep -n '\${[^}]*[,^][,^]\?}' "$file" 2>/dev/null | grep -v '^\s*#' | _filter_false_positives)
        if [[ -n "$hits" ]]; then
            failures="${failures}${file}:
${hits}
"
        fi
    done < <(_collect_sh_files)
    if [[ -n "$failures" ]]; then
        echo "Case conversion \${var,,}/\${var^^} found (bash 4+ only, breaks macOS bash 3.2):"
        echo "$failures"
        false
    fi
}

@test "bash_compat_no_pipe_stderr" {
    local failures=""
    while IFS= read -r file; do
        local hits
        hits=$(grep -n '|&' "$file" 2>/dev/null | grep -v '^\s*#' | _filter_false_positives)
        if [[ -n "$hits" ]]; then
            failures="${failures}${file}:
${hits}
"
        fi
    done < <(_collect_sh_files)
    if [[ -n "$failures" ]]; then
        echo "|& pipe found (bash 4+ only, breaks macOS bash 3.2). Use 2>&1 | instead:"
        echo "$failures"
        false
    fi
}

@test "bash_compat_no_parameter_transformation" {
    local failures=""
    while IFS= read -r file; do
        local hits
        # Match ${var@Q} ${var@E} ${var@A} etc.
        hits=$(grep -n '\${[^}]*@[QEAPU]}' "$file" 2>/dev/null | grep -v '^\s*#' | _filter_false_positives)
        if [[ -n "$hits" ]]; then
            failures="${failures}${file}:
${hits}
"
        fi
    done < <(_collect_sh_files)
    if [[ -n "$failures" ]]; then
        echo "Parameter transformation \${var@Q} found (bash 4+ only, breaks macOS bash 3.2):"
        echo "$failures"
        false
    fi
}

@test "bash_compat_no_nameref" {
    local failures=""
    while IFS= read -r file; do
        local hits
        hits=$(grep -n 'declare[[:space:]]\+-n\b\|local[[:space:]]\+-n\b' "$file" 2>/dev/null | grep -v '^\s*#' | _filter_false_positives)
        if [[ -n "$hits" ]]; then
            failures="${failures}${file}:
${hits}
"
        fi
    done < <(_collect_sh_files)
    if [[ -n "$failures" ]]; then
        echo "nameref (declare -n / local -n) found (bash 4.3+ only, breaks macOS bash 3.2):"
        echo "$failures"
        false
    fi
}
