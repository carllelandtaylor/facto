#!/bin/bash
# facto-helper.test.sh — resolver tests for bin/facto-helper.sh
#
# Covers the three subcommands whose behavior depends on which tracker the
# host repo is configured for: task-slug (slug normalization), task-dir (the
# tasks_dir override), and current-issue (identifier extraction from the
# branch). The load-bearing case is a Linear identifier — "sio-9-foo" is a
# valid issue-backed slug and must not be prefixed with "UNKNOWN-", and the
# identifier it yields must come back uppercased to match Linear's canonical
# form.
#
# Sets up a throwaway git repo and writes .facto/settings.json variants into
# it. Each case runs in a subshell so the parent CWD is not polluted. Creates
# nothing outside its temp dirs and leaves nothing behind.

set -uo pipefail  # not -e: we want to run every case and tally failures

# --- Resolve the script under test relative to this file's location ---
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SCRIPT_UNDER_TEST="${_TEST_DIR}/../facto-helper.sh"

if [[ ! -f "$_SCRIPT_UNDER_TEST" ]]; then
  echo "FAIL: script under test not found: $_SCRIPT_UNDER_TEST" >&2
  exit 1
fi

# --- Set up a throwaway git repo ---
_TMP="$(mktemp -d)"
trap 'rm -rf "$_TMP"' EXIT

git init --quiet --initial-branch=main "$_TMP"
git -C "$_TMP" config user.email "test@example.com"
git -C "$_TMP" config user.name  "test"
echo "init" > "$_TMP/README.md"
git -C "$_TMP" add README.md
git -C "$_TMP" commit --quiet -m "init"
mkdir -p "$_TMP/.facto"

_FAILS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; _FAILS=$((_FAILS + 1)); }

# Write a tracker config of the given type into the temp repo. The patterns
# mirror the shapes setup-facto writes for each tracker.
_write_config() {
  case "$1" in
    github)
      cat > "$_TMP/.facto/settings.json" <<'CONF'
{
  "tracker": {
    "type": "github-issues",
    "branch_issue_pattern": "^[a-z]+/(?<issue>[0-9]+)-"
  }
}
CONF
      ;;
    linear)
      cat > "$_TMP/.facto/settings.json" <<'CONF'
{
  "tracker": {
    "type": "linear",
    "branch_issue_pattern": "^[^/]+/(?<issue>[a-z][a-z0-9]*-[0-9]+)-"
  }
}
CONF
      ;;
    linear-tasksdir)
      cat > "$_TMP/.facto/settings.json" <<'CONF'
{
  "tasks_dir": "tasks",
  "tracker": {
    "type": "linear",
    "branch_issue_pattern": "^[^/]+/(?<issue>[a-z][a-z0-9]*-[0-9]+)-"
  }
}
CONF
      ;;
  esac
}

# Check out a fresh branch off main in the temp repo.
_checkout() {
  git -C "$_TMP" checkout --quiet -B "$1" main
}

# Run a subcommand from inside the temp repo, capturing stdout and exit code.
# Sets _OUT and _RC.
_run() {
  _OUT="$(cd "$_TMP" && "$_SCRIPT_UNDER_TEST" "$@" 2>/dev/null)"
  _RC=$?
}

# ── Case 1: a GitHub issue slug passes through unchanged ────────────────────
_write_config github
_checkout "feat/113-add-export"
_run task-slug
if [[ "$_OUT" == "113-add-export" ]]; then
  pass "task-slug passes a GitHub issue slug through unchanged"
else
  fail "task-slug on feat/113-add-export — expected '113-add-export', got '$_OUT'"
fi

# ── Case 2: a Linear identifier slug passes through unchanged ───────────────
# The regression this suite exists for: before the Linear form was added to
# _normalize_slug, this came back as "UNKNOWN-sio-9-create-app-switcher".
_write_config linear
_checkout "carllelandtaylor/sio-9-create-app-switcher"
_run task-slug
if [[ "$_OUT" == "sio-9-create-app-switcher" ]]; then
  pass "task-slug passes a Linear identifier slug through unchanged"
else
  fail "task-slug on carllelandtaylor/sio-9-create-app-switcher — expected 'sio-9-create-app-switcher', got '$_OUT'"
