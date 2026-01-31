#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <plan-file>"
    exit 1
fi
if [[ "$1" == -* ]]; then
    echo "Usage: $0 <plan-file>"
    exit 1
fi

PLAN_FILE="$1"
SPECS_PLAN_FILE="specs/$(basename "$PLAN_FILE")"
if [ ! -f "$SPECS_PLAN_FILE" ]; then
    echo "Error: Plan file '$SPECS_PLAN_FILE' does not exist in the specs/ directory."
    exit 2
fi

# Ensure that the plan file uses the "*-plan.md" naming convention
if [[ ! "$PLAN_FILE" =~ -plan\.md$ ]]; then
    echo "Error: PLAN_FILE must be named according to the *-plan.md convention."
    exit 1
fi

PROMPT="study $PLAN_FILE .
use your judgement to pick the highest priority task or chunk and build that one chunk.
Only build one chunk.
When finished, mark the chunk as completed in $PLAN_FILE and report how many (n) non-completed chunks remain in $PLAN_FILE.  The final line of your output should only this text: <REMAINING>n</REMAINING>."

#CMD="sherlock claude --dangerously-skip-permissions '$PROMPT'"
CMD="claude --dangerously-skip-permissions '$PROMPT'"
#CMD="sherlock claude '$PROMPT'"

echo "$CMD"
eval "$CMD"
