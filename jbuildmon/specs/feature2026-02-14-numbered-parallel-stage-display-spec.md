# Numbered Parallel Stage Display and Snapshot/Monitoring Consistency
Date: 2026-02-14T00:45:00-0700
References: specs/done-reports/feature2026-02-14-parallel-stage-numbered-display-raw.md, specs/bug-parallel-stages-display-spec.md, specs/nested-jobs-display-spec.md
Supersedes: none (amends bug-parallel-stages-display-spec.md and nested-jobs-display-spec.md)

## Overview

Parallel stage output currently uses a generic `║` marker that makes it hard to quickly identify which lines belong to which concurrently running branch. Monitoring and snapshot output also differ in ordering for wrapper/parent stages, which reduces readability.

This feature adds numbered parallel track markers in terminal output and aligns stage ordering semantics across monitoring and snapshot modes.

## User Decisions (Clarified Requirements)

1. Parallel numbering is **local per wrapper stage**.
2. A branch keeps the same number for the full duration of that branch execution.
3. Nested parallel branches use path notation with separators (example: `║3.1`).
4. Agent display is fixed-width 14 characters for **all stage lines** (not only parallel lines):
- shorter names padded right with spaces,
- longer names truncated to 14 characters.
5. Wrapper/parent stage line (example `Trigger Component Builds`) prints after all its parallel children complete.
6. Snapshot and monitoring output should be consistent in ordering/format as much as technically possible; any unavoidable timing differences must be documented.
7. In monitoring mode (non-verbose), suppress early in-progress lines such as `(unknown)` for parallel branch summaries; print branch summaries only when terminal.
8. Changes are terminal-display only (no new JSON fields for numbering/path).
9. This is default behavior (no compatibility flag).
10. Wrapper duration remains aggregate wall-clock duration behavior from existing parallel-stage spec.

## Problem Statement

Current output problems:
- Generic `║` marker does not distinguish multiple concurrent branches at a glance.
- Wrapper stage can appear before nested branch output in snapshot view, while monitoring view can differ.
- In-progress branch summaries like `(unknown)` are noisy and can be misleading.
- Agent field width varies, making dense parallel output harder to scan.

## Scope

Applies to terminal stage display for:
- `buildgit build`
- `buildgit push`
- `buildgit status -f`
- `buildgit status`

Not in scope:
- `buildgit status --json` schema changes for numbering/path.

## Display Model

### Parallel Track IDs

- For each parallel wrapper stage, assign child branch IDs in deterministic order starting at `1`.
- Use display prefix `║<id>` for first-level parallel branches.
- For nested parallel under branch `3`, use `║3.1`, `║3.2`, etc.
- Nested downstream stages inherit the branch path marker of their owning branch.

Examples:
- `║1 [agent8_sixcore] Build Handle->...`
- `║2 [agent7        ] Build SignalBoot->...`
- `║3.1 [agent14      ] ...`

### Agent Formatting

- Render agent label as fixed width 14 characters for every stage line.
- Rule:
- if length < 14: right-pad spaces.
- if length > 14: truncate to first 14 characters.
- if unknown/empty: keep existing empty behavior (no fabricated agent name).

### Wrapper Ordering

- For parallel wrappers, defer wrapper line printing until all mapped parallel branches have terminal status.
- Print wrapper after branch nested stages and branch summary lines in both snapshot and monitoring outputs.

## Consistency Requirements

1. Snapshot (`status`) and monitoring (`build/push/status -f`) must use the same ordering strategy and marker formatting for completed stages.
2. If perfect equality is impossible due to polling timing in monitoring mode, differences must be limited to in-progress visibility and explicitly documented in spec/tests.
3. Non-verbose monitoring should only print stages at terminal transitions (no early `(unknown)` branch summary lines).

## Implementation Notes

1. Introduce branch-path metadata in display pipeline (terminal-only) derived from existing parallel wrapper/branch mapping.
2. Preserve existing JSON model unless needed internally; do not expose new JSON fields for numbered display.
3. Ensure numbering assignment is deterministic and stable within a build.
4. Keep wrapper aggregate duration formula unchanged from existing parallel-stage behavior.

## Files Expected to Change

| File | Expected change |
|------|------------------|
| `jbuildmon/skill/buildgit/scripts/lib/jenkins-common.sh` | Stage line formatting for fixed-width agent labels and numbered parallel path markers; wrapper deferred ordering behavior aligned for snapshot + monitoring; suppress non-verbose in-progress parallel summary noise. |
| `jbuildmon/skill/buildgit/scripts/buildgit` | Any wiring needed so snapshot/monitoring paths use the same ordered stage presentation logic. |
| `jbuildmon/test/parallel_stages.bats` | Add/adjust tests for numbered path markers (`║1`, `║2`, `║3.1`), wrapper printed last, and non-verbose suppression of `(unknown)`. |
| `jbuildmon/test/nested_stages.bats` | Add/adjust tests for fixed-width 14-char agent formatting on all stage lines and snapshot/monitoring consistency expectations. |

## Acceptance Criteria

1. Parallel branches under one wrapper display with deterministic local IDs (`║1`, `║2`, ...).
2. Nested parallel branches display path notation (`║3.1`, `║3.2`, ...).
3. Branch IDs remain stable across all printed lines for the branch.
4. Agent display is fixed-width 14 chars on all stage lines.
5. Wrapper line prints after all branch lines in both snapshot and monitoring outputs.
6. Monitoring non-verbose output does not print early `(unknown)` parallel branch summary lines.
7. Snapshot and monitoring output ordering/format are aligned for completed stages; any unavoidable timing differences are documented and covered by tests.
8. `status --json` remains schema-compatible (no numbering fields added).

## Test Strategy

- Unit tests for parallel ID assignment and nested path composition.
- Integration-style tests validating wrapper-last ordering in both snapshot and monitoring code paths.
- Formatting tests for 14-char agent padding/truncation.
- Regression test for suppression of non-verbose `(unknown)` parallel summary lines.
