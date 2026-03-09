## Customizable format string for --threads stage progress lines

- **Date:** `2026-03-06T11:45:00-0700`
- **References:** `specs/todo/format-stage-display.md`
- **Supersedes:** none
- **State:** `DRAFT`

## Background

The `--threads` flag displays live per-stage progress lines during TTY monitoring. The current format is hardcoded:

```
  [agent8_sixcore] Unit Tests A [=====>              ] 32% 40s / ~2m 7s
  [agent7 guthrie] Unit Tests B [=========>          ] 54% 41s / ~1m 16s
IN_PROGRESS Job ralph1/codex/implement-realtime-timing-fix-spec #25 [===>                ] 24% 52s / ~3m 39s
```

Users want to customize the per-stage progress line format — for example, to hide the progress bar and show only agent and stage, or to change field ordering.

## Specification

### 1. Format string for --threads lines

Add a customizable format string that controls the rendering of each per-stage progress line in `--threads` mode. The format string uses `%`-prefixed placeholders, following the same convention as the existing `--format` option for `--line` mode.

**Important**: The `--threads` placeholders use a completely separate namespace from the `--line` `--format` placeholders. No letter is shared between the two sets. This avoids confusion since they operate in different contexts.

### 2. Placeholders

| Placeholder | Field | Example value | Notes |
|---|---|---|---|
| `%a` | Agent name (raw) | `agent7 guthrie` | Full agent name, no brackets or padding |
| `%S` | Stage name | `Unit Tests B` | Full stage name including `->` nesting |
| `%g` | Progress bar | `[=========>          ]` | Determinate or indeterminate bar |
| `%p` | Percentage | `54%` | Includes `%` suffix; `?` when indeterminate |
| `%e` | Elapsed time | `41s` | Formatted via `format_duration` |
| `%E` | Estimated time | `~1m 16s` | Includes `~` prefix; `~unknown` when indeterminate |
| `%%` | Literal `%` | `%` | |

All placeholders produce **value only** — surrounding text like brackets, spaces, slashes, and tildes are part of the format string, not the placeholder output, with the noted exceptions for `%p` (includes `%` suffix) and `%E` (includes `~` prefix).

### 3. Width specifiers

All placeholders support an optional width specifier between `%` and the letter:

```
%<width><placeholder>
```

- `<width>` is a positive integer specifying the maximum character width.
- Values longer than `<width>` are truncated (right-truncated for text fields).
- Values shorter than `<width>` are left-padded with spaces (right-aligned) by default.
- Prefix with `-` for left-alignment (left-aligned, right-padded): `%-14a`.

Examples:
- `%-14a` — agent name, left-aligned in 14-char field (matches current `_format_agent_prefix` behavior)
- `%30S` — stage name, right-aligned in 30-char field
- `%4p` — percentage, right-aligned in 4-char field

When no width is specified, the value is output at its natural length with no padding.

### 4. Default format string

The default format must reproduce the current hardcoded output exactly:

```
  [%-14a] %S %g %p %e / %E
```

This produces:
```
  [agent8_sixcore] Unit Tests A [=====>              ] 32% 40s / ~2m 7s
```

Note: The 2-space indent, brackets around agent, and all spacing are part of the format string literal text.

### 5. Precedence for format string selection

1. **Argument to `--threads`**: `--threads "<format>"` — highest priority
2. **Environment variable**: `BUILDGIT_THREADS_FORMAT` — used if no argument
3. **Default**: The hardcoded default string — used if neither above is set

### 6. Changes to `--threads` flag parsing

Currently `--threads` is a simple boolean flag. Change it to accept an optional argument:

```
--threads [<format>]    Show live active-stage progress during TTY monitoring
```

- `--threads` alone (no argument) — use env/default format
- `--threads "<format>"` — use the provided format string

The argument is positional (the next shell word after `--threads`). To distinguish a format string from the next flag/subcommand, the parser should treat the next argument as a format string only if it does not start with `-` and is not a recognized subcommand (`status`, `push`, `build`). If ambiguous, the user can quote: `--threads "status"` would be a format string containing the literal word "status" — but this edge case is unlikely in practice since format strings contain `%` placeholders.

