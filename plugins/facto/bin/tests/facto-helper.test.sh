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

# ── Tally ───────────────────────────────────────────────────────────────────
echo ""
if [[ "$_FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "$_FAILS test(s) FAILED"
  exit 1
fi
