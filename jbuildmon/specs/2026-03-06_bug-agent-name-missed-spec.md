## Fix empty agent name on wrapper stages in --threads mode

- **Date:** `2026-03-06T10:30:00-0700`
- **References:** `specs/done-reports/bug-agent-name-missed.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

When using `--threads` mode to monitor an orchestrator pipeline that triggers downstream builds in parallel, wrapper/parent stages sometimes display an empty agent name while their nested downstream stages show the correct agent.

Example output showing the bug:
```
  [agent8_sixcore] Build Handle->Build [================>   ] 86% 11s / ~13s
  [agent8_sixcore] Build Handle [=>                  ] 12% 28s / ~3m 54s
  [agent7 guthrie] Build SignalBoot->... [==>                 ] 19% 11s / ~1m 1s
  [              ] Build SignalBoot [=>                  ] 14% 29s / ~3m 26s
```

`Build SignalBoot` (the wrapper stage) shows an empty agent name `[              ]`, while its downstream stages correctly show `[agent7 guthrie]`. Meanwhile `Build Handle` (an identical wrapper stage in the same parallel block) shows `[agent8_sixcore]` — which is the downstream agent, not the orchestrator agent.

Both wrapper stages should display the orchestrator pipeline's agent (the agent running the Jenkinsfile), since the wrapper stage itself runs on the orchestrator — it just waits for the downstream build to complete.

## Pipeline Structure

The orchestrator pipeline (`phandlemono-IT`) declares a single pipeline-level Docker agent:
```groovy
agent {
    docker {
        image 'registry:5000/handle-electron-builder:latest'
        label 'sixcore'
    }
}
```

Under `Trigger Component Builds`, two parallel branches (`Build Handle` and `Build SignalBoot`) each call `build job: '...'` to trigger downstream builds on separate agents. The wrapper stages themselves do not allocate new nodes — they run on the orchestrator's agent.

## Root Cause Analysis

The `_get_follow_active_stages()` function in `follow_progress_core.sh` (line 150) assembles active stage data for `--threads` rendering:

1. It calls `_get_nested_stages()` which returns all stages (including downstream) with agent names. For wrapper stages, `_get_nested_stages()` falls back to `pipeline_scope_agent` (the orchestrator's pre-stage `Running on` agent) when no per-stage agent is found in `_build_stage_agent_map()`.

2. It then iterates `base_stages_json` looking for parallel wrappers and their branches. For each branch, it checks whether the branch is already present as `IN_PROGRESS` in the result from step 1. If not, it creates a synthetic entry with agent looked up from `stage_agent_map`.

3. **The bug**: The `stage_agent_map` (built from the orchestrator's console via `_build_stage_agent_map()`) has **no entries** for `Build Handle` or `Build SignalBoot` because these stages don't allocate their own nodes — there is no `Running on` line in the orchestrator console for them. Unlike `_get_nested_stages()`, the synthetic entry path in `_get_follow_active_stages()` does **not** fall back to `pipeline_scope_agent`. It uses the raw `stage_agent_map` lookup result, which is empty string.

4. **Why `Build Handle` sometimes gets an agent but `Build SignalBoot` doesn't**: This depends on which code path provides the stage entry. If the branch is `IN_PROGRESS` in `nested_stages_json` (from `_get_nested_stages()`), it keeps the `pipeline_scope_agent` fallback. If a race condition or stale-branch logic causes the synthetic path to be taken instead, the agent is empty. The two branches can take different paths depending on timing — wfapi poll timing, downstream build start order, and the stale terminal branch heuristic all influence which path is taken.

5. **Secondary issue**: When `Build Handle` does get an agent via the synthetic path, it shows the downstream agent (`agent8_sixcore`) rather than the orchestrator agent, because `_build_stage_agent_map()` may pick up a `Running on` line from the orchestrator console that was associated with a different stage. The correct behavior is to always show the orchestrator agent for wrapper stages.

### Code locations

| Location | Role |
|----------|------|
| `follow_progress_core.sh:150` `_get_follow_active_stages()` | Assembles active stages for threads; synthetic branch entry lacks `pipeline_scope_agent` fallback |
| `follow_progress_core.sh:252` | Branch agent lookup from `stage_agent_map` with no fallback |
| `follow_progress_core.sh:453` `_render_follow_thread_progress_line()` | Reads `.agent` from stage JSON; empty string `""` bypasses jq `//` fallback |
| `json_output.sh:647-651` `_get_nested_stages()` | Has correct `pipeline_scope_agent` fallback (not replicated in `_get_follow_active_stages`) |

