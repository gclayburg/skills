## Ralph-Loop SPEC Workflow Integration

- **Date:** `2026-03-12T10:00:00-06:00`
- **References:** `none`
- **Supersedes:** `none`
- **State:** `IMPLEMENTED`

## Problem

When `implement-spec.sh --ralph-loop` implements a multi-chunk plan, each chunk's codex
session receives a prompt focused only on chunk mechanics (pick one, implement, push, mark
done, count remaining). The agent never receives instructions to follow the SPEC workflow
defined in `specs/CLAUDE.md` — it doesn't run tests before starting, doesn't know per-chunk
workflow expectations, and no finalize step exists to handle final-only workflow tasks
(CHANGELOG, README, spec state, reference file moves, SKILL.md updates).

In contrast, single-spec implementation (`implement-spec.sh spec.md`) tells the agent to
"implement the DRAFT spec," and the spec's embedded `## SPEC workflow` section directs the
agent to `specs/CLAUDE.md` where all rules are defined.

### Additional Issues

1. **Plan file location**: `createchunks.sh` derives the plan path from the spec path, so
   specs in `specs/todo/` produce plans in `specs/todo/`. Plans are ready-to-implement
   artifacts and should live in `specs/`, not `specs/todo/`.

2. **No chunk identification in commits**: Commit messages don't identify which chunk was
   implemented, making git history hard to correlate with the plan.

3. **No knowledge sharing between chunks**: The finalize step needs to know what all chunks
   did to write accurate CHANGELOG/README entries, but there is no mechanism for chunks to
   record what they accomplished.

## Specification

### 1. Plan files output to `specs/` directory

`createchunks.sh` must place the generated `*-plan.md` file in the `specs/` directory,
regardless of where the source spec file is located.

### 2. Plan file structure enhancements

#### 2a. Implementation Log subsection

The chunk template (`chunk_template.md`) and `taskcreator.md` must require each chunk detail
to include an `#### Implementation Log` subsection, initially empty. The implementing agent
fills this in after completing the chunk with a brief summary of what was done (files
changed, key decisions, anything the finalize step needs to know).

#### 2b. SPEC Workflow section in plans

Each generated plan must include a `## SPEC Workflow` section that embeds the per-chunk and
finalize workflow rules. This section tells agents exactly what to do without requiring them
to discover the rules by navigating to `specs/CLAUDE.md`.

Content of the SPEC workflow section:

```markdown
## SPEC Workflow

### Per-Chunk Workflow (every chunk must follow these steps)

1. **Run all unit tests** before starting. Do not proceed if tests are failing.
   - Test runner: `jbuildmon/test/bats/bin/bats jbuildmon/test/` (do NOT use any bats from `$PATH`)
2. **Implement the chunk** as described in its Implementation Details section.
3. **Write or update unit tests** as described in the chunk's Test Plan section.
4. **Run all unit tests** and confirm they pass (both new and existing).
5. **Fill in the `#### Implementation Log`** for the chunk you implemented — summarize files
   changed, key decisions, and anything notable.
6. **Commit and push** using `buildgit push jenkins` with a commit message that includes the
   chunk number (e.g., `"chunk 3/5: implement stage-level test fetching"`).
7. **Verify** the Jenkins CI build succeeds with no test failures. If it fails, fix and push again.

### Finalize Workflow (after ALL chunks are complete)

After all chunks have been implemented, a finalize step runs to complete the remaining
SPEC workflow tasks. The finalize agent reads the entire plan file (including all
Implementation Log entries) and performs:

1. **Update `CHANGELOG.md`** (at the repository root).
2. **Update `README.md`** (at the repository root) if CLI options or usage changed.
3. **Update `jbuildmon/skill/buildgit/SKILL.md`** if the changes affect the buildgit skill.
4. **Update `jbuildmon/skill/buildgit/references/reference.md`** if output format or
   available options changed.
5. **Update the spec file:** Change its `State:` field to `IMPLEMENTED` and add it to the
   spec index in `specs/README.md`.
6. **Handle referenced files:** If the spec lists files in its `References:` header, move
   those files to `specs/done-reports/` and update the reference paths in the spec.
7. **Update `CLAUDE.md` AND `README.md`** (at the repository root) if the output of
   `buildgit --help` changes in any way.
8. **Commit and push** using `buildgit push jenkins` and verify CI passes.
```

### 3. `implement-spec.sh` ralph-loop prompt enhancement

The `DEFAULT_RALPH_PROMPT` must include explicit per-chunk workflow steps instead of
relying on the agent to discover them. Specifically:

- Run all tests before implementing
- Include chunk number in commit messages (format: `"chunk N/M: <brief description>"`)
- Fill in the `#### Implementation Log` after completing the chunk
- Reference `specs/CLAUDE.md` for testing conventions (bats runner path, parallel jobs, etc.)

### 4. `implement-spec.sh` finalize step

After the ralph-loop completes all chunks successfully, `implement-spec.sh` must
automatically run one additional codex session (the "finalize step") that:

- Reads the plan file (which now contains all Implementation Log entries)
- Executes the Finalize Workflow from the plan's `## SPEC Workflow` section
- Pushes changes and verifies CI one final time

### 5. `specs/CLAUDE.md` clarification

Add a section clarifying that the Implementation Workflow has two tiers when using
multi-chunk plans:

- **Per-chunk workflow**: run tests → implement → test → log → push (handled by each chunk)
- **Finalize workflow**: docs, metadata, state changes (handled once after all chunks)

Single-spec implementation continues to do everything in one pass as before.

### 6. `taskcreator.md` updates

Add requirements:
- Each chunk detail must include `#### Implementation Log` (initially empty)
- Plans must include the `## SPEC Workflow` section with both per-chunk and finalize rules
- Plans must explicitly reference the parent spec file path

## Test Strategy

These changes are to workflow tooling (shell scripts and markdown templates), not to
buildgit functionality. Testing is manual:

- Run `createchunks.sh` on a spec in `specs/todo/` and verify the plan is created in `specs/`
- Run `implement-spec.sh --ralph-loop` on a plan with the new structure and verify:
  - Each chunk's codex session follows per-chunk workflow
  - Commit messages include chunk numbers
  - Implementation Logs are filled in
  - Finalize step runs after all chunks complete
  - CI passes after finalize push

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