fi

# ── Case 3: an already-UNKNOWN slug passes through unchanged ────────────────
_write_config github
_checkout "feat/UNKNOWN-ref-design-mock"
_run task-slug
if [[ "$_OUT" == "UNKNOWN-ref-design-mock" ]]; then
  pass "task-slug passes an UNKNOWN- slug through unchanged"
else
  fail "task-slug on feat/UNKNOWN-ref-design-mock — expected 'UNKNOWN-ref-design-mock', got '$_OUT'"
fi

# ── Case 4: a bare description gets the UNKNOWN- prefix ─────────────────────
_write_config github
_checkout "feat/add-user-login-page"
_run task-slug
if [[ "$_OUT" == "UNKNOWN-add-user-login-page" ]]; then
  pass "task-slug prefixes a bare description with UNKNOWN-"
else
  fail "task-slug on feat/add-user-login-page — expected 'UNKNOWN-add-user-login-page', got '$_OUT'"
fi

# ── Case 5: a word-hyphen-word slug is NOT mistaken for an identifier ───────
# "release-2-notes" would match a naive <letters>-<digits> rule. The anchor
# requires the digits to be followed by "-", and the segment to start the
# slug, so this must still be treated as a bare description.
_write_config linear
_checkout "feat/release-notes-cleanup"
_run task-slug
if [[ "$_OUT" == "UNKNOWN-release-notes-cleanup" ]]; then
  pass "task-slug does not mistake a hyphenated description for an identifier"
else
  fail "task-slug on feat/release-notes-cleanup — expected 'UNKNOWN-release-notes-cleanup', got '$_OUT'"
fi

# ── Case 6: current-issue extracts a GitHub issue number ────────────────────
_write_config github
_checkout "feat/113-add-export"
_run current-issue
if [[ "$_RC" -eq 0 && "$_OUT" == "113" ]]; then
  pass "current-issue extracts a GitHub issue number"
else
  fail "current-issue on feat/113-add-export — expected '113' rc 0, got '$_OUT' rc $_RC"
fi

# ── Case 7: current-issue extracts and uppercases a Linear identifier ───────
# Linear branch names carry the identifier lowercased; its API expects the
# uppercase canonical form.
_write_config linear
_checkout "carllelandtaylor/sio-9-create-app-switcher"
_run current-issue
if [[ "$_RC" -eq 0 && "$_OUT" == "SIO-9" ]]; then
  pass "current-issue uppercases a Linear identifier"
else
  fail "current-issue on carllelandtaylor/sio-9-create-app-switcher — expected 'SIO-9' rc 0, got '$_OUT' rc $_RC"
fi

# ── Case 8: current-issue does not uppercase on a GitHub tracker ────────────
# Guards the uppercase step against firing for any tracker but Linear.
_write_config github
_checkout "feat/42-fix-thing"
_run current-issue
if [[ "$_OUT" == "42" ]]; then
  pass "current-issue leaves a GitHub number untouched"
else
  fail "current-issue on feat/42-fix-thing — expected '42', got '$_OUT'"
fi

# ── Case 9: current-issue fails on a branch matching neither pattern ────────
_write_config linear
_checkout "feat/no-issue-here"
_run current-issue
if [[ "$_RC" -ne 0 ]]; then
  pass "current-issue exits non-zero on a branch with no identifier"
else
  fail "current-issue on feat/no-issue-here — expected non-zero exit, got rc $_RC with '$_OUT'"
fi

# ── Case 10: task-dir honors tasks_dir for a Linear slug ────────────────────
_write_config linear-tasksdir
_checkout "carllelandtaylor/sio-9-create-app-switcher"
_run task-dir
if [[ "$_OUT" == "$_TMP/tasks/sio-9-create-app-switcher" ]]; then
  pass "task-dir honors tasks_dir for a Linear slug"
else
  fail "task-dir — expected '$_TMP/tasks/sio-9-create-app-switcher', got '$_OUT'"
fi

