#!/bin/bash
# skill-structure.test.sh — structural tests for review-loop-code/SKILL.md
#
# review-loop-code (../SKILL.md) gates whether another review cycle runs on
# the severity of the previous cycle's in-scope findings: critical or
# important findings continue the loop, an all-minor cycle is the last one,
# and if that terminal cycle fixes nothing, the loop short-circuits straight
# to Done instead of paying for a commit and re-validation of an unchanged
# tree. This suite guards those load-bearing rules in the prose.
#
# These assertions are pinned to specific marker phrases in SKILL.md today.
# A future prose edit should either preserve those markers or update this
# test deliberately — it is not meant to be a loose contract.
#
# This suite only reads SKILL.md; it creates nothing and leaves nothing
# behind.

set -uo pipefail  # not -e: we want to run every case and tally failures

# --- Resolve SKILL.md under test relative to this file's location ---
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKILL="${_TEST_DIR}/../SKILL.md"

if [[ ! -f "$_SKILL" ]]; then
  echo "FAIL: SKILL.md under test not found: $_SKILL" >&2
  exit 1
fi

_FAILS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; _FAILS=$((_FAILS + 1)); }

# ── Case 1: the old binary stopping rule is gone ────────────────────────────
# Negative assertion — guards against a revert that re-adds the old rule
# alongside the new severity gate (two contradictory instructions at once).
if grep -q "Stop when a review cycle produces no feedback" "$_SKILL"; then
  fail "old binary stopping rule still present ('Stop when a review cycle produces no feedback')"
else
  pass "old binary stopping rule is gone"
fi

# ── Case 2: terminal-cycle rule present — an all-minor cycle is the final one
if grep -q "This cycle is the final cycle" "$_SKILL"; then
  pass "terminal-cycle rule present (all-minor cycle is the final cycle)"
else
  fail "terminal-cycle rule missing ('This cycle is the final cycle')"
fi

# ── Case 3: continuation rule present — critical/important findings continue
# Pinned to Phase 2 outcome 2's own wording, which occurs exactly once. The
# looser phrases nearby will not do: "findings are critical or important" also
# matches the frontmatter description, and "another full cycle follows" also
# matches Phase 3's rationale, so either one would stay green with outcome 2
# deleted — which is the revert this case exists to catch.
if grep -q "One or more in-scope findings are critical or important" "$_SKILL"; then
  pass "continuation rule present (critical/important findings continue the loop)"
else
  fail "continuation rule missing (Phase 2 outcome 2: 'One or more in-scope findings are critical or important')"
fi

# ── Case 4: max-cycles backstop retained — default-5 cycle cap survives ────
if grep -q "default: 5" "$_SKILL"; then
  pass "max-cycles backstop retained (default: 5)"
else
  fail "max-cycles backstop missing ('default: 5')"
fi

# ── Case 5: severity list unchanged — critical / important / minor ─────────
# Pins the decision that the three buckets stay and stay undefined; a future
# edit adding a fourth level or baking in definitions has to change this
# test on purpose.
if grep -q "critical / important / minor" "$_SKILL"; then
  pass "severity list unchanged (critical / important / minor)"
else
  fail "severity list missing or changed ('critical / important / minor')"
fi

# ── Case 6: terminal-mode fix branch present ───────────────────────────────
# Phase 3's terminal branch is the rule that the orchestrator judges each
# minor rather than fixing them all. Deleting it leaves the other cases passing.
if grep -q "judge each minor on whether fixing it is worth the risk" "$_SKILL"; then
  pass "terminal-mode fix branch present (orchestrator judges each minor)"
else
  fail "terminal-mode fix branch missing ('judge each minor on whether fixing it is worth the risk')"
fi

# ── Case 7: the repeat phase is conditional ────────────────────────────────
# Reverting Phase 7 to an unconditional "Go back to Phase 1" restores the old
# cost profile while leaving Phase 2's rules intact, so pin it separately.
if grep -q 'section below instead of repeating' "$_SKILL"; then
  pass "repeat phase is conditional (a terminal cycle falls through to Done)"
else
  fail "conditional repeat missing ('section below instead of repeating')"
fi

# ── Case 8: deferred minors are reported ──────────────────────────────────
# Requirement 2 has two halves: the orchestrator judges each minor (case 6),
# and whatever it skips gets reported. Without this, dropping the report
# bullet leaves the suite green and skipped minors vanish silently.
if grep -q "minors skipped on a terminal cycle" "$_SKILL"; then
  pass "deferred minors are reported in the final summary"
else
  fail "deferred-minor reporting missing ('minors skipped on a terminal cycle')"
fi

# ── Case 9: a terminal cycle that fixes nothing short-circuits ─────────────
# Without it, a terminal cycle that skips every minor still pays for a commit
# subagent and a full re-validation of an unchanged tree — the exact wasted
# spend this gate exists to remove.
if grep -q "If the terminal cycle fixes nothing" "$_SKILL"; then
  pass "no-fix terminal cycle short-circuits to Done"
else
  fail "no-fix short-circuit missing ('If the terminal cycle fixes nothing')"
fi

# ── Tally ────────────────────────────────────────────────────────────────────
echo ""
if [[ "$_FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "$_FAILS test(s) FAILED"
  exit 1
fi