## Specification

### 1. Add `pipeline_scope_agent` fallback in `_get_follow_active_stages()`

After building `stage_agent_map` from the console output (`follow_progress_core.sh:169-172`), also extract `pipeline_scope_agent` using `_extract_pre_stage_agent_from_console()`:

```bash
local pipeline_scope_agent=""
if [[ -n "$console_output" ]]; then
    pipeline_scope_agent=$(_extract_pre_stage_agent_from_console "$console_output" 2>/dev/null) || pipeline_scope_agent=""
fi
```

### 2. Apply fallback when resolving branch agents

When looking up the branch agent from `stage_agent_map` (`follow_progress_core.sh:252`), fall back to `pipeline_scope_agent` if the map returns empty:

**Current:**
```bash
branch_agent=$(echo "$stage_agent_map" | jq -r --arg n "$branch_name" '.[$n] // empty' 2>/dev/null) || branch_agent=""
```

**Fixed:**
```bash
branch_agent=$(echo "$stage_agent_map" | jq -r --arg n "$branch_name" '.[$n] // empty' 2>/dev/null) || branch_agent=""
if [[ -z "$branch_agent" && -n "$pipeline_scope_agent" ]]; then
    branch_agent="$pipeline_scope_agent"
fi
```

### 3. Ensure nested_stages_json entries also have the fallback

When `_get_follow_active_stages()` returns entries from `nested_stages_json` (the `branch_present == true` path), those entries already have the correct agent from `_get_nested_stages()` which applies `pipeline_scope_agent`. No change needed on this path — just verify consistency.

### 4. Handle empty agent in renderer

In `_render_follow_thread_progress_line()` (`follow_progress_core.sh:461`), the jq expression `.agent // .execNode // .node // "unknown"` does not catch empty strings. Add a bash-level fallback so empty agent displays as empty (matching current snapshot mode behavior where empty agents show `[              ]`):

No change needed here — empty agent producing blank brackets is acceptable for stages that genuinely have no agent. The fix in sections 1-2 ensures wrapper stages always resolve to the orchestrator agent.

### 5. Consistency across both code paths

After this fix, wrapper stages in `--threads` mode will always show the orchestrator pipeline's agent (the node allocated before the first named stage). This is consistent with how `_get_nested_stages()` handles the same stages in snapshot/monitoring stage log output.

## Test Strategy

### Unit tests

1. **Wrapper stage gets orchestrator agent**: Mock an orchestrator build with a pipeline-level agent and parallel branches that trigger downstream builds. Verify that the wrapper stage entries in `_get_follow_active_stages()` output have the orchestrator agent, not empty string.

2. **Both parallel branches get agents**: Mock two parallel branches (`Build Handle`, `Build SignalBoot`) under the same wrapper. Verify both have non-empty agent names in the active stages output.

3. **Downstream stages keep their own agents**: Verify that nested downstream stages (e.g. `Build SignalBoot->System Diagnostics`) still show the downstream build's agent, not the orchestrator's.

4. **No console output fallback**: When console output is unavailable, verify wrapper stages have empty agent (graceful degradation, no crash).

5. **No pipeline-scope agent**: When the console has no `Running on` line before the first stage (unusual but possible), verify wrapper stages have empty agent rather than crashing.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
