# Needed Tools: Jenkins API Commands for buildgit

This document captures Jenkins API calls that were needed during debugging of build failures but are not currently available through the `buildgit` tool. These should be added as new commands or options.

## Context

When build #97 and #98 failed (ABORTED due to hanging tests), the only information `buildgit` provided was the final status (`ABORTED`) and a console URL. To diagnose the root cause, several manual API calls were needed.

---

## 1. View Console Output for a Build

**Purpose:** See the full console log for a specific build to diagnose failures, identify where a build hung, or see test output.

**API Call:**
```
GET /job/{job_name}/{build_number}/consoleText
```

**Example:**
```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/ralph1/98/consoleText"
```

**When needed:** After build #98 was ABORTED, we needed to see the console output to determine which test file was hanging. `buildgit` only showed `Finished: ABORTED` with no way to inspect why.

**Suggested buildgit command:**
```
buildgit console [build_number]       # Show console output for a build
buildgit console                      # Show console output for latest build
buildgit console --tail 50            # Show last 50 lines
```

---

## 2. Progressive Console Output (Streaming/Tail)

**Purpose:** Stream console output in real-time or fetch output incrementally, useful for watching a build in progress or tailing the end of a completed build.

**API Call:**
```
GET /job/{job_name}/{build_number}/logText/progressiveText?start={byte_offset}
```

Response includes header `X-Text-Size` indicating the current size, which can be used as `start` for the next request to get only new output.

**Example:**
```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/ralph1/98/logText/progressiveText?start=0"
```

**When needed:** Would have been useful to watch the build in real-time to see exactly where it got stuck, rather than waiting for the build to timeout and then inspecting the full log.

**Suggested buildgit command:**
```
buildgit console -f                   # Stream/follow console output live
buildgit console -f 98                # Follow specific build's console
```

---

## 3. Build Information / Build Details

**Purpose:** Get detailed JSON information about a specific build including result, duration, timestamp, and parameters.

**API Call:**
```
GET /job/{job_name}/{build_number}/api/json
```

**Example:**
```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/ralph1/98/api/json"
```

**When needed:** To check whether a build was still running, had been aborted, or had completed. `buildgit status` shows the current/latest build but there's no way to query a specific historical build.

**Suggested buildgit command:**
```
buildgit status 98                    # Show status of specific build number
buildgit status --last 5              # Show status of last 5 builds
```

---

## 4. Test Results for a Build

**Purpose:** Get structured test results (pass/fail counts, failed test names, error messages) for a specific build.

**API Call:**
```
GET /job/{job_name}/{build_number}/testReport/api/json
```

**Example:**
```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/ralph1/98/testReport/api/json"
```

**When needed:** Build #97 produced an empty `test-results.xml` because tests hung. We needed to check if Jenkins had any partial test results that could indicate which tests ran before the hang.

**Suggested buildgit command:**
```
buildgit tests [build_number]         # Show test results for a build
buildgit tests --failed               # Show only failed tests
buildgit tests --failed 98            # Failed tests for specific build
```

---

## 5. Pipeline Stage Details (Workflow API)

**Purpose:** Get detailed information about each pipeline stage including status, duration, and which stage failed or is currently running.

**API Call:**
```
GET /job/{job_name}/{build_number}/wfapi/describe
```

**Example:**
```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/ralph1/98/wfapi/describe"
```

**When needed:** To determine which pipeline stage (Initialize Submodules, Build, Unit Tests, Deploy) was running when the build was aborted. `buildgit` showed stage transitions during monitoring but didn't provide a way to query stages after the fact.

**Suggested enhancement:** Already partially available via `buildgit status -f` during monitoring. Could be enhanced to show stage details for completed builds.

---

## 6. Build Queue Status

**Purpose:** Check if a build is queued and why it might be waiting (e.g., waiting for executor, blocked by another build).

**API Call:**
```
GET /queue/api/json
```

**Example:**
```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/queue/api/json"
```

**When needed:** When triggering builds, sometimes they sit in the queue. Understanding why (no available executors, throttled, etc.) helps diagnose delays.

**Current status:** `buildgit build` already uses this internally via `wait_for_queue_item()`, but the information isn't exposed to the user in a queryable way.

---

## Summary of Proposed Commands

| Command | Purpose |
|---------|---------|
| `buildgit console [build#]` | View console output for a build |
| `buildgit console -f [build#]` | Stream/follow console output live |
| `buildgit status <build#>` | Show status of a specific build |
| `buildgit status --last N` | Show recent build history |
| `buildgit tests [build#]` | Show test results for a build |
| `buildgit tests --failed [build#]` | Show only failed tests |

## Priority

1. **`buildgit console`** - Most needed. This was the primary missing tool during debugging. Being able to see console output without opening a browser would have saved significant time.
2. **`buildgit tests`** - Second priority. Quick access to test results from the command line.
3. **`buildgit status <build#>`** - Third priority. Querying historical builds.