### 7. Terminal width handling

The existing terminal-width truncation logic in `_render_follow_thread_progress_line()` currently truncates the stage name to fit within terminal columns. With a custom format string:

- If the rendered line exceeds terminal width, truncate the entire line from the right to fit.
- The `%S` (stage name) placeholder is the preferred truncation target when the format uses the default layout. With custom formats, simple right-truncation of the entire line is sufficient.

### 8. Implementation

Modify `_render_follow_thread_progress_line()` in `follow_progress_core.sh`:

1. Accept the format string (from global variable `_THREADS_FORMAT`).
2. Compute all placeholder values (agent, stage, bar, pct, elapsed, estimate) as currently done.
3. Apply the format string by iterating character-by-character, replacing `%X` sequences with values and applying width specifiers.
4. Truncate the final rendered line to terminal width.

Add a format application function `_apply_threads_format()` that:
1. Takes the format string and all field values as named arguments.
2. Iterates through the format string.
3. For each `%` sequence: parse optional `-` alignment flag, optional width digits, then the placeholder letter.
4. Replace with the formatted value (padded/truncated per width spec).
5. Unknown `%X` sequences pass through unchanged (typos are visible).
6. `%%` produces a literal `%`.

### 9. Help text update

Update `--threads` in `buildgit --help` under Global Options:

```
  --threads [<format>]           Show live active-stage progress during TTY monitoring
```

Add threads format documentation to the help examples section:

```
Threads format placeholders for --threads (TTY monitoring only):
  %a=agent  %S=stage  %g=progress-bar  %p=percent  %e=elapsed  %E=estimate  %%=literal%
  Width: %14a (max 14 chars, right-aligned), %-14a (left-aligned)
  Default: "  [%-14a] %S %g %p %e / %E"
  Env: BUILDGIT_THREADS_FORMAT
```

### 10. Interaction with other features

- **Non-TTY**: `--threads` is silently ignored regardless of format string (existing behavior).
- **`--line` mode**: `--threads` format applies to per-stage lines; the `--line` `--format` applies to the overall build progress line. They are independent.
- **Snapshot commands**: `--threads` has no effect on `status`, `status --all`, `status --json` (existing behavior).

## Test Strategy

### Unit tests

1. **Default format produces current output**: Render a thread progress line with the default format string. Verify it matches the existing hardcoded output exactly.

2. **Custom format string**: Provide `"[%a] %S %p"` as format. Verify output contains only agent, stage name, and percentage with no progress bar.

3. **Width specifier — fixed width left-aligned**: Use `%-14a` for agent. Verify agent is left-aligned and padded to 14 characters.

4. **Width specifier — truncation**: Use `%5a` with agent name `agent7 guthrie`. Verify output is `agent` (truncated to 5 chars).

5. **Width specifier — right-aligned**: Use `%20S` with stage name `Build`. Verify it is right-padded... er, left-padded (right-aligned) to 20 chars.

6. **Literal percent**: Format `"100%% %S"` produces `100% Unit Tests A`.

7. **Unknown placeholder passthrough**: Format `"%S %Z"` outputs the stage name followed by literal `%Z`.

8. **Indeterminate estimate**: When no estimate is available, `%p` outputs `?` and `%E` outputs `~unknown`.

9. **Environment variable precedence**: Set `BUILDGIT_THREADS_FORMAT="[%a] %S"` with no `--threads` argument. Verify format is used.

10. **Argument overrides env**: Set `BUILDGIT_THREADS_FORMAT="[%a] %S"` and `--threads "[%a] %S %g"`. Verify the argument format is used.

11. **Terminal width truncation**: Set terminal width to 40. Verify rendered line is truncated to 40 characters.

12. **Flag parsing**: Verify `--threads` alone sets `THREADS_MODE=true` with default format. Verify `--threads "<fmt>"` sets both mode and format.

### Existing test coverage

All existing tests must continue to pass without modification.

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
