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

**Specification template (include at top of each DRAFT spec):**
```
## Title

- **Date:** `<ISO 8601 format with seconds, America/Denver timezone>`
- **References:** list of `<other-raw-report-path.md>` or `<none>`
- **Supersedes:** list of `<other-spec-file.md>`
- **State:** one of these valid values: `DRAFT`, `IMPLEMENTED`, `VALIDATED`
```

**Specification template (include verbatim in the DRAFT spec):**
```
## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)
```

- before creating a DRAFT spec, you must read all the relevant background material and then ask questions about anything that needs clarification
- if the raw issue is a bug or something broken, perform a root cause analysis and include that in the spec

## Implementation Workflow for DRAFT->IMPLEMENTED
## Mandatory trigger: "implement DRAFT spec"

When implementing a DRAFT spec or bug fix, follow these steps in order.
If user asks to implement a DRAFT spec:

### Before writing code
- [ ] **Run all unit tests** and confirm they pass. Do not proceed if tests are failing.
  - Test runner: `jbuildmon/test/bats/bin/bats jbuildmon/test/` (do NOT use any bats from `$PATH`)

### Implement the feature or fix
- [ ] **Write the code** as described in the spec's Specification section.
- [ ] **Write or update unit tests** as described in the spec's Test Strategy section.
- [ ] **Run all unit tests** and confirm they pass (both new and existing).

### Update documentation and metadata
- [ ] **Update `CHANGELOG.md`** (at the repository root): document new features, changed behavior, deprecations, removals, bug fixes, or security fixes.
- [ ] **Update `README.md`** (at the repository root): reflect any changes to CLI options or usage.
- [ ] **Update `jbuildmon/skill/buildgit/SKILL.md`** if the changes affect the buildgit skill.
- [ ] **Update the spec file:** Change its `State:` field to `IMPLEMENTED` and add it to the spec index in `specs/README.md`.
- [ ] **Handle referenced files:** If the spec lists files in its `References:` header, move those files to `specs/done-reports/` and update the reference paths in the spec accordingly.

## Workflow for IMPLEMENTED->VALIDATED

- perform all manual testing to make sure the change does what it claims (human does this)
- mark the State: of the spec to `VALIDATED`

## Implementation plan files `*-plan.md`
- implementation plan files are optional and only used do break down large specs into manageable chunks for independent execution
- see `taskcreator.md` for details on how plans and chunks are created and implemented
