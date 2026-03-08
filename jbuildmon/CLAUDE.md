## Testing
- This project uses bats-core for unit testing.
- IMPORTANT: bats-core is located at `jbuildmon/test/bats/bin/bats`; do not use any bats command from your `$PATH`.
- when running bats-core tests always use the --jobs option for speed: `bats --jobs 10 ...`
- Note: The `'buildgit status -f'` command will run indefinitely, waiting for the next build after printing output. Terminate it with `SIGTERM` signal.
- **Tests must never silently skip in CI.** If a test cannot run because the environment is not set up (missing credentials, missing Jenkins job, missing infrastructure), the test must **fail** with a clear error — not skip. Skipping hides failures and gives false confidence. Unit tests mock their dependencies and are self-contained. Integration tests require real infrastructure; if that infrastructure is unavailable, that is a broken environment and must be surfaced as a failure.

## Changes
- any changes to the 'buildgit status' command must ensure that 'buildgit status', 'buildgit status -f', and 'buildgit status --json' are always consistent with each other.  If you change one of these, they all should be changed to match.


## Skill
- buildgit shell script is distributed as an AI Agent skill in folder skill/buildgit

## Hints
- See [hints/index.md](hints/index.md) for hard-won lessons from debugging and development. Check these before investigating test failures or platform-specific issues.