# ── Case 11: task-dir defaults to facto-tasks when tasks_dir is absent ──────
_write_config linear
_checkout "carllelandtaylor/sio-9-create-app-switcher"
_run task-dir
if [[ "$_OUT" == "$_TMP/facto-tasks/sio-9-create-app-switcher" ]]; then
  pass "task-dir defaults to facto-tasks for a Linear slug"
else
  fail "task-dir — expected '$_TMP/facto-tasks/sio-9-create-app-switcher', got '$_OUT'"
fi

# ── Case 12: task-dir <slug> normalizes an explicit Linear slug ─────────────
_write_config linear
_run task-dir "sio-12-some-work"
if [[ "$_OUT" == "$_TMP/facto-tasks/sio-12-some-work" ]]; then
  pass "task-dir <slug> normalizes an explicit Linear slug"
else
  fail "task-dir sio-12-some-work — expected '$_TMP/facto-tasks/sio-12-some-work', got '$_OUT'"
fi

# ════════════════════════════════════════════════════════════════════════════
# push-plan — the push decision (Issue #116)
# ════════════════════════════════════════════════════════════════════════════
#
# push-plan must key on whether a SAME-NAMED remote branch exists, never on
# @{u}. task-start.sh branches track origin/<main>, so a never-pushed branch
# has an upstream — which the old logic misread as "already pushed" and
# answered with a plain `git push` instead of the first-push with -u.
#
# These cases build real git states against a real bare origin, so ls-remote
# and the pushes are genuine. Each case also RUNS the command push-plan emits
# and asserts it succeeds — a well-formed but unexecutable command is a
# failure, not a pass.

_PP_ROOT="$(mktemp -d)"
trap 'rm -rf "$_TMP" "$_PP_ROOT"' EXIT

# Create a fresh bare origin + clone with a single commit on main.
# Echoes the clone path — and ONLY that: this runs inside $(...), so every
# git command's own chatter is silenced or it would be captured as the path.
# The unique dir comes from mktemp rather than a counter, because a counter
# incremented in a command substitution does not survive back to the caller.
_pp_new_repo() {
  local base origin clone
  base="$(mktemp -d "${_PP_ROOT}/rXXXXXX")"
  origin="${base}/origin.git"
  clone="${base}/clone"
  {
    git init --quiet --bare --initial-branch=main "$origin"
    git init --quiet --initial-branch=main "$clone"
    git -C "$clone" config user.email "test@example.com"
    git -C "$clone" config user.name  "test"
    echo "base" > "$clone/README.md"
    git -C "$clone" add README.md
    git -C "$clone" commit --quiet -m "base"
    git -C "$clone" remote add origin "$origin"
    git -C "$clone" push --quiet -u origin main
  } >/dev/null 2>&1
  echo "$clone"
}

# Run push-plan in $1; capture stdout in _PP_OUT and status in _PP_STATUS.
_pp_run() {
  _PP_OUT="$(cd "$1" && "$_SCRIPT_UNDER_TEST" push-plan 2>/dev/null)"
  _PP_STATUS=$?
}

# Extract one key=value field from _PP_OUT.
_pp_get() {
  printf '%s\n' "$_PP_OUT" | grep "^$1=" | head -1 | cut -d= -f2-
}

# Run the command push-plan emitted, in dir $1. Returns its exit status.
# An empty command is a failure, not a success: `eval ""` exits 0, which would
# let a case that emitted no command at all pass vacuously.
_pp_exec() {
  local dir="$1" cmd="$2"
  [[ -n "$cmd" ]] || return 1
  (cd "$dir" && eval "$cmd") >/dev/null 2>&1
}

# ── Case P1: the Issue #116 state — upstream origin/main, no remote branch ──
# The load-bearing case. --track is exactly what task-start.sh used to do.
_C="$(_pp_new_repo)"
_W="${_C}-wt1"
git -C "$_C" worktree add --quiet --track "$_W" -b feat/x origin/main 2>/dev/null
echo "work" > "$_W/work.txt"
git -C "$_W" add work.txt
git -C "$_W" commit --quiet -m "work"

_UPSTREAM="$(git -C "$_W" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
if [[ "$_UPSTREAM" == "origin/main" ]]; then
  pass "push-plan fixture reproduces the trap (@{u} is origin/main on a never-pushed branch)"
