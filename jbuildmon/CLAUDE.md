## Testing
- This project uses bats-core for unit testing
- IMPORTANT: bats-core is located at <git_repo_root>/jbuildmon/test/bats/bin/bats, do not use any bats command in your $PATH.

## Implementation Rules (specs/todo)
When implementing a spec or bug fix from `specs/todo/`:
- Before beginning work, make sure all unit tests are in a passing state
- Update `CHANGELOG.md` (root level) if the change adds features, changes functionality, deprecates/removes a feature, fixes a bug, or fixes a security vulnerability
- Update `README.md` (root level) if any CLI options change
- Update `skill/buildgit/SKILL.md` as needed
- Make sure all unit tests pass before considering the item complete
- When complete, move the spec file from `specs/todo/` to `specs/` and add it to the index in `specs/README.md`; remove it from `specs/todo/README.md`
- When compmlete, if the spec references other files in the References: heade move these files to specs/done-reports and update the reference path in the spec

## Skill
- buildgit shell script is distributed as a skill in folder skill/buildgit, update skill/buildgit/SKILL.md as necessary.



## Hints
- See [hints/index.md](hints/index.md) for hard-won lessons from debugging and development. Check these before investigating test failures or platform-specific issues.

