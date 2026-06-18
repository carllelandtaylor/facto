#!/bin/bash
# task-list.sh — List all active task worktrees
# Must be SOURCED (not executed) for consistency with task-start.sh / task-end.sh.
#
# Usage: source task-list.sh

# --- Preflight checks (no side effects) ---

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: not inside a git repository."
  return 1
fi

# --- Resolve main repo root ---

_tl_repo_root="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
_tl_worktree_prefix="${_tl_repo_root}/.facto/worktrees/"
_tl_entries=""
_tl_path=""
_tl_branch=""

# --- Parse git worktree list --porcelain ---
# Use process substitution to avoid a subshell so variables persist.

while IFS= read -r _tl_line || [[ -n "$_tl_line" ]]; do
  case "$_tl_line" in
    worktree\ *)
      _tl_path="${_tl_line#worktree }"
      _tl_branch=""
      ;;
    branch\ *)
      _tl_branch="${_tl_line#branch refs/heads/}"
      ;;
    "")
      # Blank line marks end of a worktree entry
      if [[ -n "$_tl_path" && "$_tl_path" == "${_tl_worktree_prefix}"* ]]; then
        _tl_name="$(basename "$_tl_path")"
        _tl_entries="${_tl_entries}${_tl_name}"$'\t'"${_tl_path}"$'\t'"${_tl_branch}"$'\n'
      fi
      _tl_path=""
      _tl_branch=""
      ;;
  esac
done < <(git worktree list --porcelain)

# Handle the last entry (porcelain output may not end with a blank line)
if [[ -n "$_tl_path" && "$_tl_path" == "${_tl_worktree_prefix}"* ]]; then
  _tl_name="$(basename "$_tl_path")"
  _tl_entries="${_tl_entries}${_tl_name}"$'\t'"${_tl_path}"$'\t'"${_tl_branch}"$'\n'
fi

if [[ -n "$_tl_entries" ]]; then
  printf '%s' "$_tl_entries" | sort | while IFS=$'\t' read -r _tl_n _tl_p _tl_b; do
    echo "Name: $_tl_n"
    echo "  Path: $_tl_p"
    echo "  Branch: $_tl_b"
    echo ""
  done
else
  echo "No active tasks."
fi

# --- Clean up temporary variables ---

unset _tl_repo_root _tl_worktree_prefix _tl_entries
unset _tl_path _tl_branch _tl_line _tl_name _tl_n _tl_p _tl_b