else
  fail "push-plan fixture — expected @{u} to be origin/main, got '$_UPSTREAM'"
fi

_pp_run "$_W"
if [[ "$(_pp_get remote_branch)" == "absent" && "$(_pp_get action)" == "first-push" ]]; then
  pass "push-plan: upstream origin/main + no remote branch => first-push"
else
  fail "push-plan #116 state — expected absent/first-push, got '$(_pp_get remote_branch)'/'$(_pp_get action)'"
fi

_CMD="$(_pp_get command)"
if [[ "$_CMD" == *"-u origin feat/x"* ]]; then
  pass "push-plan: first-push command sets upstream (-u origin feat/x)"
else
  fail "push-plan first-push command — expected '-u origin feat/x', got '$_CMD'"
fi

if _pp_exec "$_W" "$_CMD"; then
  pass "push-plan: first-push command executes successfully"
else
  fail "push-plan first-push command failed to execute: $_CMD"
fi

if [[ -n "$(git -C "$_C" ls-remote --heads origin feat/x)" ]]; then
  pass "push-plan: first-push actually created the remote branch"
else
  fail "push-plan first-push did not create remote branch feat/x"
fi

# ── Case P2: no upstream at all (the post---no-track state) ─────────────────
_C="$(_pp_new_repo)"
_W="${_C}-wt2"
git -C "$_C" worktree add --quiet --no-track "$_W" -b feat/y origin/main 2>/dev/null
echo "work" > "$_W/work.txt"
git -C "$_W" add work.txt
git -C "$_W" commit --quiet -m "work"

if ! git -C "$_W" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  pass "push-plan fixture: --no-track leaves no upstream"
else
  fail "push-plan fixture — --no-track unexpectedly set an upstream"
fi

_pp_run "$_W"
if [[ "$(_pp_get action)" == "first-push" ]]; then
  pass "push-plan: no upstream + no remote branch => first-push"
else
  fail "push-plan no-upstream — expected first-push, got '$(_pp_get action)'"
fi

if _pp_exec "$_W" "$(_pp_get command)"; then
  pass "push-plan: no-upstream first-push command executes successfully"
else
  fail "push-plan no-upstream first-push command failed to execute"
fi

# ── Case P3: fresh branch, zero commits ahead of main ───────────────────────
# The false "Nothing new to put in a PR" case, and task-end.sh's false prompt.
_C="$(_pp_new_repo)"
_W="${_C}-wt3"
git -C "$_C" worktree add --quiet --track "$_W" -b feat/empty origin/main 2>/dev/null

_pp_run "$_W"
if [[ "$(_pp_get action)" == "nothing-to-push" && "$(_pp_get ahead)" == "0" ]]; then
  pass "push-plan: no commits ahead of main => nothing-to-push, ahead=0"
else
  fail "push-plan empty branch — expected nothing-to-push/0, got '$(_pp_get action)'/'$(_pp_get ahead)'"
fi

if [[ -z "$(_pp_get command)" ]]; then
  pass "push-plan: nothing-to-push emits no command"
else
  fail "push-plan nothing-to-push — expected empty command, got '$(_pp_get command)'"
fi

# ── Case P4: remote branch present, local strictly ahead => plain push ──────
_C="$(_pp_new_repo)"
_W="${_C}-wt4"
git -C "$_C" worktree add --quiet --track "$_W" -b feat/ff origin/main 2>/dev/null
echo "one" > "$_W/one.txt"; git -C "$_W" add one.txt; git -C "$_W" commit --quiet -m "one"
git -C "$_W" push --quiet -u origin feat/ff
echo "two" > "$_W/two.txt"; git -C "$_W" add two.txt; git -C "$_W" commit --quiet -m "two"

_pp_run "$_W"
_CMD="$(_pp_get command)"
if [[ "$(_pp_get action)" == "push" ]]; then
  pass "push-plan: remote present + fast-forward => push"
else
  fail "push-plan fast-forward — expected push, got '$(_pp_get action)'"
fi

# An explicit refspec, so push.default cannot redirect this at origin/<main>.
if [[ "$_CMD" == "git push origin feat/ff" ]]; then
  pass "push-plan: fast-forward command names an explicit refspec"
