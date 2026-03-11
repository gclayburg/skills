# chunk-counter — Implementation Plan

**Purpose:** Test plan for validating the `--ralph-loop` workflow. Implements a small
standalone utility `jbuildmon/util/chunk-counter.sh` that reads a `*-plan.md` file and
reports how many chunks are done vs. remaining. Deliberately simple — each chunk is
trivial to implement and produces a verifiable file artifact.

**Created:** 2026-03-10

---

## Contents

- [ ] **Chunk A: Script skeleton**
- [ ] **Chunk B: `count-done` subcommand**
- [ ] **Chunk C: `count-remaining` subcommand**
- [ ] **Chunk D: `summary` subcommand**
- [ ] **Chunk E: Bats tests**

---

## Chunk Detail

---

### Chunk A: Script skeleton

#### Description

Create the `jbuildmon/util/chunk-counter.sh` script with a shebang, `set -euo pipefail`,
a `usage()` function, and a `main()` dispatch stub that prints the usage if no arguments
are given or if an unknown subcommand is passed. The script does nothing useful yet but
establishes the file and is executable.

#### Spec Reference

Self-contained — this plan is the specification.

#### Dependencies

- None

#### Produces

- `jbuildmon/util/chunk-counter.sh`

#### Implementation Details

1. Create `jbuildmon/util/` directory if it doesn't exist.
2. Write `jbuildmon/util/chunk-counter.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   usage() {
       echo "Usage: chunk-counter.sh <subcommand> <plan-file>"
       echo ""
       echo "Subcommands:"
       echo "  count-done       Count completed chunks (lines matching '- [x]')"
       echo "  count-remaining  Count incomplete chunks (lines matching '- [ ]')"
       echo "  summary          Print done/remaining counts and percent complete"
   }

   main() {
       if [[ $# -lt 2 ]]; then
           usage >&2
           exit 1
       fi
       local subcommand="$1"
       local plan_file="$2"
       if [[ ! -f "$plan_file" ]]; then
           echo "Error: file not found: $plan_file" >&2
           exit 1
       fi
       case "$subcommand" in
           count-done)      cmd_count_done      "$plan_file" ;;
           count-remaining) cmd_count_remaining "$plan_file" ;;
           summary)         cmd_summary         "$plan_file" ;;
           *)
               echo "Error: unknown subcommand '$subcommand'" >&2
               usage >&2
               exit 1
               ;;
       esac
   }

   main "$@"
   ```
3. Make the script executable: `chmod +x jbuildmon/util/chunk-counter.sh`.
4. **Verification:** Running `./jbuildmon/util/chunk-counter.sh` with no args prints usage
   and exits non-zero.

#### Test Plan

**Test File:** `jbuildmon/test/chunk_counter.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `no_args_prints_usage` | Running with no args exits non-zero and prints "Usage:" | Chunk A |
| `unknown_subcommand_exits_nonzero` | `chunk-counter.sh badcmd file` exits non-zero | Chunk A |
| `missing_file_exits_nonzero` | `chunk-counter.sh summary /nonexistent` exits non-zero with error | Chunk A |

**Mocking Requirements:** None — no external dependencies.

**Dependencies:** None

---

### Chunk B: `count-done` subcommand

#### Description

Implement `cmd_count_done()` in `chunk-counter.sh`. It counts lines in the plan file
that match the completed-checkbox pattern `- [x]` (case-insensitive) and prints the
integer count to stdout.

#### Spec Reference

Self-contained — this plan is the specification.

#### Dependencies

- Chunk A (`chunk-counter.sh` skeleton must exist)

#### Produces

- Modified `jbuildmon/util/chunk-counter.sh` (adds `cmd_count_done()`)

#### Implementation Details

1. Add `cmd_count_done()` to `chunk-counter.sh` before `main()`:
   ```bash
   cmd_count_done() {
       local plan_file="$1"
       grep -ci '^\- \[x\]' "$plan_file" || echo 0
   }
   ```
   Note: `grep -c` returns exit code 1 when count is 0; `|| echo 0` handles that.
2. **Verification:** Given a plan file with two `- [x]` lines, running
   `chunk-counter.sh count-done <file>` prints `2`.

#### Test Plan

**Test File:** `jbuildmon/test/chunk_counter.bats`

Create fixture file `jbuildmon/test/fixtures/chunk_counter_sample.md` containing:
```
- [x] **Chunk A: Done thing**
- [x] **Chunk B: Also done**
- [ ] **Chunk C: Not done yet**
- [ ] **Chunk D: Still todo**
```

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `count_done_two` | Fixture has 2 done — output is `2` | Chunk B |
| `count_done_zero` | File with no `[x]` lines — output is `0` | Chunk B |
| `count_done_all` | File where all chunks are done — correct count | Chunk B |

**Mocking Requirements:** None

**Dependencies:** Chunk A

---

### Chunk C: `count-remaining` subcommand

#### Description

Implement `cmd_count_remaining()` in `chunk-counter.sh`. It counts lines matching the
incomplete-checkbox pattern `- [ ]` and prints the integer count to stdout.

#### Spec Reference

Self-contained — this plan is the specification.

#### Dependencies

- Chunk A (`chunk-counter.sh` skeleton must exist)

#### Produces

- Modified `jbuildmon/util/chunk-counter.sh` (adds `cmd_count_remaining()`)

#### Implementation Details

1. Add `cmd_count_remaining()` to `chunk-counter.sh` before `main()`:
   ```bash
   cmd_count_remaining() {
       local plan_file="$1"
       grep -c '^\- \[ \]' "$plan_file" || echo 0
   }
   ```
2. **Verification:** Given the fixture with two `- [ ]` lines, running
   `chunk-counter.sh count-remaining <file>` prints `2`.

#### Test Plan

**Test File:** `jbuildmon/test/chunk_counter.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `count_remaining_two` | Fixture has 2 remaining — output is `2` | Chunk C |
| `count_remaining_zero` | File with no `[ ]` lines — output is `0` | Chunk C |
| `count_done_plus_remaining_equals_total` | Done + remaining = total checkbox lines in fixture | Chunk C |

