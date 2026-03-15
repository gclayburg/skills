# Manual Test Plan: Count IMPLEMENTED specs

**Spec:** `2026-03-15_specreport-spec.md`
**Purpose:** Verify the specreport script counts IMPLEMENTED specs correctly.

## Prerequisites

- The script `jbuildmon/specs/specreport.sh` exists and is executable.

## Test 1: Script runs and produces one line of output

**Command:**
```bash
bash jbuildmon/specs/specreport.sh
```

**Verify:**
- [ ] Exit code is 0
- [ ] Exactly one line of output
- [ ] Format is `IMPLEMENTED: <number>`

## Test 2: Count matches manual grep

**Command:**
```bash
SCRIPT_COUNT=$(bash jbuildmon/specs/specreport.sh | awk '{print $2}')
GREP_COUNT=$(grep -l '`IMPLEMENTED`' jbuildmon/specs/*-spec.md | wc -l | tr -d ' ')
echo "Script: $SCRIPT_COUNT  Grep: $GREP_COUNT"
```

**Verify:**
- [ ] Both counts are identical

## Test 3: Works from a different working directory

**Command:**
```bash
cd /tmp && bash /Users/gclaybur/dev/ralph1/jbuildmon/specs/specreport.sh
```

**Verify:**
- [ ] Same output as running from the repo root

## Test Summary

| # | Test | Pass/Fail | Notes |
|---|------|-----------|-------|
| 1 | Runs with one line output | | |
| 2 | Count matches manual grep | | |
| 3 | Works from different directory | | |