else
  fail "push-plan fast-forward command — expected 'git push origin feat/ff', got '$_CMD'"
fi

if ! printf '%s' "$_CMD" | grep -qE -- '--force'; then
  pass "push-plan: fast-forward command carries no --force of any kind"
else
  fail "push-plan fast-forward command unexpectedly contains --force: $_CMD"
fi

if _pp_exec "$_W" "$_CMD"; then
  pass "push-plan: fast-forward command executes successfully"
else
  fail "push-plan fast-forward command failed to execute: $_CMD"
fi

# ── Case P5: remote branch present, history rewritten => force-with-lease ───
_C="$(_pp_new_repo)"
_W="${_C}-wt5"
git -C "$_C" worktree add --quiet --track "$_W" -b feat/amend origin/main 2>/dev/null
echo "one" > "$_W/one.txt"; git -C "$_W" add one.txt; git -C "$_W" commit --quiet -m "one"
git -C "$_W" push --quiet -u origin feat/amend
_REMOTE_SHA="$(git -C "$_W" ls-remote --heads origin feat/amend | cut -f1)"
git -C "$_W" commit --quiet --amend -m "one amended"

_pp_run "$_W"
_CMD="$(_pp_get command)"
if [[ "$(_pp_get action)" == "force-with-lease" ]]; then
  pass "push-plan: remote present + diverged => force-with-lease"
else
  fail "push-plan diverged — expected force-with-lease, got '$(_pp_get action)'"
fi

# The lease must be the DEFAULT form, leasing against the remote-tracking ref.
# An explicit --force-with-lease=<branch>:<sha> read live from the remote always
# matches, so it can never refuse a push — a bare --force wearing a seatbelt.
if [[ "$_CMD" == "git push --force-with-lease origin feat/amend" ]]; then
  pass "push-plan: lease uses the default form (leases against what we last saw)"
else
  fail "push-plan lease — expected the default --force-with-lease form, got '$_CMD'"
fi

if [[ "$_CMD" != *"--force-with-lease="* ]]; then
  pass "push-plan: lease carries no live-read explicit value"
else
  fail "push-plan lease is pinned to a live-read sha, which can never refuse: $_CMD"
fi

# --force-with-lease is fine; a bare --force is not.
if ! printf '%s' "$_CMD" | grep -qE -- '--force([^-]|$)'; then
  pass "push-plan: diverged command never uses bare --force"
else
  fail "push-plan diverged command uses bare --force: $_CMD"
fi

if _pp_exec "$_W" "$_CMD"; then
  pass "push-plan: force-with-lease command executes successfully"
else
  fail "push-plan force-with-lease command failed to execute: $_CMD"
fi

# ── Case P5b: the lease actually refuses when someone else pushed ──────────
# The case that matters, and the one a hardcoded-stale-sha assertion cannot
# test: run push-plan's OWN emitted command against a branch a second clone
# has moved. If this is ever accepted, the lease is decorative.
_C2="$(_pp_new_repo)"
_W2="${_C2}-race"
git -C "$_C2" worktree add --quiet --track "$_W2" -b feat/race origin/main 2>/dev/null
echo "mine" > "$_W2/mine.txt"; git -C "$_W2" add mine.txt; git -C "$_W2" commit --quiet -m "mine"
git -C "$_W2" push --quiet -u origin feat/race

# A different clone pushes to the same branch behind our back.
_OTHER="${_C2}-other"
git clone --quiet "$(git -C "$_C2" remote get-url origin)" "$_OTHER" 2>/dev/null
git -C "$_OTHER" config user.email "other@example.com"
git -C "$_OTHER" config user.name  "other"
git -C "$_OTHER" checkout --quiet feat/race
echo "theirs" > "$_OTHER/theirs.txt"; git -C "$_OTHER" add theirs.txt
git -C "$_OTHER" commit --quiet -m "theirs"
git -C "$_OTHER" push --quiet origin feat/race

# We rewrite our own history, unaware of their push.
git -C "$_W2" commit --quiet --amend -m "mine amended"

_pp_run "$_W2"
if [[ "$(_pp_get action)" == "force-with-lease" ]]; then
  pass "push-plan: a remote that moved still reads as force-with-lease"
