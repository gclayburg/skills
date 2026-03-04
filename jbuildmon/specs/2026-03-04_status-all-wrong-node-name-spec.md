## Fix incorrect and truncated agent names in stage display

- **Date:** `2026-03-04T14:47:49-0700`
- **References:** `specs/done-reports/status-all-wrong-node-name.md`
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## Background

When running `buildgit status -f` (or any monitoring/snapshot mode that shows stages), all stages display the same agent name (e.g. `agent6`), even when parallel branches are running on different agents (`agent7`, `agent8`, etc.). Additionally, the agent name is truncated at the first space — `agent6 guthrie` becomes just `agent6`.

Example of current broken output:
```
[14:29:01] ℹ   Stage: [agent6        ] Build (4s)
[14:29:01] ℹ   Stage:   ║3 [agent6        ] Unit Tests C (<1s)
[14:30:15] ℹ   Stage:   ║1 [agent6        ] Unit Tests A (<1s)
[14:30:15] ℹ   Stage:   ║2 [agent6        ] Unit Tests B (1m 14s)
[14:30:15] ℹ   Stage: [agent6        ] Unit Tests (1m 14s)
[14:31:19] ℹ   Stage:   ║4 [agent6        ] Unit Tests D (2m 16s)
```

Jenkins UI shows Unit Tests A-D running on `agent7 guthrie`, `agent8_sixcore`, etc. — not `agent6`.

## Root Cause Analysis

### Problem 1: All stages share one agent name

In `_get_nested_stages()` (buildgit lines ~3613-3619), one console output is fetched per build and a single agent is extracted:

```bash
console_output=$(get_console_output "$job_name" "$build_number" 2>/dev/null) || true
agent=$(_extract_agent_name "$console_output")
```

Every stage object in the subsequent loop uses `--arg agent "$agent"` — the same value for all stages, regardless of which agent actually ran that stage.

### Problem 2: Only the first "Running on" line is matched

`_extract_running_agent_from_console()` uses `grep -m1 "Running on "` which captures only the first occurrence. The console output actually contains multiple "Running on" lines — one per `node {}` block in the Jenkinsfile:

```
[Pipeline] { (Build)
[Pipeline] node
Running on agent6 guthrie in /home/jenkins/workspace/ralph1_main
...
[Pipeline] { (Unit Tests C)
...
Running on agent8_sixcore in /home/jenkins/workspace/ralph1_main
Running on agent7 guthrie in /home/jenkins/workspace/ralph1_main
Running on agent8_sixcore in /home/jenkins/workspace/ralph1_main@2
Running on agent7 guthrie in /home/jenkins/workspace/ralph1_main@2
...
[Pipeline] { (Deploy)
Running on agent7 guthrie in /home/jenkins/workspace/ralph1_main
```

### Problem 3: Agent name truncated at first space

The sed regex `([^[:space:]]+)` captures only the first word. The Jenkins console format is:
```
Running on <full-agent-name> in <workspace-path>
```
Agent names can contain spaces (e.g. `agent6 guthrie`). The regex stops at the first space, producing `agent6` instead of `agent6 guthrie`.

### Why `execNode` from wfapi cannot be used

The Jenkins `wfapi/describe` endpoint includes an `execNode` field per stage, but **it is always empty** (`""`) on this Jenkins installation. The per-stage `wfapi/log` endpoints also do not contain "Running on" lines — those only appear in the top-level console text. Console parsing is the only viable approach.

## Specification

### 1. Fix agent name extraction regex

In `_extract_running_agent_from_console()`, change the sed regex to capture everything between `"Running on "` and `" in /"` (the `in` before the workspace path):

**Current:**
```bash
sed -E 's/.*Running on[[:space:]]+([^[:space:]]+).*/\1/'
```

**Fixed:**
```bash
sed -E 's/.*Running on[[:space:]]+(.+)[[:space:]]+in[[:space:]]+\/.*/\1/'
```

This captures `agent6 guthrie`, `agent8_sixcore`, etc. — the full agent display name as shown in Jenkins.

### 2. Build a stage-to-agent mapping from the console text

Add a new function `_build_stage_agent_map()` that parses the full console text and builds a mapping from stage name to agent name.

The Jenkins console text follows a predictable pattern:
```
[Pipeline] { (<StageName>)
...
[Pipeline] node
Running on <agent-name> in <workspace-path>
```

The function should:
1. Scan the console text line by line
2. Track the current stage name from `[Pipeline] { (<name>)` lines
3. When a `Running on` line is encountered, associate the extracted agent name with the current stage
4. Return the mapping as a series of `stagename=agentname` lines (or a format parseable by the caller)

For parallel branches, multiple `[Pipeline] { (<name>)` lines may appear before their corresponding `Running on` lines. The mapping must handle this by associating each `Running on` with the most recent unmatched stage.

### 3. Use per-stage agent names in `_get_nested_stages()`

Replace the current single-agent-for-all-stages approach:

**Current flow:**
1. Fetch console once → extract one agent → apply to all stages

**New flow:**
1. Fetch console once → build stage-to-agent map
2. For each stage in the wfapi response, look up its agent name from the map
3. If no mapping found for a stage (e.g. wrapper stages that don't allocate a node), use empty string

### 4. Update the Build Info header agent

The `_parse_build_metadata()` / `display_build_metadata()` code that shows the Build Info header should use the first "Running on" agent from the console (the orchestrator node). This is the existing behavior and remains correct for the header. Just fix the name truncation using the updated regex from section 1.

### 5. Display formatting

The `_format_agent_prefix()` function currently truncates to 14 characters. Keep this width limit but apply it to the full agent name. Examples:

| Full name | Displayed as |
|-----------|-------------|
| `agent6 guthrie` | `[agent6 guthri]` (14 chars, truncated) |
| `agent8_sixcore` | `[agent8_sixcor]` (14 chars, truncated) |
| `agent7` | `[agent7       ]` (padded) |

### 6. Consistency across output modes

The per-stage agent name fix must apply to:
- **Monitoring mode** (`push`, `build`, `status -f`): each stage line shows its own agent
- **Snapshot mode** (`status`, `status --all`): stage display uses correct per-stage agents
- **JSON mode** (`status --json`): if agent names are included in JSON output, they must reflect per-stage values

### 7. Fallback behavior

If the console text cannot be parsed or a stage has no matching "Running on" line:
- Use empty string for that stage's agent (no `[unknown]` placeholder)
- The Build Info header falls back to empty (no `Agent:` line displayed), same as current behavior when console is unavailable

## Test Strategy

### Unit tests

1. **Full agent name extraction**: Test `_extract_running_agent_from_console` with `"Running on agent6 guthrie in /home/jenkins/..."` → returns `"agent6 guthrie"`.
2. **Single-word agent name**: Test with `"Running on agent8_sixcore in /home/..."` → returns `"agent8_sixcore"`.
3. **Stage-to-agent mapping**: Provide a multi-stage console text with multiple "Running on" lines. Verify each stage maps to the correct agent.
4. **Parallel stage mapping**: Provide console text where parallel branches appear with interleaved `[Pipeline] { (Unit Tests A)` ... `Running on agent7 ...` patterns. Verify each parallel branch gets its own agent.
5. **Missing agent for a stage**: A stage that doesn't allocate a node (wrapper stage) should have no agent.
6. **No "Running on" in console**: Empty console or console with no "Running on" → all agents empty, no crash.
7. **Build Info header**: Verify the header `Agent:` line shows the full first agent name.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