**Mocking Requirements:** None

**Dependencies:** Chunk A

---

### Chunk D: `summary` subcommand

#### Description

Implement `cmd_summary()` in `chunk-counter.sh`. It calls `cmd_count_done()` and
`cmd_count_remaining()` internally, then prints a human-readable summary line:

```
Done: 2 / 4  (50%)
```

If total is 0 (no checkboxes found), print `Done: 0 / 0  (n/a)`.

#### Spec Reference

Self-contained — this plan is the specification.

#### Dependencies

- Chunk B (`cmd_count_done()` must exist)
- Chunk C (`cmd_count_remaining()` must exist)

#### Produces

- Modified `jbuildmon/util/chunk-counter.sh` (adds `cmd_summary()`)

#### Implementation Details

1. Add `cmd_summary()` to `chunk-counter.sh` before `main()`:
   ```bash
   cmd_summary() {
       local plan_file="$1"
       local done remaining total pct
       done=$(cmd_count_done "$plan_file")
       remaining=$(cmd_count_remaining "$plan_file")
       total=$(( done + remaining ))
       if [[ $total -eq 0 ]]; then
           echo "Done: 0 / 0  (n/a)"
       else
           pct=$(( done * 100 / total ))
           echo "Done: ${done} / ${total}  (${pct}%)"
       fi
   }
   ```
2. **Verification:** On the fixture file (2 done, 2 remaining), output is `Done: 2 / 4  (50%)`.

#### Test Plan

**Test File:** `jbuildmon/test/chunk_counter.bats`

| Test Case | Description | Spec Section |
|-----------|-------------|--------------|
| `summary_half_done` | 2 done, 2 remaining → `Done: 2 / 4  (50%)` | Chunk D |
| `summary_all_done` | All done → `Done: N / N  (100%)` | Chunk D |
| `summary_none_done` | All remaining → `Done: 0 / N  (0%)` | Chunk D |
| `summary_no_checkboxes` | No checkbox lines → `Done: 0 / 0  (n/a)` | Chunk D |

**Mocking Requirements:** None

**Dependencies:** Chunks B, C

---

### Chunk E: Bats tests

#### Description

Write the complete `jbuildmon/test/chunk_counter.bats` test file covering all test cases
from Chunks A–D. Create the fixture file `jbuildmon/test/fixtures/chunk_counter_sample.md`.
Run the full test suite and confirm all tests pass.

#### Spec Reference

Self-contained — this plan is the specification. Test cases defined in Chunks A–D above.

#### Dependencies

- Chunk A (skeleton — tests invoke the script)
- Chunk B (`count-done` — tested here)
- Chunk C (`count-remaining` — tested here)
- Chunk D (`summary` — tested here)

> **WARNING for ralph-loop:** Do not implement Chunk E until Chunks A, B, C, and D are
> all complete. The tests call all subcommands; any missing implementation will cause
> test failures.

#### Produces

- `jbuildmon/test/chunk_counter.bats`
- `jbuildmon/test/fixtures/chunk_counter_sample.md`

#### Implementation Details

1. **Create fixture** `jbuildmon/test/fixtures/chunk_counter_sample.md`:
   ```markdown
   - [x] **Chunk A: Done thing**
   - [x] **Chunk B: Also done**
   - [ ] **Chunk C: Not done yet**
   - [ ] **Chunk D: Still todo**
   ```

2. **Create `jbuildmon/test/chunk_counter.bats`** covering all test cases from Chunks A–D.
   Use `run bash -c "bash jbuildmon/util/chunk-counter.sh <args> 3>&- 2>&1"` pattern.
   Source `test_helper.bash`. Each `@test` must include a comment referencing which
   chunk's spec it comes from.

3. **Run the tests** to confirm all pass:
   ```bash
   jbuildmon/test/bats/bin/bats --jobs 10 jbuildmon/test/chunk_counter.bats
   ```

4. **Run the full test suite** to confirm no regressions:
   ```bash
   jbuildmon/test/bats/bin/bats --jobs 10 jbuildmon/test/
   ```

#### Test Plan

**Test File:** `jbuildmon/test/chunk_counter.bats`

All test cases from Chunks A, B, C, D are consolidated here. See those chunks for the
full table. Total: ~10 test cases.

**Mocking Requirements:** None — the script has no external dependencies.

**Dependencies:** Chunks A, B, C, D