else
  fail "push-plan race — expected force-with-lease, got '$(_pp_get action)'"
fi

if ! _pp_exec "$_W2" "$(_pp_get command)"; then
  pass "push-plan: its own emitted lease REFUSES when the remote moved"
else
  fail "push-plan's emitted command overwrote a commit pushed by someone else"
fi

# And their commit must still be on the remote.
if git -C "$_W2" ls-remote --heads origin feat/race | grep -q "$(git -C "$_OTHER" rev-parse HEAD)"; then
  pass "push-plan: the other clone's commit survived"
else
  fail "push-plan: the other clone's commit was clobbered"
fi

# ── Case P6: remote branch present and identical to HEAD ────────────────────
_C="$(_pp_new_repo)"
_W="${_C}-wt6"
git -C "$_C" worktree add --quiet --track "$_W" -b feat/same origin/main 2>/dev/null
echo "one" > "$_W/one.txt"; git -C "$_W" add one.txt; git -C "$_W" commit --quiet -m "one"
git -C "$_W" push --quiet -u origin feat/same

_pp_run "$_W"
if [[ "$(_pp_get action)" == "nothing-to-push" && "$(_pp_get remote_branch)" == "present" ]]; then
  pass "push-plan: remote present and identical to HEAD => nothing-to-push"
else
  fail "push-plan identical — expected present/nothing-to-push, got '$(_pp_get remote_branch)'/'$(_pp_get action)'"
fi

# ── Case P6b: a remote branch that merely ENDS WITH our name is not ours ───
# `git ls-remote --heads origin <pattern>` matches the TAIL of a ref, so asking
# for "sio-9-app" also returns "refs/heads/carllelandtaylor/sio-9-app" — which
# is precisely the Linear branch convention this project supports. Treating that
# as our branch reports a never-pushed branch as present and answers with a
# force-push over an unrelated branch instead of creating ours.
_C="$(_pp_new_repo)"
_W="${_C}-prefixed"
git -C "$_C" worktree add --quiet --no-track "$_W" -b carllelandtaylor/sio-9-app origin/main 2>/dev/null
echo "theirs" > "$_W/theirs.txt"; git -C "$_W" add theirs.txt
git -C "$_W" commit --quiet -m "theirs"
git -C "$_W" push --quiet origin carllelandtaylor/sio-9-app

# Our branch has the bare name and has never been pushed.
_W2="${_C}-bare"
git -C "$_C" worktree add --quiet --no-track "$_W2" -b sio-9-app origin/main 2>/dev/null
echo "mine" > "$_W2/mine.txt"; git -C "$_W2" add mine.txt
git -C "$_W2" commit --quiet -m "mine"

_pp_run "$_W2"
if [[ "$(_pp_get remote_branch)" == "absent" && "$(_pp_get action)" == "first-push" ]]; then
  pass "push-plan: a prefixed remote branch is not mistaken for ours"
else
  fail "push-plan prefix collision — expected absent/first-push, got '$(_pp_get remote_branch)'/'$(_pp_get action)'"
fi

if _pp_exec "$_W2" "$(_pp_get command)"; then
  pass "push-plan: the bare-named branch is created on the remote"
else
  fail "push-plan prefix collision — emitted command failed to execute"
fi

# Both refs must now exist independently.
if [[ -n "$(git -C "$_W2" ls-remote --heads origin | grep -c 'refs/heads/sio-9-app$')" ]] \
  && git -C "$_W2" ls-remote --heads origin | grep -q 'refs/heads/carllelandtaylor/sio-9-app$'; then
  pass "push-plan: the prefixed branch was left untouched"
else
  fail "push-plan prefix collision — the prefixed branch was disturbed"
fi

# ── Case P7: detached HEAD exits non-zero ──────────────────────────────────
_C="$(_pp_new_repo)"
git -C "$_C" checkout --quiet --detach HEAD 2>/dev/null
_pp_run "$_C"
if [[ "$_PP_STATUS" -ne 0 ]]; then
  pass "push-plan: detached HEAD exits non-zero"
else
  fail "push-plan detached HEAD — expected non-zero exit, got $_PP_STATUS"
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
