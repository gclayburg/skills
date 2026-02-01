## Executing Implementation Plan Chunks

When asked to work on a chunk from an implementation plan (`*-plan.md` file):

1. **Every chunk is executable.** Do not skip chunks or assume they cannot be done. Chunks are designed to be performed by an AI agent—not deferred to humans or marked as "investigation only."

2. **Attempt the task before concluding it's blocked.** If a chunk requires querying an API, accessing a file, or gathering data, try it. Use available environment variables (e.g., `JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN`) and tools at your disposal.

3. **Do not substitute assumptions for actual data.** If a chunk says "capture the actual API response," do not create a fixture based on general knowledge or documentation. Execute the API call and use the real response.

4. **Follow chunk order when dependencies exist.** If Chunk B depends on Chunk A, complete Chunk A first. Do not skip Chunk A and build Chunk B based on assumptions about what Chunk A would have produced.

5. **If truly blocked, report why.** If a chunk genuinely cannot be completed (e.g., credentials missing, service unreachable), report the specific error encountered—not a preemptive assumption that it won't work.

## Testing
- jbuildmon uses bats-core located at test/bats/bin/bats
- IMPORTANT: to run the bats command you must use the full path of test/bats/bin/bats







#
#
#
#
#
#
#
