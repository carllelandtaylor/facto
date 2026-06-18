#!/bin/bash
# task-start.sh — Create a git worktree for a new task
# Must be SOURCED (not executed) so it can change the caller's CWD.
#
# Usage:
#   source task-start.sh <description words...>
#   source task-start.sh --issue <number|url> [extra description...]
#
# Examples:
#   source task-start.sh add user login page
#   source task-start.sh --issue 86
#   source task-start.sh --issue https://github.com/owner/repo/issues/86

# --- Preflight checks (no side effects) ---

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: not inside a git repository."
  return 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: source task-start.sh <description...>"
  echo "       source task-start.sh --issue <number|url> [extra description...]"
  return 1
fi

# --- Parse --issue flag ---

_ts_issue_input=""
_ts_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --issue requires a value (issue number or URL)."
        unset _ts_issue_input _ts_args
        return 1
      fi
      _ts_issue_input="$2"
      shift 2
      ;;
    *)
      _ts_args+=("$1")
      shift
      ;;
  esac
done
set -- "${_ts_args[@]}"

# --- Detect a literal "issue N" token sequence in positional args ---
# If the developer wrote `task-start issue 123` instead of
# `task-start --issue 123`, promote the first matching "issue <number>"
# to issue mode. Case-insensitive; first match wins. The matched two
# tokens are removed from _ts_args for hygiene.
if [[ -z "$_ts_issue_input" ]]; then
  _ts_filtered_args=()
  _ts_skip_next=0
  for ((_ts_i = 0; _ts_i < ${#_ts_args[@]}; _ts_i++)); do
    if (( _ts_skip_next )); then
      _ts_skip_next=0
      continue
    fi
    _ts_tok="${_ts_args[$_ts_i]}"
    _ts_next="${_ts_args[$((_ts_i + 1))]:-}"
    if [[ -z "$_ts_issue_input" \
          && "${_ts_tok,,}" == "issue" \
          && "$_ts_next" =~ ^[0-9]+$ ]]; then
      _ts_issue_input="$_ts_next"
      _ts_skip_next=1
      echo "Detected issue ${_ts_issue_input} in arguments — using --issue ${_ts_issue_input}."
      continue
    fi
    _ts_filtered_args+=("$_ts_tok")
  done
  _ts_args=("${_ts_filtered_args[@]}")
  set -- "${_ts_args[@]}"
  unset _ts_filtered_args _ts_skip_next _ts_i _ts_tok _ts_next
fi

# --- Issue-mode setup (resolves Issue + locks branch prefix from labels) ---

_ts_issue_number=""
_ts_issue_url=""
_ts_issue_title=""
_ts_issue_labels_json=""

if [[ -n "$_ts_issue_input" ]]; then
  if ! command -v facto-helper.sh >/dev/null 2>&1; then
    echo "Error: --issue requires facto-helper.sh on PATH."
    unset _ts_issue_input _ts_args
    return 1
  fi

  if ! facto-helper.sh tracker.exists; then
    echo "Error: --issue requires .facto/settings.json with a tracker section in the host repo."
    unset _ts_issue_input _ts_args
    return 1
  fi

  _ts_repo_slug="$(facto-helper.sh tracker.field repo)"
  if [[ -z "$_ts_repo_slug" ]]; then
    echo "Error: could not resolve tracker repo via facto-helper.sh."
    unset _ts_issue_input _ts_args _ts_repo_slug
    return 1
  fi

  # Extract numeric issue number from either a bare number or a URL
  if [[ "$_ts_issue_input" =~ ^[0-9]+$ ]]; then
    _ts_issue_number="$_ts_issue_input"
  elif [[ "$_ts_issue_input" =~ /issues/([0-9]+) ]]; then
    _ts_issue_number="${BASH_REMATCH[1]}"
  else
    echo "Error: --issue must be an issue number or a URL containing /issues/<number>."
    unset _ts_issue_input _ts_args _ts_repo_slug
    return 1
  fi

  _ts_issue_json="$(gh issue view "$_ts_issue_number" --repo "$_ts_repo_slug" --json number,title,url,labels 2>/dev/null)"
  if [[ -z "$_ts_issue_json" ]]; then
    echo "Error: could not fetch Issue #$_ts_issue_number from $_ts_repo_slug."
    unset _ts_issue_input _ts_args _ts_repo_slug _ts_issue_number _ts_issue_json
    return 1
  fi

  _ts_issue_title="$(echo "$_ts_issue_json" | jq -r .title)"
  _ts_issue_url="$(echo "$_ts_issue_json" | jq -r .url)"
  _ts_issue_labels_json="$(echo "$_ts_issue_json" | jq -c '[.labels[].name]')"
fi

# --- All checks passed — begin actions ---

# Combine optional extra description words with issue title (in issue mode) or
# the bare description (no-issue mode).
if [[ -n "$_ts_issue_number" ]]; then
  _ts_description="$_ts_issue_title"
else
  _ts_description="$*"
fi

# Use --git-common-dir to always resolve to the main repo, not a worktree
_ts_repo_root="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"

# Fetch latest and detect main branch
git fetch origin --quiet
_ts_main_branch="$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')"
if [[ -z "$_ts_main_branch" ]]; then
  echo "Error: could not detect main branch from origin."
  return 1
fi

# Infer branch prefix
_ts_prefix="feat"
if [[ -n "$_ts_issue_number" ]] && echo "$_ts_issue_labels_json" | jq -e 'any(test("^bug"; "i"))' >/dev/null 2>&1; then
  # Any label starting with "bug" (case-insensitive) selects fix/
  _ts_prefix="fix"
else
  case "${_ts_description,,}" in
    fix*|bug*|patch*) _ts_prefix="fix" ;;
    chore*|cleanup*|refactor*) _ts_prefix="chore" ;;
    doc*|docs*|readme*) _ts_prefix="docs" ;;
    test*|spec*) _ts_prefix="test" ;;
  esac
