#!/bin/bash
# task-start.test.sh — parsing matrix tests for bin/task-start.sh
#
# Sets up a throwaway git repo with stub gh + facto-helper.sh on PATH.
# Each case runs in a subshell so the parent CWD and env are not polluted.
# The stub gh returns a bug label so the expected prefix is always "fix"
# for issue-mode cases.

set -eo pipefail

# --- Resolve the script under test relative to this file's location ---
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SCRIPT_UNDER_TEST="${_TEST_DIR}/../task-start.sh"

if [[ ! -f "$_SCRIPT_UNDER_TEST" ]]; then
  echo "FAIL: script under test not found: $_SCRIPT_UNDER_TEST" >&2
  exit 1
fi

# --- Set up a throwaway git repo ---
_TMP="$(mktemp -d)"

git init --quiet --initial-branch=main "$_TMP"
git -C "$_TMP" config user.email "test@example.com"
git -C "$_TMP" config user.name  "test"
echo "init" > "$_TMP/README.md"
git -C "$_TMP" add README.md
git -C "$_TMP" commit --quiet -m "init"

# Fake a remote so `git fetch origin` and `git remote show origin` work
git -C "$_TMP" remote add origin "$_TMP"
git -C "$_TMP" fetch --quiet origin
git -C "$_TMP" branch -u origin/main main --quiet

# --- Create a temp bin/ dir with stub gh and facto-helper.sh ---
_STUB_BIN="$(mktemp -d)"
trap 'rm -rf "$_STUB_BIN" "$_TMP"' EXIT

# Sentinel file used to verify whether gh was called
_GH_SENTINEL="$_STUB_BIN/.gh_called"

cat > "$_STUB_BIN/gh" <<'STUB'
#!/bin/bash
# Stub gh for task-start.sh tests
touch "$(dirname "$0")/.gh_called"
subcmd="$1"
if [[ "$subcmd" == "issue" && "$2" == "view" ]]; then
  # gh issue view <N> --repo <slug> --json number,title,url,labels
  num="$3"
  echo '{"number":'"$num"',"title":"stub issue title","url":"https://github.com/owner/repo/issues/'"$num"'","labels":[{"name":"bug"}]}'
  exit 0
fi
# All other gh subcommands return empty / {} (best-effort path)
echo '{}'
exit 0
STUB
chmod +x "$_STUB_BIN/gh"

cat > "$_STUB_BIN/facto-helper.sh" <<'STUB'
#!/bin/bash
# Stub facto-helper.sh for task-start.sh tests
subcmd="$1"
if [[ "$subcmd" == "tracker.exists" ]]; then
  exit 0
fi
if [[ "$subcmd" == "tracker.field" ]]; then
  key="$2"
  case "$key" in
    repo)                      echo "owner/repo" ;;
    project.owner)             echo "owner" ;;
    project.number)            echo "1" ;;
    status_field)              echo "Status" ;;
    status_values.in_progress) echo "In progress" ;;
    *) echo "" ;;
  esac
  exit 0
fi
exit 1
STUB
chmod +x "$_STUB_BIN/facto-helper.sh"

# Prepend the stub bin to PATH for child processes
export PATH="$_STUB_BIN:$PATH"

# Helper: clean up worktree + branch created by a test case
_cleanup() {
  local branch="$1"
  local slug
  slug="${branch#*/}"   # strip prefix/
  local wt_dir="$_TMP/.facto/worktrees/$slug"
  git -C "$_TMP" worktree remove --force "$wt_dir" 2>/dev/null || true
  git -C "$_TMP" branch -D "$branch" 2>/dev/null || true
  rm -f "$_GH_SENTINEL"
}

# -----------------------------------------------------------------------
# Case: no_args
# Invocation with zero args returns non-zero, prints usage. Branch list
# unchanged (no new branches should appear).
# -----------------------------------------------------------------------
echo "  testing: no_args"
_branches_before="$(git -C "$_TMP" branch --list | sort)"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" 2>&1 || true)"
_branches_after="$(git -C "$_TMP" branch --list | sort)"
if [[ "$_branches_before" != "$_branches_after" ]]; then
  echo "FAIL: no_args — unexpected branch created" >&2
  exit 1
