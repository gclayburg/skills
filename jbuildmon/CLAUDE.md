## Testing
- This project uses bats-core for unit testing.
- IMPORTANT: bats-core is located at `jbuildmon/test/bats/bin/bats`; do not use any bats command from your `$PATH`.
- Note: The `'buildgit status -f'` command will run indefinitely, waiting for the next build after printing output. Terminate it with `SIGTERM` signal.

## Changes
- any changes to the 'buildgit status' command must ensure that 'buildgit status', 'buildgit status -f', and 'buildgit status --json' are always consistent with each other.  If you change one of these, they all should be changed to match.


## Skill
- buildgit shell script is distributed as an AI Agent skill in folder skill/buildgit

## Hints
- See [hints/index.md](hints/index.md) for hard-won lessons from debugging and development. Check these before investigating test failures or platform-specific issues.

