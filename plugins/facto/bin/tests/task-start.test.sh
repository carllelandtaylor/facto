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
# Stub facto-helper.sh for task-start.sh tests.
#
# Which tracker it reports is switchable per case via _TS_TEST_TRACKER, so the
# GitHub and Linear cases share one stub. Unset means github-issues, matching
# the script's own default.
subcmd="$1"
tracker="${_TS_TEST_TRACKER:-github-issues}"
if [[ "$subcmd" == "tracker.exists" ]]; then
  exit 0
fi
if [[ "$subcmd" == "tracker.field" ]]; then
  key="$2"
  if [[ "$tracker" == "linear" ]]; then
    case "$key" in
      type)                 echo "linear" ;;
      branch_prefix)        echo "carllelandtaylor" ;;
      branch_issue_pattern) echo '^[^/]+/(?<issue>[a-z][a-z0-9]*-[0-9]+)-' ;;
      *) echo "" ;;
    esac
    exit 0
  fi
  case "$key" in
    type)                      echo "github-issues" ;;
    repo)                      echo "owner/repo" ;;
    project.owner)             echo "owner" ;;
    project.number)            echo "1" ;;
    status_field)              echo "Status" ;;
    status_values.in_progress) echo "In progress" ;;
    branch_issue_pattern)      echo '^[a-z]+/(?<issue>[0-9]+)-' ;;
    *) echo "" ;;
  esac
  exit 0
fi
exit 1
STUB
chmod +x "$_STUB_BIN/facto-helper.sh"

# Prepend the stub bin to PATH for child processes
export PATH="$_STUB_BIN:$PATH"

# Helper: clean up worktree + branch created by a test case.
# The worktree slug is normally the branch minus its leading segment, but the
# UNKNOWN- convention makes them differ, so it can be passed explicitly. Getting
# this wrong leaves a checked-out branch that `git branch -D` then refuses to
# delete, so the override is load-bearing rather than cosmetic.
_cleanup() {
  local branch="$1"
  local slug="${2:-${branch#*/}}"
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

# =======================================================================
# Linear tracker cases
#
# On a Linear repo task-start never reaches the tracker: Linear is an MCP
# server and bash cannot call it. Every case below therefore asserts that
# the gh stub was NOT invoked, in addition to the branch it produced.
# =======================================================================

export _TS_TEST_TRACKER="linear"

# -----------------------------------------------------------------------
# Case: linear_branch_flag
# `--branch carllelandtaylor/sio-9-create-app-switcher` → that branch
# verbatim, slug sio-9-create-app-switcher (leading segment stripped, no
# UNKNOWN- prefix since the identifier matches). gh NOT called.
# -----------------------------------------------------------------------
echo "  testing: linear_branch_flag"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch carllelandtaylor/sio-9-create-app-switcher 2>&1)"
_branch="carllelandtaylor/sio-9-create-app-switcher"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: linear_branch_flag — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if [[ ! -d "$_TMP/.facto/worktrees/sio-9-create-app-switcher" ]]; then
  echo "FAIL: linear_branch_flag — worktree dir 'sio-9-create-app-switcher' not found" >&2
  exit 1
fi
if [[ -f "$_GH_SENTINEL" ]]; then
  echo "FAIL: linear_branch_flag — gh was unexpectedly called" >&2
  exit 1
fi
# task.json must carry the identifier as a JSON *string*, uppercased.
_task_json="$(cd "$_TMP/.facto/worktrees/sio-9-create-app-switcher" && git rev-parse --absolute-git-dir)/task.json"
if [[ ! -f "$_task_json" ]]; then
  echo "FAIL: linear_branch_flag — task.json not written at $_task_json" >&2
  exit 1
fi
if [[ "$(jq -r '.issue_number' "$_task_json")" != "SIO-9" ]]; then
  echo "FAIL: linear_branch_flag — expected issue_number 'SIO-9', got '$(jq -r '.issue_number' "$_task_json")'" >&2
  exit 1
fi
if [[ "$(jq -r '.issue_number | type' "$_task_json")" != "string" ]]; then
  echo "FAIL: linear_branch_flag — issue_number must be a JSON string, got $(jq -r '.issue_number | type' "$_task_json")" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: linear_branch_flag_no_match