fi
if ! echo "$_out" | grep -qi "usage"; then
  echo "FAIL: no_args — expected usage message in output, got: $_out" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# Case: bare_description
# `add user login page` → branch feat/UNKNOWN-add-user-login-page
# (no issue → UNKNOWN- slug convention). No notice line printed. gh stub
# NOT called.
# -----------------------------------------------------------------------
echo "  testing: bare_description"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" add user login page 2>&1)"
_branch="feat/UNKNOWN-add-user-login-page"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: bare_description — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if echo "$_out" | grep -qi "Detected issue"; then
  echo "FAIL: bare_description — unexpected notice line in output" >&2
  exit 1
fi
if [[ -f "$_GH_SENTINEL" ]]; then
  echo "FAIL: bare_description — gh was unexpectedly called" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: explicit_flag
# `--issue 123` → branch fix/123-stub-issue-title (prefix from bug label)
# gh WAS called.
# -----------------------------------------------------------------------
echo "  testing: explicit_flag"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --issue 123 2>&1)"
_branch="fix/123-stub-issue-title"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: explicit_flag — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if [[ ! -f "$_GH_SENTINEL" ]]; then
  echo "FAIL: explicit_flag — gh was not called" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: detected_lowercase
# `issue 123` → same branch as explicit_flag. Notice line appears.
# -----------------------------------------------------------------------
echo "  testing: detected_lowercase"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" issue 123 2>&1)"
_branch="fix/123-stub-issue-title"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: detected_lowercase — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if ! echo "$_out" | grep -qF "Detected issue 123 in arguments — using --issue 123."; then
  echo "FAIL: detected_lowercase — expected notice line in output, got:" >&2
  echo "$_out" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: detected_capitalized
# `Issue 123` → same outcome as lowercase case (case-insensitive match)
# -----------------------------------------------------------------------
echo "  testing: detected_capitalized"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" Issue 123 2>&1)"
_branch="fix/123-stub-issue-title"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: detected_capitalized — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if ! echo "$_out" | grep -qF "Detected issue 123 in arguments — using --issue 123."; then
  echo "FAIL: detected_capitalized — expected notice line in output, got:" >&2
  echo "$_out" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: flag_wins
# `--issue 123 issue 456` → branch references issue 123, not 456.
# Notice line does NOT appear (flag short-circuits detection).
# -----------------------------------------------------------------------
echo "  testing: flag_wins"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --issue 123 issue 456 2>&1)"
_branch="fix/123-stub-issue-title"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: flag_wins — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if echo "$_out" | grep -qi "Detected issue"; then
  echo "FAIL: flag_wins — unexpected notice line in output" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: no_detection_when_no_number
# `the issue is hard` → branch feat/UNKNOWN-the-issue-is-hard
# (no issue → UNKNOWN- slug). No notice printed. gh NOT called.
# -----------------------------------------------------------------------
echo "  testing: no_detection_when_no_number"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" the issue is hard 2>&1)"
_branch="feat/UNKNOWN-the-issue-is-hard"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: no_detection_when_no_number — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if echo "$_out" | grep -qi "Detected issue"; then
  echo "FAIL: no_detection_when_no_number — unexpected notice line in output" >&2
  exit 1
fi
if [[ -f "$_GH_SENTINEL" ]]; then
  echo "FAIL: no_detection_when_no_number — gh was unexpectedly called" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: no_detection_when_no_issue_keyword
# `fix bug 42 in parser` → branch fix/UNKNOWN-fix-bug-42-in-parser
# (existing keyword path picks "fix"; no issue → UNKNOWN- slug). No
# notice printed.
# -----------------------------------------------------------------------
echo "  testing: no_detection_when_no_issue_keyword"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" fix bug 42 in parser 2>&1)"
_branch="fix/UNKNOWN-fix-bug-42-in-parser"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: no_detection_when_no_issue_keyword — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if echo "$_out" | grep -qi "Detected issue"; then
  echo "FAIL: no_detection_when_no_issue_keyword — unexpected notice line in output" >&2
  exit 1
fi
if [[ -f "$_GH_SENTINEL" ]]; then
  echo "FAIL: no_detection_when_no_issue_keyword — gh was unexpectedly called" >&2
  exit 1
fi
_cleanup "$_branch"

echo "PASS: task-start parsing matrix"
