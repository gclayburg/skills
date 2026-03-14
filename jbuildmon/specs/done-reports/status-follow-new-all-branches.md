# status-follow-new-all-branches

Traceability note for [2026-03-14_status-follow-probe-all-branches-spec.md](../2026-03-14_status-follow-probe-all-branches-spec.md).

The spec referenced a raw report path under `specs/todo/`, but that source file was not present in this repository or in `HEAD` during finalize. This note preserves the referenced filename and the original request intent captured by the spec:

- `buildgit status -f` should be able to follow the next Jenkins build even when the build starts on a different multibranch branch than the current checkout.
- The resulting feature became `buildgit status -f --probe-all`, which watches the top-level multibranch job, detects the first branch build that starts, and then follows that branch build with the normal monitoring flow.
