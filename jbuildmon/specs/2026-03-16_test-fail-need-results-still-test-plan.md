# Manual Test Plan: Hierarchical Test Results with Downstream Aggregation

**Spec:** `2026-03-16_test-fail-need-results-still-spec.md`
**Purpose:** Verify that test results from downstream builds are displayed in a hierarchical breakdown with aggregated Totals, and that one-line mode shows the Totals.

## Prerequisites

- Jenkins server is reachable (`$JENKINS_URL` set)
- Jenkins credentials configured (`$JENKINS_USER_ID`, `$JENKINS_API_TOKEN`)
- `phandlemono-IT` job has:
  - Build #73 (FAILURE — component failed, parent testReport returns 404)
  - Build #75 (SUCCESS — all stages completed, parent + downstream test reports available)
- `ralph1/main` job has recent builds (no downstream builds)

## Test 1: Failed build — hierarchical display (`--all`)

**Command:**
```bash
buildgit --job phandlemono-IT status 73 --all 2>&1 | sed -n '/=== Test Results ===/,/====================/p'
```

**Verify:**
- [ ] First line after header shows `phandlemono-IT` with `Total: ? | Passed: ? | Failed: ? | Skipped: ?`
- [ ] Child lines indented 2 spaces: `Build SignalBoot` and `Build Handle`
- [ ] `Build SignalBoot` shows failure count > 0
- [ ] `Build Handle` shows all tests passing
- [ ] `--------------------` separator before Totals
- [ ] `Totals` row shows aggregated sum (treating `?` as 0)
- [ ] Numbers are right-aligned across all lines
- [ ] Does NOT show `(no test results available)`

## Test 2: Successful build — hierarchical display (`--all`)

**Command:**
```bash
buildgit --job phandlemono-IT status 75 --all 2>&1 | sed -n '/=== Test Results ===/,/====================/p'
```

**Verify:**
- [ ] Shows `phandlemono-IT` with actual counts (pass=19, fail=0)
- [ ] Shows `Build SignalBoot` with counts (pass=15, fail=0)
- [ ] Shows `Build Handle` with counts (pass=64, fail=0)
- [ ] Totals row shows sum of all three (98 total)
- [ ] All lines are green (all passing)

## Test 3: Failed build — one-line mode

**Command:**
```bash
buildgit --job phandlemono-IT status 73
```

**Verify:**
- [ ] Shows `Tests=97/1/0` (or similar — sum of downstream results, NOT `?/?/?`)
- [ ] Failed count > 0

## Test 4: Successful build — one-line mode

**Command:**
```bash
buildgit --job phandlemono-IT status 75
```

**Verify:**
- [ ] Shows `Tests=98/0/0` (sum of parent 19 + signalboot 15 + handle 64)
- [ ] Previous value was `Tests=19/0/0` (parent only) — now includes downstream totals

## Test 5: Failed build — JSON mode

**Command:**
```bash
buildgit --job phandlemono-IT status 73 --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
tr = d.get('test_results', {})
print('Totals: total=%s passed=%s failed=%s skipped=%s' % (tr.get('total'), tr.get('passed'), tr.get('failed'), tr.get('skipped')))
bd = tr.get('breakdown', [])
print('Breakdown entries: %d' % len(bd))
for b in bd:
    print('  %s: total=%s passed=%s failed=%s' % (b.get('job'), b.get('total'), b.get('passed'), b.get('failed')))
"
```

**Verify:**
- [ ] `test_results` is not `null`
- [ ] Top-level totals match the Totals row from `--all` output
- [ ] `breakdown` array has 3 entries (parent + 2 downstream)
- [ ] Parent entry has `null` values (for `?`)
- [ ] Downstream entries have actual counts

## Test 6: Successful build — JSON mode

**Command:**
```bash
buildgit --job phandlemono-IT status 75 --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
tr = d.get('test_results', {})
print('Totals: total=%s passed=%s failed=%s' % (tr.get('total'), tr.get('passed'), tr.get('failed')))
bd = tr.get('breakdown', [])
print('Breakdown entries: %d' % len(bd))
for b in bd:
    print('  %s: total=%s passed=%s' % (b.get('job'), b.get('total'), b.get('passed')))
"
```

**Verify:**
- [ ] Top-level totals = sum of all 3 jobs
- [ ] `breakdown` has 3 entries with actual counts for each

## Test 7: Job without downstream builds — unchanged

**Command:**
```bash
buildgit status --all 2>&1 | sed -n '/=== Test Results ===/,/====================/p'
```

**Verify:**
- [ ] Shows single-line format: `Total: N | Passed: N | Failed: N | Skipped: N`
- [ ] No hierarchy, no Totals row, no `--------------------` separator
- [ ] Unchanged from prior behavior

## Test 8: Job without downstream builds — JSON unchanged

**Command:**
```bash
buildgit status --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
tr = d.get('test_results', {})
print('Has breakdown:', 'breakdown' in tr)
print('total=%s passed=%s' % (tr.get('total'), tr.get('passed')))
"
```

**Verify:**
- [ ] No `breakdown` field present
- [ ] Existing `test_results` structure unchanged

## Test 9: Consistency across modes for failed build

**Command:**
```bash
echo "=== One-line ==="
buildgit --job phandlemono-IT status 73
echo ""
echo "=== JSON Totals ==="
buildgit --job phandlemono-IT status 73 --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
tr = d.get('test_results', {})
print('Tests=%s/%s/%s' % (tr.get('passed',0), tr.get('failed',0), tr.get('skipped',0)))
"
echo ""
echo "=== --all Totals ==="
buildgit --job phandlemono-IT status 73 --all 2>&1 | grep '^Totals'
```

**Verify:**
- [ ] One-line `Tests=` values match JSON totals
- [ ] JSON totals match `--all` Totals row

## Test 10: Multiple builds in -n mode

**Command:**
```bash
buildgit --job phandlemono-IT status -n 5
```

**Verify:**
- [ ] Failed builds show actual aggregated test counts (not `?/?/?`)
- [ ] Successful builds show aggregated test counts
- [ ] No errors or timeouts from extra API calls

## Test 11: Color verification (TTY)

**Command:**
```bash
buildgit --job phandlemono-IT status 73 --all 2>&1 | cat -v | sed -n '/Test Results/,/====/p'
```

**Verify:**
- [ ] Parent line (all `?`) uses default/white color (no ANSI color codes)
- [ ] Downstream line with failures uses yellow ANSI codes
- [ ] Downstream line with all passing uses green ANSI codes
- [ ] Totals line with failures uses yellow ANSI codes

## Test Summary

| # | Test | Pass/Fail | Notes |
|---|------|-----------|-------|
| 1 | Failed build hierarchical --all | | |
| 2 | Successful build hierarchical --all | | |
| 3 | Failed build one-line | | |
| 4 | Successful build one-line | | |
| 5 | Failed build JSON | | |
| 6 | Successful build JSON | | |
| 7 | No-downstream --all unchanged | | |
| 8 | No-downstream JSON unchanged | | |
| 9 | Mode consistency | | |
| 10 | Multiple builds -n mode | | |
| 11 | Color verification | | |
