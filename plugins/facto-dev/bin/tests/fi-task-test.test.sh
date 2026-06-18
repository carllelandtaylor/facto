#!/bin/bash
# fi-task-test.test.sh — sandbox tests for bin/fi-task-test.sh
#
# fi-task-test.sh re-points the factory's two install symlinks
#     ~/.claude/skills/facto      -> <checkout>/plugins/facto
#     ~/.claude/skills/facto-dev  -> <checkout>/plugins/facto-dev
# at either a worktree (link mode) or the main checkout (reset mode).
#
# To exercise it without clobbering the developer's REAL install, every script
# invocation runs under a throwaway HOME, so the script's
# SKILLS_DIR="$HOME/.claude/skills" lands in a sandbox dir we own.
#
# Builds throwaway git repos (with a local bare remote so `fetch` / origin/main
# work offline) and exercises the behaviours: link, reset, precondition failure
# (dirty / wrong-branch main aborts), and the factory-repo guard.

set -uo pipefail  # not -e: we want to run every case and tally failures

# --- Resolve the script under test relative to this file's location ---
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SCRIPT="${_TEST_DIR}/../fi-task-test.sh"

if [[ ! -f "$_SCRIPT" ]]; then
  echo "FAIL: script under test not found: $_SCRIPT" >&2
  exit 1
fi

# --- A throwaway HOME so the install symlinks land in a sandbox skills dir ---
FAKE_HOME="$(mktemp -d)"
SANDBOX_SKILLS="$FAKE_HOME/.claude/skills"

_FAILS=0
_TMPS=("$FAKE_HOME")
trap 'for d in "${_TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; _FAILS=$((_FAILS + 1)); }

# realpath of a dir, resolving symlinked path components (mktemp may live under
# a symlink), so target comparisons are robust.
_realdir() { (cd "$1" 2>/dev/null && pwd -P); }

# run <dir> — invoke the script from <dir> under the sandbox HOME. Discards
# output; the caller inspects the exit code via $?.
run() { ( cd "$1" && HOME="$FAKE_HOME" "$_SCRIPT" ) >/dev/null 2>&1; }

# install_links_point_at <root> — true if BOTH sandbox install symlinks are
# symlinks resolving to <root>/plugins/{facto,facto-dev}.
install_links_point_at() {
  local root="$1" p
  for p in facto facto-dev; do
    [[ -L "$SANDBOX_SKILLS/$p" ]] || return 1
    [[ "$(_realdir "$SANDBOX_SKILLS/$p")" == "$(_realdir "$root/plugins/$p")" ]] || return 1
  done
  return 0
}

# marker_reads <expected> — true if BOTH plugin markers resolved through the
# sandbox install symlinks contain <expected>.
marker_reads() {
  local expected="$1" p
  for p in facto facto-dev; do
    [[ "$(cat "$SANDBOX_SKILLS/$p/marker.txt" 2>/dev/null)" == "$expected" ]] || return 1
  done
  return 0
}

# make_repo <yes|no> <marker> — create a repo; "yes" tracks plugins/facto and
# plugins/facto-dev (the factory structure), each with a marker file. Prints the
# repo path then its bare-remote path, one per line.
make_repo() {
  local with_plugins="$1" marker="$2" tmp p
  tmp="$(mktemp -d)"
  git init --quiet --initial-branch=main "$tmp"
  git -C "$tmp" config user.email "test@example.com"
  git -C "$tmp" config user.name "test"
  echo "init" > "$tmp/README.md"
  # Mirror the real factory repo: worktrees live under .facto/worktrees/ and
  # must be gitignored, otherwise they'd show as untracked in the main checkout.
  echo ".facto/worktrees/" > "$tmp/.gitignore"
  if [[ "$with_plugins" == "yes" ]]; then
    for p in facto facto-dev; do
      mkdir -p "$tmp/plugins/$p/skills"
      echo "$marker" > "$tmp/plugins/$p/marker.txt"
    done
  fi
  git -C "$tmp" add -A
  git -C "$tmp" commit --quiet -m "init"
  # A separate bare repo as origin, so origin's HEAD stays 'main' regardless of
  # which branch the working checkout is on (the script reads the default branch
  # from `git remote show origin`). Using the repo as its own remote would make
  # the reported HEAD follow the checkout, defeating the wrong-branch test.
  local bare="${tmp}.git"
  git clone --quiet --bare "$tmp" "$bare"
  git -C "$tmp" remote add origin "$bare"
  git -C "$tmp" fetch --quiet origin
  git -C "$tmp" branch -u origin/main main --quiet
  printf '%s\n%s\n' "$tmp" "$bare"
}

# add_worktree <repo> <slug> <marker> — add a worktree and stamp its plugins
# with <marker> (simulating in-progress, uncommitted edits). Prints the path.
add_worktree() {
  local repo="$1" slug="$2" marker="$3" wt p
  wt="$repo/.facto/worktrees/$slug"
  git -C "$repo" worktree add --quiet -b "feat/$slug" "$wt" main
  for p in facto facto-dev; do
    mkdir -p "$wt/plugins/$p"
    echo "$marker" > "$wt/plugins/$p/marker.txt"
  done
  printf '%s\n' "$wt"
}

# ── Setup: factory-like repo with a worktree ─────────────────────────────────
{ read -r REPO; read -r REPO_BARE; } < <(make_repo yes main-version); _TMPS+=("$REPO" "$REPO_BARE")
WT="$(add_worktree "$REPO" "158-demo" "worktree-version")"

# ── Case 1: link (run from the worktree) ─────────────────────────────────────
run "$WT"
if install_links_point_at "$WT" && marker_reads "worktree-version"; then
  pass "link: install symlinks resolve to <worktree>/plugins/{facto,facto-dev}"
else
  fail "link: expected install symlinks -> <worktree>/plugins/* with worktree content"
fi

# ── Case 2: reset (run from the main checkout) ───────────────────────────────
run "$REPO"
if install_links_point_at "$REPO" && marker_reads "main-version"; then
  pass "reset: install symlinks restored to <main>/plugins/{facto,facto-dev}"
else
  fail "reset: expected install symlinks -> <main>/plugins/* with main content"
fi

# ── Case 3: precondition — dirty main aborts, install links unchanged ─────────
# After Case 2 the links point at main; a failed link must leave them there.
echo "dirty" >> "$REPO/README.md"
run "$WT"; rc=$?
if [[ $rc -ne 0 ]] && install_links_point_at "$REPO"; then
  pass "precondition: dirty main checkout aborts the link"
else
  fail "precondition: dirty main should abort and leave links at main (rc=$rc)"
fi
git -C "$REPO" checkout -- README.md

# ── Case 4: precondition — main on a non-default branch aborts ───────────────
git -C "$REPO" checkout -b scratch --quiet
run "$WT"; rc=$?
if [[ $rc -ne 0 ]] && install_links_point_at "$REPO"; then
  pass "precondition: main off the default branch aborts the link"
else
  fail "precondition: main off default branch should abort (rc=$rc)"
fi
git -C "$REPO" checkout main --quiet

# ── Case 5: factory guard — repo with no tracked plugins/ dirs is refused ────
{ read -r REPO2; read -r REPO2_BARE; } < <(make_repo no ""); _TMPS+=("$REPO2" "$REPO2_BARE")
WT2="$(add_worktree "$REPO2" "1-x" "x")"
run "$WT2"; rc=$?
if [[ $rc -ne 0 ]]; then
  pass "guard: repo without tracked plugins/{facto,facto-dev} is refused"
else
  fail "guard: non-factory repo should be refused (rc=$rc)"
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
