# Hints Index

This directory contains hard-won lessons from debugging and development on jbuildmon. Each hint documents what worked, what didn't, and why -- so future contributors (human or AI) don't repeat the same mistakes. Update this index whenever a new hint file is added.

## Hints

- **[bats-background-processes-linux.md](bats-background-processes-linux.md)** -- Bats tests that launch background processes hang on Linux CI but pass on macOS. Root cause: bats-core's internal fd 3 leaks to orphaned descendant processes. Fix: always use `3>&-` when launching background processes, and use `kill -9` for reliable cleanup.
