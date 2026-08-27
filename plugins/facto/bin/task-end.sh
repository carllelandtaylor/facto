#!/bin/bash
# task-end.sh — Clean up a git worktree after a task is done
# Must be SOURCED (not executed) so it can change the caller's CWD.
#
# Usage: source task-end.sh

# --- Preflight checks (no side effects) ---

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: not inside a git repository."
  return 1
fi

# Must be in a worktree, not the main repo
_te_main_repo="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
_te_git_dir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
if [[ "$_te_git_dir" == "$_te_main_repo" ]]; then
  echo "Error: you are in the main repo, not a worktree."
  return 1
fi

_te_worktree_path="$(git rev-parse --show-toplevel)"
_te_branch="$(git rev-parse --abbrev-ref HEAD)"

# --- Handle uncommitted changes ---

if [[ -n "$(git status --short)" ]]; then
  echo "You have uncommitted changes:"
  git status --short
  echo ""
  echo "What would you like to do?"
  echo "  [c] Commit them now"
  echo "  [s] Stash them"
  echo "  [d] Discard them"
  echo "  [a] Abort task-end"
  read -r -p "Choice [c/s/d/a]: " _te_choice
  case "$_te_choice" in
    c|C)
      read -r -p "Commit message: " _te_msg
      git add -A && git commit -m "$_te_msg"
      if [[ $? -ne 0 ]]; then
        echo "Error: commit failed."
        unset _te_main_repo _te_git_dir _te_worktree_path _te_branch _te_choice _te_msg
        return 1
      fi
      ;;
    s|S)
      git stash push -m "task-end stash for ${_te_branch}"
      ;;
    d|D)
      read -r -p "Are you sure you want to discard all changes? [y/N]: " _te_confirm
      if [[ "$_te_confirm" != "y" && "$_te_confirm" != "Y" ]]; then
        echo "Aborted."
        unset _te_main_repo _te_git_dir _te_worktree_path _te_branch _te_choice _te_confirm
        return 1
      fi
      git checkout -- . && git clean -fd
      ;;
    *)
      echo "Aborted."
      unset _te_main_repo _te_git_dir _te_worktree_path _te_branch _te_choice
      return 1
      ;;
  esac
fi

# --- Handle unpushed commits ---

# Ask facto-helper.sh how this branch should be pushed. Do NOT infer it from
# @{upstream}: task-start.sh branches have no upstream now, and older worktrees
# have one pointing at origin/<main>, so neither its presence nor the commit
# count against it says anything about whether this branch exists on the remote
# (Issue #116). push-plan keys on `git ls-remote --heads origin <branch>`.
_te_push_plan="$(facto-helper.sh push-plan 2>/dev/null)"
_te_plan_status=$?

if [[ "$_te_plan_status" -ne 0 ]]; then
  # No origin, detached HEAD, or an unreachable remote. Prompt rather than
  # skip: silently dropping commits during cleanup is the worse failure.
  _te_action="unknown"
  _te_push_cmd="git push -u origin ${_te_branch}"
else
  _te_action="$(printf '%s\n' "$_te_push_plan" | grep '^action=' | cut -d= -f2-)"
  _te_push_cmd="$(printf '%s\n' "$_te_push_plan" | grep '^command=' | cut -d= -f2-)"
fi

_te_has_unpushed=false
if [[ "$_te_action" != "nothing-to-push" ]]; then
  _te_has_unpushed=true
fi

# Never let an empty command through to eval: `eval ""` succeeds, so the push
# would silently do nothing and cleanup would go on to remove the worktree.
if [[ "$_te_has_unpushed" == true && -z "$_te_push_cmd" ]]; then
  _te_push_cmd="git push -u origin ${_te_branch}"
fi

if [[ "$_te_has_unpushed" == true ]]; then
  echo ""
  echo "You have unpushed commits on ${_te_branch}."
  read -r -p "Push before cleaning up? [Y/n]: " _te_push_choice
  if [[ "$_te_push_choice" != "n" && "$_te_push_choice" != "N" ]]; then
    eval "$_te_push_cmd"
    if [[ $? -ne 0 ]]; then
      echo "Error: push failed. Aborting cleanup."
      unset _te_main_repo _te_git_dir _te_worktree_path _te_branch
      unset _te_push_plan _te_plan_status _te_action _te_push_cmd
      unset _te_has_unpushed _te_push_choice
      return 1
    fi
  fi
fi

# --- All checks passed — begin teardown ---

# Find the main repo path from worktree list
_te_main_path="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"

# Check if branch is merged or has a merged PR
_te_delete_branch=false
_te_main_branch="$(git -C "$_te_main_path" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')"

if git -C "$_te_main_path" merge-base --is-ancestor "$_te_branch" "origin/${_te_main_branch}" 2>/dev/null; then
  _te_delete_branch=true
elif command -v gh &>/dev/null; then
  _te_merged_count="$(gh pr list --head "$_te_branch" --state merged --json number --jq 'length' 2>/dev/null)"
  if [[ "$_te_merged_count" -gt 0 ]]; then
    _te_delete_branch=true
  fi
fi

# Run project-specific teardown hook if it exists
if [[ -f "${_te_main_path}/.facto/worktree-teardown.sh" ]]; then
  echo "Running project worktree-teardown hook..."
  bash "${_te_main_path}/.facto/worktree-teardown.sh" "$_te_worktree_path"
fi

# Remove the worktree
cd "$_te_main_path"
git worktree remove "$_te_worktree_path" --force
if [[ $? -ne 0 ]]; then
  echo "Error: failed to remove worktree."
  unset _te_main_repo _te_git_dir _te_worktree_path _te_branch _te_main_path
  unset _te_delete_branch _te_main_branch _te_merged_count
  return 1
fi

# Delete branch if it was merged
if [[ "$_te_delete_branch" == true ]]; then
  git branch -d "$_te_branch" 2>/dev/null
  echo "Deleted merged branch: ${_te_branch}"
else
  echo "Branch ${_te_branch} kept (not yet merged)."
fi

echo ""
echo "Worktree removed. You are now in: $(pwd)"
echo ""

# Clean up temporary variables
unset _te_main_repo _te_git_dir _te_worktree_path _te_branch
unset _te_push_plan _te_plan_status _te_action _te_push_cmd
unset _te_has_unpushed _te_push_choice _te_choice _te_msg _te_confirm
unset _te_main_path _te_delete_branch _te_main_branch _te_merged_count
