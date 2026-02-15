# Specs

Individual `*-spec.md` files are treated as the specification for each feature—they define what the feature is and what it must do. These specification files are the authoritative ("canonical") source of requirements for their parts of the application.

- All spec files that are created from other raw report documents should reference those documents in the title header of the spec
- When writing a new spec, review the existing specs in the specs/ directory and identify any that are clearly superseded by your new specification. List only the directly superseded (first-level) specs.

## Creating a new DRAFT spec
- Draft specs are created from raw data, a raw bug report, or a any text file such as .md.  All raw data files need to be listed as references in the spec.
- make sure to read all files matching the `*-spec.md` pattern in this directory.  Newer specs are more important than older ones.
- existing specs are indexed in `./README.md`
- newly created specs will start in the DRAFT state.
- DRAFT spec filename is based on the raw file name and the date (YYYY-MM-DD America/Denver TZ) draft created, e.g. `featurereport74.md` -> `./specs/2026-02-15_featurereport74-spec.md`

**Specification template (include at top of each spec):**
```
## Title

- **Date:** `<ISO 8601 format with seconds, America/Denver timezone>`
- **References:** list of `<other-raw-report-path.md>` or `<none>`
- **Supersedes:** list of `<other-spec-file.md>`
- **State:** one of these valid values: `DRAFT`, `IMPLEMENTED`, `VALIDATED`
```

- before creating a DRAFT spec, you must read all the relevant background material and then ask questions about anything that needs clarification
- if the raw issue is a bug or something broken, perform a root cause analysis and include that in the spec

## Implementation Workflow for Specs and Bug Fixes

When working on a DRAFT spec or bug fix from the `specs/` directory, follow these steps:

- **Confirm all unit tests are currently passing** before starting any implementation work.
- **Update the `CHANGELOG.md` (at the repository root):** If your change introduces new features, alters existing functionality, deprecates or removes features, fixes bugs, or addresses security vulnerabilities, document it here.
- **Update the root `README.md`:** Reflect any changes to CLI options or usage as needed.
- **Update `skill/buildgit/SKILL.md`** if your changes affect the buildgit skill.
- **Ensure all unit tests pass** before declaring the implementation complete.
- **Update the spec file:** Change its `State:` field to `IMPLEMENTED` and add it to the spec and bug index in `specs/README.md`.
- **Handle referenced files:** If the spec lists files in its `References:` header, move those files to `specs/done-reports` and update the reference paths in the spec accordingly.


## Implementation plan files `*-plan.md`
- implementation plan files are optional and only used do break down large specs into manageable chunks for independent execution
- see `taskcreator.md` for details on how plans and chunks are created and implemented
