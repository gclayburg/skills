 Here is Claude's plan:
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Plan: Add --once flag to buildgit status -f

 Context

 AI agents using buildgit status -f get stuck indefinitely because follow mode never exits — after the current build finishes, it waits for the
 next build forever. The push and build commands already follow one build and exit, but status -f doesn't have that behavior. We need a way for
 agents to follow a single build to completion and then exit.

 Changes

 1. Add --once option to buildgit script

 File: .agents/skills/buildgit/scripts/buildgit

 - Add STATUS_ONCE_MODE=false to _parse_status_options() (~line 186)
 - Add --once case to the option parser (~line 195)
 - Validate: --once requires -f/--follow (error if used without it)
 - Modify _cmd_status_follow() (~line 910): after the first build completes (monitoring + completion display), check STATUS_ONCE_MODE — if true,
 return the build's exit code instead of continuing the while true loop

 2. Update SKILL.md

 File: .agents/skills/buildgit/SKILL.md

 - Add status -f --once to the commands table: "Follow current build, exit when done"
 - Add a note/section recommending agents use status -f --once instead of status -f to avoid indefinite blocking

 3. Update help text

 File: .agents/skills/buildgit/scripts/buildgit

 - Add --once to the usage text in show_usage() (~line 83)

 Verification

 - Run buildgit status -f --once — should follow the latest build and exit when it completes (exit 0 for SUCCESS, 1 for FAILURE)
 - Run buildgit status --once without -f — should show a usage error
 - Run buildgit status -f — should still loop indefinitely (existing behavior preserved)
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