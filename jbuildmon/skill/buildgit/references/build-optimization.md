# Build Optimization

Use this workflow when the user wants to make Jenkins builds faster, reduce queue time, or understand where executor capacity is being lost.

## Steps

1. Measure queue pressure with `scripts/buildgit queue`.
   This shows whether builds are waiting, why they are waiting, and how long they have been queued.

2. Measure executor capacity with `scripts/buildgit agents`.
   Use this to find saturated labels, idle capacity, offline nodes, and labels with too few executors.

3. Find build-time bottlenecks with `scripts/buildgit timing --tests`.
   Start with the latest successful build so timings are complete, then look for the slowest sequential stages, the bottleneck branch inside each parallel group, and the slowest test suites.

4. Inspect pipeline shape with `scripts/buildgit pipeline`.
   Use this to confirm whether slow work is sequential, whether a stage is already parallelized, and which agent label each stage runs on.

5. Form a constrained optimization hypothesis.
   Examples: move a bottleneck stage onto a less-contended label, increase executors for a saturated label, split a large test suite, or parallelize a sequential stage that dominates wall time.

6. Re-run the same commands after the change.
   Compare queue wait, executor saturation, stage timing, bottleneck branch, and test suite timing to verify that the change improved throughput rather than just moving the bottleneck elsewhere.

## Key constraints

- Prefer recent successful builds for timing analysis; failed builds often have incomplete timing or missing later stages.
- `queue` and `agents` describe current Jenkins state; `timing` and `pipeline` describe build structure and historical execution.
- High queue time with idle executors usually points to label mismatch, quiet period, or job restrictions rather than raw capacity shortage.
- A faster branch inside a parallel block does not improve wall time if another sibling branch remains the bottleneck.
- Agent labels matter as much as stage duration; a short stage on an oversubscribed label can still delay the whole pipeline.
- Optimize one suspected bottleneck at a time and re-measure before proposing further changes.
