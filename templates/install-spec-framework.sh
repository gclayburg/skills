#!/usr/bin/env bash
#
# install-spec-framework.sh — Deploy the spec-driven development framework
# into a target project directory.
#
# Usage: install-spec-framework.sh [--force] <target-directory>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=false

usage() {
    echo "Usage: $(basename "$0") [--force] <target-directory>"
    echo ""
    echo "Deploy the spec-driven development process framework into a project."
    echo ""
    echo "Options:"
    echo "  --force    Overwrite existing files (default: skip)"
    echo "  -h, --help Show this help message"
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

if [[ -z "${TARGET_DIR:-}" ]]; then
    echo "Error: Target directory is required." >&2
    usage 1
fi

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo "Error: Target directory does not exist: ${TARGET_DIR}" >&2
    exit 1
}

# Check if target is a git repo
if ! git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Warning: Target directory is not a git repository: $TARGET_DIR"
fi

# Files to install (relative paths from template root)
TEMPLATE_FILES=(
    "CLAUDE.md"
    "specs/CLAUDE.md"
    "specs/README.md"
    "specs/taskcreator.md"
    "specs/chunk_template.md"
    "specs/todo/README.md"
)

# Install each file
for rel_path in "${TEMPLATE_FILES[@]}"; do
    src="$SCRIPT_DIR/$rel_path"
    dst="$TARGET_DIR/$rel_path"
    dst_dir="$(dirname "$dst")"

    # Create directory if needed
    mkdir -p "$dst_dir"

    if [[ -f "$dst" ]]; then
        if [[ "$FORCE" == true ]]; then
            cp "$src" "$dst"
            echo "overwritten: $rel_path"
        else
            echo "skipped:     $rel_path (already exists)"
        fi
    else
        cp "$src" "$dst"
        echo "created:     $rel_path"
    fi
done

echo ""
echo "Done. Framework installed to: $TARGET_DIR"
