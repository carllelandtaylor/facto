#!/bin/bash
# skill-structure.test.sh — structural tests for pr/SKILL.md
#
# facto:pr used to choose its push command by asking whether the branch has an
# upstream. That is not the same question as "does a same-named remote branch
# exist": task-start.sh creates task branches tracking origin/<main>, so every
# Facto task branch has an upstream before it has ever been pushed. The skill
# therefore ran a plain `git push` where a first-push with -u was required
# (Issue #116). The decision now lives in `facto-helper.sh push-plan`, which is
# behaviorally tested in plugins/facto/bin/tests/facto-helper.test.sh.
#
# This suite guards the SKILL.md side of that fix: that the skill delegates,
# and that the broken check has not been re-inlined into the prose. It is a
# structural test and cannot prove the model follows the prose correctly — the
# real correctness guarantee is the behavioral suite named above.
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

# Print only the lines inside ```bash fences — i.e. the text that is meant to be
# run, as opposed to prose that merely discusses commands.
_code_lines() {
  awk '/^```bash/ {inblock=1; next} /^```/ {inblock=0; next} inblock' "$_SKILL"
}

# ── Case 1: Phase 5 delegates the push decision to push-plan ────────────────
if _code_lines | grep -q 'facto-helper.sh push-plan'; then
  pass "Phase 5 invokes facto-helper.sh push-plan"
else
  fail "no runnable 'facto-helper.sh push-plan' call found in a bash block"
fi

# ── Case 2: the @{u} push decision is not re-inlined ────────────────────────
# Prose may NAME @{u} in order to warn against it (case 3); what must never
# come back is an executable @{u} check.
if ! _code_lines | grep -q '@{u}'; then
  pass "no @{u} check remains in any runnable command"
else
  fail "an @{u} check was re-inlined into a bash block: $(_code_lines | grep '@{u}')"
fi

# ── Case 3: the reason the check is delegated is recorded ───────────────────
# Principle 7: the empirical gotcha stays written down, or a future edit will
# re-derive the broken check from first principles.
if grep -q 'Do not reintroduce an `@{u}` check here' "$_SKILL"; then
  pass "the @{u} gotcha is recorded as an explicit warning"
else
  fail "the 'Do not reintroduce an @{u} check here' warning is missing"
fi

# ── Case 4: Phase 1's early exit keys on the push plan, not remote_uptodate ─
if grep -q 'action=nothing-to-push' "$_SKILL"; then
  pass "Phase 1 early exit keys on action=nothing-to-push"
else
  fail "Phase 1 does not key its early exit on 'action=nothing-to-push'"
fi

if ! grep -q 'remote_uptodate' "$_SKILL"; then
  pass "the remote_uptodate signal is gone"
else
  fail "remote_uptodate still appears — it was measured against origin/main"
fi

# ── Case 5: no runnable command uses a bare --force ────────────────────────
# --force-with-lease is required; a bare --force discards the safety net. As in
# case 2, prose may name bare --force in order to forbid it — what must never
# appear is a runnable one.
if ! _code_lines | grep -qE -- '--force([^-]|$)'; then
  pass "no runnable command uses a bare --force"
else
  fail "a bare --force appears in a bash block: $(_code_lines | grep -E -- '--force([^-]|$)' | head -1)"
fi

# The rule itself must also still be stated, or nothing stops it drifting back.
if grep -q 'never bare `--force`' "$_SKILL"; then
  pass "the 'never bare --force' rule is stated"
else
  fail "the 'never bare --force' rule is missing from SKILL.md"
fi

# ── Case 6: the unrelated bash -c wrapper rule survived the rewrite ────────
# Guards against a Phase 5 rewrite quietly dropping a rule it did not own.
if grep -q 'Never wrap `git push` in `bash -c' "$_SKILL"; then
  pass "the 'never wrap git push in bash -c' rule survived"
else
  fail "the 'never wrap git push in bash -c' rule was dropped"
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
