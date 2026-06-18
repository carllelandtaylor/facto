#!/bin/bash
# task-list.test.sh — snapshot test for bin/task-list.sh
#
# Sets up a throwaway git repo with two fake worktree directories
# (added in reverse alphabetical order to prove the sort), sources
# task-list.sh, and diffs stdout against an expected snapshot.

set -eo pipefail

# --- Resolve the script under test relative to this file's location ---
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SCRIPT_UNDER_TEST="${_TEST_DIR}/../task-list.sh"

if [[ ! -f "$_SCRIPT_UNDER_TEST" ]]; then
  echo "FAIL: script under test not found: $_SCRIPT_UNDER_TEST" >&2
  exit 1
fi

# --- Set up a throwaway repo with two fake worktrees ---
_TMP="$(mktemp -d)"
trap 'rm -rf "$_TMP"' EXIT

cd "$_TMP"
git init --quiet --initial-branch=main
git config user.email "test@example.com"
git config user.name  "test"
echo "init" > README.md
git add README.md
git commit --quiet -m "init"

mkdir -p "$_TMP/.facto/worktrees"

# Add in reverse alphabetical order so the sort test is meaningful.
git worktree add --quiet -b feat/zebra-task "$_TMP/.facto/worktrees/zebra-task" main
git worktree add --quiet -b feat/alpha-task "$_TMP/.facto/worktrees/alpha-task" main

# --- Source task-list.sh from inside one of the worktrees and capture stdout ---
cd "$_TMP/.facto/worktrees/zebra-task"
ACTUAL="$(source "$_SCRIPT_UNDER_TEST")"

# --- Expected snapshot (interpolate the temp dir so paths match) ---
EXPECTED="Name: alpha-task
  Path: ${_TMP}/.facto/worktrees/alpha-task
  Branch: feat/alpha-task

Name: zebra-task
  Path: ${_TMP}/.facto/worktrees/zebra-task
  Branch: feat/zebra-task
"

# --- Diff and report ---
if ! diff -u <(printf '%s' "$EXPECTED") <(printf '%s\n' "$ACTUAL") > /tmp/task-list-test.diff 2>&1; then
  echo "FAIL: task-list output did not match expected snapshot" >&2
  echo "--- diff (expected vs actual) ---" >&2
  cat /tmp/task-list-test.diff >&2
  exit 1
fi

echo "PASS: task-list snapshot matches expected output"
