## Extract Process Framework as Reusable Template

- **Date:** `2026-02-27T23:15:24-0700`
- **References:** none
- **Supersedes:** none
- **State:** `IMPLEMENTED`

## SPEC workflow

1. read `specs/CLAUDE.md` and follow all rules there to implement this DRAFT spec (DRAFT->IMPLEMENTED)

## Summary

This project contains two separable concerns: (1) the jbuildmon/buildgit tool, and (2) a spec-driven development process framework (CLAUDE.md files, specs/CLAUDE.md workflow, taskcreator, chunk_template, etc.). The process framework is valuable and reusable but currently entangled with jbuildmon-specific content.

This spec defines how to extract the generic process files into a `templates/` directory that serves as the single source of truth, plus a bash script to deploy them into any target project.

## Specification

### 1. Template Directory Structure

Create `templates/` at the repository root containing genericized versions of the process framework files:

```
templates/
  CLAUDE.md
  install-spec-framework.sh
  specs/
    CLAUDE.md
    README.md
    taskcreator.md
    chunk_template.md
    todo/
      README.md
```

### 2. Template File Descriptions

#### `templates/CLAUDE.md`

Derived from the root `CLAUDE.md`. Changes:
- Keep the "Agent Instructions (CLAUDE.md / AGENTS.md)" framing and introductory paragraph
- Replace the "Project Overview" section body with a placeholder comment instructing the user to describe their project here
- Keep the "Detailed Specifications" section pointing to `specs/README.md` and `specs/CLAUDE.md`
- Remove all jbuildmon/buildgit/Jenkins content: the buildgit help text block, the "buildgit" section, the "Building on Jenkins CI server" section

#### `templates/specs/CLAUDE.md`

Derived from `jbuildmon/specs/CLAUDE.md`. Changes:
- Remove the jbuildmon-specific test runner path (`jbuildmon/test/bats/bin/bats jbuildmon/test/`). Replace with a generic placeholder comment: `<!-- Replace with your project's test runner command -->`
- Remove `jbuildmon/skill/buildgit/SKILL.md` and `jbuildmon/skill/buildgit/references/reference.md` from the update checklist
- Remove the buildgit-specific update checklist items that reference SKILL.md and reference.md
- Keep the DRAFT/IMPLEMENTED/VALIDATED workflow, spec template, naming conventions, and all other generic process content

#### `templates/specs/README.md`

Derived from `jbuildmon/specs/README.md`. Changes:
- Keep the todo directory section and workflow descriptions
- Remove the entire project-specific spec index entries
- Start with an empty "Spec and Bug index" section containing only a placeholder comment

#### `templates/specs/taskcreator.md`

Derived from `jbuildmon/specs/taskcreator.md`. Changes:
- Remove the bats-core specific line from the unit testing framework list (`Bash shell scripts should use bats-core`)
- Keep all other language-specific framework recommendations (Java/JUnit, TypeScript/Jest, Groovy/Spock)
- Remove the reference in the "Output format" section to chunk_template using bats-core (`see chunk_template.md for a format example of a system for bash shell scripts using the bats-core unit testing framework`)
- Replace with a generic reference: `see chunk_template.md for a format example`
- Keep everything else as-is

#### `templates/specs/chunk_template.md`

Derived from `jbuildmon/specs/chunk_template.md`. Changes:
- Replace `.bats` file extension references with generic `<test-file>` placeholders in the Produces and Test Plan sections
- Replace `test/<feature_name>.bats` with `test/<feature_name>.<ext>`
- Keep the template structure intact

#### `templates/specs/todo/README.md`

New file. Contains:
- Heading explaining the todo directory convention
- Description that files here represent raw ideas not yet spec'd or planned
- Conventions section explaining `*-spec.md` and `*-plan.md` naming patterns
- Empty index section

### 3. Install Script: `templates/install-spec-framework.sh`

A bash script that deploys the template files into a target project directory.

**Usage:**
```
install-spec-framework.sh [--force] <target-directory>
```

**Behavior:**
- Takes a target project directory as the first positional argument
- Copies all template files into the target, creating directories as needed (`specs/`, `specs/todo/`)
- Uses `git -C <target> rev-parse --git-dir` to check if the target is a git repo; prints a warning if not
- Default behavior: skip files that already exist in the target (print "skipped" message)
- `--force` flag: overwrite existing files (print "overwritten" message)
- Prints status for each file: `created`, `skipped`, or `overwritten`
- Exits with 0 on success, 1 on usage error (missing target directory)

### 4. Files NOT in Scope

The following are intentionally excluded from the template:
- `.agents/skills/*` — skill-specific, not part of the process framework
- `jbuildmon/CLAUDE.md` — entirely project-specific (bats testing, buildgit changes, skill, hints)
- `jbuildmon/hints/*` — project-specific debugging notes
- Any spec files (`*-spec.md`) — those are project-specific implementations
- Any plan files (`*-plan.md`) — those are project-specific implementation plans

## Test Strategy

This spec produces no runtime code requiring unit tests. Verification is manual:

1. Inspect each template file to confirm no jbuildmon-specific content leaked through
2. Run the install script against a temporary directory and verify:
   - All expected files are created
   - The `--force` flag overwrites existing files
   - Without `--force`, existing files are skipped
   - Non-git-repo warning is printed when appropriate
3. Verify the install script is executable (`chmod +x`)
