# Todo: Pending Specs and Plans

Items in this directory represent raw ideas for features, enhancements, or bug fixes that have not been spec'd or planned yet.

## conventions
- This directory is for raw ideas and reports only. Once a spec (`*-spec.md`) or plan (`*-plan.md`) is ready to implement, it should be created in `specs/` (the parent directory), not here.
- All other files are considered raw reports or ideas not ready for implementation
- An LLM will generally assist in crafting the *-spec.md or *-plan.md file as necessary.  when complete, the index here in this README.md should be updated

## Index ready to implement

- **needed_tools.md** — New `buildgit` subcommands (`console`, `tests`) identified during debugging of build failures. Prioritized by usefulness during incident triage. (`status <build#>` has been implemented — see `feature-status-job-number-spec.md`)
- **feature-live-active-stages-spec.md** — `--threads` flag for `push`, `build`, `status -f` that shows a live-updating footer of currently active stages with elapsed times during build monitoring. Uses ANSI cursor control for in-place updates; interactive terminals only.

## Index of files not ready to implement

- **features-to-ralph.md** — Future feature ideas: `buildgit log` with per-commit build status, and a `--debug`/`-vv` verbose level for connection diagnostics.
