# Todo: Pending Specs and Plans

Items in this directory represent features, enhancements, or bug fixes that have not been implemented yet. When an item is completed, move its file to `specs/` and add it to the Spec and Bug index in `specs/README.md`.

## conventions
- any file in this directory using the pattern *-plan.md or *-spec.md is considered a fleshed out plan or spec that can be implemented.  All other files are considered raw reports or ideas not ready for implementation
- An LLM will generally assist in crafting the *-spec.md or *-plan.md file as necessary.  when complete, the index here in this README.md should be updated

## Index ready to implement

- **needed_tools.md** — New `buildgit` subcommands (`console`, `tests`) identified during debugging of build failures. Prioritized by usefulness during incident triage. (`status <build#>` has been implemented — see `feature-status-job-number-spec.md`)
- **feature-live-active-stages-spec.md** — `--threads` flag for `push`, `build`, `status -f` that shows a live-updating footer of currently active stages with elapsed times during build monitoring. Uses ANSI cursor control for in-place updates; interactive terminals only.

## Index of files not ready to implement

- **features-to-ralph.md** — Future feature ideas: `buildgit log` with per-commit build status, and a `--debug`/`-vv` verbose level for connection diagnostics.


# todo implementation rules

- see `../CLAUDE.md`