fi

# Slugify the description
_ts_title_slug="$(echo "$_ts_description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)"

if [[ -n "$_ts_issue_number" ]]; then
  _ts_slug="${_ts_issue_number}-${_ts_title_slug}"
else
  # No issue: prefix "UNKNOWN-" where the issue number would go, so a missing
  # issue is explicit rather than looking like a slug whose number was dropped.
  _ts_slug="UNKNOWN-${_ts_title_slug}"
fi

_ts_branch="${_ts_prefix}/${_ts_slug}"

# Create worktree directory
_ts_worktree_dir="${_ts_repo_root}/.facto/worktrees/${_ts_slug}"
mkdir -p "$(dirname "$_ts_worktree_dir")"

git worktree add --track "$_ts_worktree_dir" -b "$_ts_branch" "origin/${_ts_main_branch}" --quiet
if [[ $? -ne 0 ]]; then
  echo "Error: failed to create worktree."
  return 1
fi

# Write task.json + set Status -> In progress when --issue was supplied.
# Both are best-effort — failures warn and continue; worktree creation is the
# primary deliverable.
if [[ -n "$_ts_issue_number" ]]; then
  _ts_task_path="$(cd "$_ts_worktree_dir" && git rev-parse --git-path task.json)"
  # git rev-parse may return a path relative to the worktree's cwd; absolutize.
  if [[ "$_ts_task_path" != /* ]]; then
    _ts_task_path="$(cd "$_ts_worktree_dir" && cd "$(dirname "$_ts_task_path")" && pwd)/$(basename "$_ts_task_path")"
  fi
  jq -n \
    --argjson n "$_ts_issue_number" \
    --arg url "$_ts_issue_url" \
    --arg title "$_ts_issue_title" \
    --arg started "$(date -Iseconds)" \
    '{ issue_number: $n, issue_url: $url, issue_title: $title, started_at: $started }' \
    > "$_ts_task_path" \
    || echo "Warning: could not write task.json at $_ts_task_path"

  # Status -> In progress (best effort)
  _ts_project_owner="$(facto-helper.sh tracker.field project.owner)"
  _ts_project_number="$(facto-helper.sh tracker.field project.number)"
  _ts_status_field_name="$(facto-helper.sh tracker.field status_field)"
  _ts_in_progress_name="$(facto-helper.sh tracker.field status_values.in_progress)"

  _ts_project_id="$(gh project view "$_ts_project_number" --owner "$_ts_project_owner" --format json 2>/dev/null | jq -r .id)"
  _ts_status_field_json="$(gh project field-list "$_ts_project_number" --owner "$_ts_project_owner" --format json 2>/dev/null \
    | jq --arg name "$_ts_status_field_name" '.fields[] | select(.name == $name)')"
  _ts_status_field_id="$(echo "$_ts_status_field_json" | jq -r .id)"
  _ts_in_progress_id="$(echo "$_ts_status_field_json" | jq -r --arg n "$_ts_in_progress_name" '.options[] | select(.name == $n) | .id')"

  _ts_item_id="$(gh project item-list "$_ts_project_number" --owner "$_ts_project_owner" --format json --limit 200 2>/dev/null \
    | jq -r --argjson num "$_ts_issue_number" '.items[] | select(.content.type == "Issue" and .content.number == $num) | .id')"

  if [[ -z "$_ts_item_id" ]]; then
    _ts_item_id="$(gh project item-add "$_ts_project_number" --owner "$_ts_project_owner" \
      --url "https://github.com/${_ts_repo_slug}/issues/${_ts_issue_number}" \
      --format json 2>/dev/null | jq -r .id)"
  fi

  if [[ -n "$_ts_project_id" && -n "$_ts_item_id" && -n "$_ts_status_field_id" && -n "$_ts_in_progress_id" ]]; then
    if ! gh project item-edit \
        --project-id "$_ts_project_id" \
        --id "$_ts_item_id" \
        --field-id "$_ts_status_field_id" \
        --single-select-option-id "$_ts_in_progress_id" >/dev/null 2>&1; then
      echo "Warning: could not set Issue #$_ts_issue_number Status -> $_ts_in_progress_name on the project board."
    fi
  else
    echo "Warning: could not resolve project/field IDs to set Status -> $_ts_in_progress_name."
  fi
fi

# Run project-specific setup hook if it exists
if [[ -f "${_ts_repo_root}/.facto/worktree-setup.sh" ]]; then
  echo "Running project worktree-setup hook..."
  bash "${_ts_repo_root}/.facto/worktree-setup.sh" "$_ts_worktree_dir"
fi

# Change caller's CWD into the worktree
cd "$_ts_worktree_dir"

echo ""
echo "Worktree ready:"
echo "  Branch:    ${_ts_branch}"
echo "  Directory: ${_ts_worktree_dir}"
if [[ -n "$_ts_issue_number" ]]; then
  echo "  Issue:     ${_ts_issue_url}"
fi
echo ""

# Clean up temporary variables
unset _ts_main_repo _ts_git_dir _ts_description _ts_repo_root
unset _ts_main_branch _ts_prefix _ts_slug _ts_title_slug _ts_branch _ts_worktree_dir
unset _ts_issue_input _ts_issue_number _ts_issue_url _ts_issue_title _ts_issue_labels_json _ts_issue_json
unset _ts_repo_slug _ts_args _ts_task_path
unset _ts_filtered_args _ts_skip_next _ts_i _ts_tok _ts_next
unset _ts_project_owner _ts_project_number _ts_status_field_name _ts_in_progress_name
unset _ts_project_id _ts_status_field_json _ts_status_field_id _ts_in_progress_id _ts_item_id