# A branch name that matches no identifier is not an error — it warns and
# starts a no-issue task, so the slug takes the UNKNOWN- prefix.
# -----------------------------------------------------------------------
echo "  testing: linear_branch_flag_no_match"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch scratch/poke-at-something 2>&1)"
_branch="scratch/poke-at-something"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: linear_branch_flag_no_match — branch '$_branch' not found" >&2
  exit 1
fi
if [[ ! -d "$_TMP/.facto/worktrees/UNKNOWN-poke-at-something" ]]; then
  echo "FAIL: linear_branch_flag_no_match — expected UNKNOWN- worktree dir" >&2
  ls "$_TMP/.facto/worktrees" >&2
  exit 1
fi
if ! echo "$_out" | grep -qi "does not match"; then
  echo "FAIL: linear_branch_flag_no_match — expected a warning, got: $_out" >&2
  exit 1
fi
_cleanup "$_branch" "UNKNOWN-poke-at-something"

# -----------------------------------------------------------------------
# Case: linear_branch_flag_multi_segment
# Linear's branch format is workspace-configurable and may carry more than one
# leading segment. The default pattern allows exactly one, so such a name
# recovers no identifier and correctly falls back to a no-issue task. What is
# asserted here is that the resulting slug stays a FLAT directory name: taking
# only the last segment keeps it equal to the worktree basename, which is what
# facto-helper.sh task-slug reads back. Stripping just the first segment would
# yield "UNKNOWN-feature/sio-12-nested-name" and nest a directory whose
# basename no longer matches the slug.
# -----------------------------------------------------------------------
echo "  testing: linear_branch_flag_multi_segment"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch carllelandtaylor/feature/sio-12-nested-name 2>&1)"
_branch="carllelandtaylor/feature/sio-12-nested-name"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: linear_branch_flag_multi_segment — branch '$_branch' not found" >&2
  exit 1
fi
if [[ ! -d "$_TMP/.facto/worktrees/UNKNOWN-sio-12-nested-name" ]]; then
  echo "FAIL: linear_branch_flag_multi_segment — expected flat worktree dir 'UNKNOWN-sio-12-nested-name'" >&2
  ls -R "$_TMP/.facto/worktrees" >&2
  exit 1
fi
if [[ -d "$_TMP/.facto/worktrees/UNKNOWN-feature" ]]; then
  echo "FAIL: linear_branch_flag_multi_segment — slug nested a directory (UNKNOWN-feature/...)" >&2
  exit 1
fi
_cleanup "$_branch" "UNKNOWN-sio-12-nested-name"

# -----------------------------------------------------------------------
# Case: linear_issue_flag
# `--issue SIO-9 create app switcher` rebuilds the same branch name Linear
# would generate, from branch_prefix + lowercased identifier + slug.
# -----------------------------------------------------------------------
echo "  testing: linear_issue_flag"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --issue SIO-9 create app switcher 2>&1)"
_branch="carllelandtaylor/sio-9-create-app-switcher"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: linear_issue_flag — branch '$_branch' not found" >&2
  git -C "$_TMP" branch --list >&2
  exit 1
fi
if [[ -f "$_GH_SENTINEL" ]]; then
  echo "FAIL: linear_issue_flag — gh was unexpectedly called" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: linear_issue_flag_lowercase
# The identifier is uppercased before use, so a lowercased one produces the
# identical branch.
# -----------------------------------------------------------------------
echo "  testing: linear_issue_flag_lowercase"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --issue sio-9 create app switcher 2>&1)"
_branch="carllelandtaylor/sio-9-create-app-switcher"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: linear_issue_flag_lowercase — branch '$_branch' not found" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: linear_issue_flag_needs_words
# Without a fetch there is no title, so description words are required.
# -----------------------------------------------------------------------
echo "  testing: linear_issue_flag_needs_words"
_branches_before="$(git -C "$_TMP" branch --list | sort)"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --issue SIO-9 2>&1 || true)"
_branches_after="$(git -C "$_TMP" branch --list | sort)"
if [[ "$_branches_before" != "$_branches_after" ]]; then
  echo "FAIL: linear_issue_flag_needs_words — unexpected branch created" >&2
  exit 1
fi
if ! echo "$_out" | grep -qi "requires description words"; then
  echo "FAIL: linear_issue_flag_needs_words — expected the words error, got: $_out" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# Case: linear_rejects_bare_number
