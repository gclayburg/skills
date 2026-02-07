#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <todo-file>"
    exit 1
fi

TODO_FILE="$1"

# Resolve the full path to the todo file (relative or absolute)
TODO_PATH="$(cd "$(dirname "$TODO_FILE")" 2>/dev/null && pwd)/$(basename "$TODO_FILE")"
if [ ! -f "$TODO_PATH" ]; then
    echo "Error: Todo file '$TODO_FILE' does not exist."
    exit 2
fi

# Ensure ROOT_DIR is set to the root of the git repo
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT_DIR" ] || [ ! -d "$ROOT_DIR/.git" ]; then
    echo "Error: Could not determine the root of the git repository."
    exit 3
fi

# Verify the file is inside specs/todo/
TODO_DIR="$ROOT_DIR/jbuildmon/specs/todo"
case "$TODO_PATH" in
    "$TODO_DIR"/*)
        ;;
    *)
        echo "Error: '$TODO_FILE' is not inside specs/todo/."
        echo "Expected path under: $TODO_DIR"
        exit 4
        ;;
esac

CMD="docker sandbox run claude $ROOT_DIR -- 'Implement all the todo items described in jbuildmon/$TODO_FILE. Follow the rules in jbuildmon/specs/todo/README.md.'"

echo "$CMD"
eval "$CMD"
