## Testing
- This project uses bats-core for unit testing.
- IMPORTANT: bats-core is located at `jbuildmon/test/bats/bin/bats`; do not use any bats command from your `$PATH`.
- when running bats-core tests always use the --jobs option for speed: `bats --jobs 10 ...`
- Note: The `'buildgit status -f'` command will run indefinitely, waiting for the next build after printing output. Terminate it with `SIGTERM` signal.
- **Tests must never silently skip in CI.** If a test cannot run because the environment is not set up (missing credentials, missing Jenkins job, missing infrastructure), the test must **fail** with a clear error — not skip. Skipping hides failures and gives false confidence. Unit tests mock their dependencies and are self-contained. Integration tests require real infrastructure; if that infrastructure is unavailable, that is a broken environment and must be surfaced as a failure.
- **Bats fd 3 and background processes:** bats-core uses fd 3 for internal output capture. When running tests in parallel (`--jobs`), subprocesses that inherit fd 3 can cause SIGPIPE (exit 141) or cause bats to hang indefinitely. **Always add `3>&-`** before `2>&1` when launching subprocesses via `run bash -c`: `run bash -c "bash script.sh 3>&- 2>&1"`. This also applies to background processes: `cmd > out.txt 2>&1 3>&- &`.

## Changes
- any changes to the 'buildgit status' command must ensure that 'buildgit status', 'buildgit status -f', and 'buildgit status --json' are always consistent with each other.  If you change one of these, they all should be changed to match.


## Skill
- buildgit shell script is distributed as an AI Agent skill in folder skill/buildgit

## Hints
- See [hints/index.md](hints/index.md) for hard-won lessons from debugging and development. Check these before investigating test failures or platform-specific issues.

