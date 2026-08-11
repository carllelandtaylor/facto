#!/bin/bash
# skill-structure.test.sh — structural tests for observe/SKILL.md
#
# observe supports GitHub Issues only: its routing, dedup, Issue creation and
# autonomous closes are all built on `gh issue list` plus a GitHub Project
# board. On a repo whose tracker.type is "linear" it must hard-stop before
# doing anything, because a partial run would create junk in a real Linear
# workspace. This suite guards that the guard is present, that it comes before
# the first tracker call, and that it is worded as a stop rather than a
# preference.
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

# Line number of the first match, or empty if absent.
_line_of() { grep -n -- "$1" "$_SKILL" | head -1 | cut -d: -f1; }

# ── Case 1: the guard reads the tracker type ────────────────────────────────
if grep -q 'tracker.field type' "$_SKILL"; then
  pass "guard reads tracker.field type"
else
  fail "guard missing — no 'tracker.field type' lookup in SKILL.md"
fi

# ── Case 2: the guard names linear as the unsupported tracker ───────────────
if grep -qi 'is `linear`, stop immediately' "$_SKILL"; then
  pass "guard stops on tracker.type linear"
else
  fail "guard does not stop on linear ('is \`linear\`, stop immediately')"
fi

# ── Case 3: the guard runs BEFORE the first tracker call ────────────────────
# A guard placed after REPO_SLUG resolution would already have shelled out to
# the GitHub-only path, which is the failure this ordering exists to prevent.
_guard_line="$(_line_of 'tracker.field type')"
_repo_line="$(_line_of 'REPO_SLUG="$(facto-helper.sh tracker.field repo)"')"
if [[ -n "$_guard_line" && -n "$_repo_line" && "$_guard_line" -lt "$_repo_line" ]]; then
  pass "guard precedes the first REPO_SLUG resolution (line $_guard_line < $_repo_line)"
else
  fail "guard must precede REPO_SLUG resolution (guard=${_guard_line:-none}, repo=${_repo_line:-none})"
fi

# ── Case 4: the guard forbids partial behavior explicitly ───────────────────
# Without this, an agent reading the skill may reasonably decide to do the
# "harmless" parts anyway.
if grep -q 'Do not create Issues, do not comment, do not write status' "$_SKILL"; then
  pass "guard forbids partial behavior (no create / comment / status)"
else
  fail "guard does not forbid partial behavior ('Do not create Issues, do not comment, do not write status')"
fi

# ── Case 5: the guard is stated as a hard stop ──────────────────────────────
if grep -q 'This is a hard stop, not a preference' "$_SKILL"; then
  pass "guard is stated as a hard stop"
else
  fail "guard is not stated as a hard stop ('This is a hard stop, not a preference')"
fi

# ── Tally ───────────────────────────────────────────────────────────────────
echo ""
if [[ "$_FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "$_FAILS test(s) FAILED"
  exit 1
fi