# A GitHub-style issue number is not a valid Linear identifier.
# -----------------------------------------------------------------------
echo "  testing: linear_rejects_bare_number"
_branches_before="$(git -C "$_TMP" branch --list | sort)"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --issue 123 some words 2>&1 || true)"
_branches_after="$(git -C "$_TMP" branch --list | sort)"
if [[ "$_branches_before" != "$_branches_after" ]]; then
  echo "FAIL: linear_rejects_bare_number — unexpected branch created" >&2
  exit 1
fi
if ! echo "$_out" | grep -qi "must be an identifier"; then
  echo "FAIL: linear_rejects_bare_number — expected the identifier error, got: $_out" >&2
  exit 1
fi

unset _TS_TEST_TRACKER

# -----------------------------------------------------------------------
# Case: branch_and_issue_are_exclusive
# Tracker-independent: the two flags name different things and cannot be
# reconciled, so supplying both is an error rather than a precedence rule.
# -----------------------------------------------------------------------
echo "  testing: branch_and_issue_are_exclusive"
_branches_before="$(git -C "$_TMP" branch --list | sort)"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch some/branch --issue 123 2>&1 || true)"
_branches_after="$(git -C "$_TMP" branch --list | sort)"
if [[ "$_branches_before" != "$_branches_after" ]]; then
  echo "FAIL: branch_and_issue_are_exclusive — unexpected branch created" >&2
  exit 1
fi
if ! echo "$_out" | grep -qi "mutually exclusive"; then
  echo "FAIL: branch_and_issue_are_exclusive — expected the exclusivity error, got: $_out" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# Case: branch_flag_requires_value
# -----------------------------------------------------------------------
echo "  testing: branch_flag_requires_value"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch 2>&1 || true)"
if ! echo "$_out" | grep -qi "requires a value"; then
  echo "FAIL: branch_flag_requires_value — expected the missing-value error, got: $_out" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# Case: github_branch_flag
# --branch is tracker-independent: on a GitHub repo it names the branch
# directly and still recovers the issue number from the name.
# -----------------------------------------------------------------------
echo "  testing: github_branch_flag"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch feat/42-some-github-work 2>&1)"
_branch="feat/42-some-github-work"
if ! git -C "$_TMP" branch --list | grep -qF "$_branch"; then
  echo "FAIL: github_branch_flag — branch '$_branch' not found" >&2
  exit 1
fi
if [[ ! -d "$_TMP/.facto/worktrees/42-some-github-work" ]]; then
  echo "FAIL: github_branch_flag — expected worktree dir '42-some-github-work'" >&2
  exit 1
fi
_task_json="$(cd "$_TMP/.facto/worktrees/42-some-github-work" && git rev-parse --absolute-git-dir)/task.json"
if [[ "$(jq -r '.issue_number | type' "$_task_json")" != "number" ]]; then
  echo "FAIL: github_branch_flag — GitHub issue_number must stay a JSON number, got $(jq -r '.issue_number | type' "$_task_json")" >&2
  exit 1
fi
_cleanup "$_branch"

# -----------------------------------------------------------------------
# Case: no_upstream
# The worktree must be created with NO upstream. Branching from a
# remote-tracking ref auto-sets one (branch.autoSetupMerge=true), and that
# upstream would be origin/<main> — a branch that this one is not a copy of.
# facto:pr read exactly that as proof the branch had already been pushed
# (Issue #116), so --no-track is load-bearing, not cosmetic.
# -----------------------------------------------------------------------
echo "  testing: no_upstream"
rm -f "$_GH_SENTINEL"
_out="$(cd "$_TMP" && source "$_SCRIPT_UNDER_TEST" --branch feat/77-no-upstream-check 2>&1)"
_branch="feat/77-no-upstream-check"
_wt="$_TMP/.facto/worktrees/77-no-upstream-check"
if [[ ! -d "$_wt" ]]; then
  echo "FAIL: no_upstream — expected worktree dir '$_wt'" >&2
  exit 1
fi
if git -C "$_wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo "FAIL: no_upstream — worktree has an upstream ($(git -C "$_wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}')); --track must not come back" >&2
  exit 1
fi
_cleanup "$_branch"

echo "PASS: task-start parsing matrix"
