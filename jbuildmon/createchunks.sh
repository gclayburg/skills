#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <plan-file>"
    exit 1
fi

SPEC_FILE="$1"
if [[ ! "$SPEC_FILE" =~ -spec\.md$ ]]; then
    echo "Error: SPEC_FILE must be named according to the *-spec.md convention."
    exit 1
fi
# Verify that SPEC_FILE exists in the specs/ directory
# Resolve the full path to the spec file (relative or absolute)
SPEC_PATH="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
if [ ! -f "$SPEC_PATH" ]; then
    echo "Error: Spec file '$SPEC_PATH' does not exist."
    exit 2
fi
SPECS_DIR=$(dirname "$SPEC_FILE")

# Replace the '-spec.md' suffix in the SPEC_FILE name with '-plan.md' to generate the corresponding implementation plan file name.
PLAN_FILE="${SPEC_FILE/-spec.md/-plan.md}"
if [ -f "$PLAN_FILE" ]; then
    echo "Error: Plan file '$PLAN_FILE' already exists for '$SPEC_FILE'."
    read -p "A plan file already exists for this spec: '$PLAN_FILE'. Do you want to continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 3
    fi
fi
# Ensure ROOT_DIR is set to the root of the git repo, not just current working dir
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT_DIR" ] || [ ! -d "$ROOT_DIR/.git" ]; then
    echo "Error: Could not determine the root of the git repository."
    exit 4
fi

#CMD="sherlock claude -- --dangerously-skip-permissions 'use $SPECS_DIR/taskcreator.md to create an implementation plan for $SPEC_FILE  '"
CMD="docker sandbox run claude $ROOT_DIR -- 'use $SPECS_DIR/taskcreator.md to create an implementation plan for $SPEC_FILE  '"

echo "$CMD"
eval "$CMD"
