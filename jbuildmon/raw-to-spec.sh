#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <raw-file>"
    exit 1
fi
if [[ "$1" == -* ]]; then
    echo "Usage: $0 <raw-file>"
    exit 1
fi

RAW_FILE="$1"

if [ ! -f "$RAW_FILE" ]; then
    echo "Error: File '$RAW_FILE' does not exist."
    exit 2
fi

PROMPT="study specs/README.md and $RAW_FILE .
This information represents a new feature or bug in the system.  Your task is to analyze this and then ask me some questions about it to clarify what is needed.
Make sure to also read and study any existing specs in the specs/ directory, especialy any that are referenced directly in $RAW_FILE or specs/README.md
When this interview process is finished you will be eventually asked to produce a spec file as documented in specs/README.md"

#CMD="sherlock claude --dangerously-skip-permissions '$PROMPT'"
#CMD="claude --dangerously-skip-permissions '$PROMPT'"
#CMD="sherlock claude '$PROMPT'"
CMD="tokentap claude '$PROMPT'"

echo "$CMD"
eval "$CMD"
