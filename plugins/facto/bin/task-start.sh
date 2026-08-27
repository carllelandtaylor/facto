#!/bin/bash
# task-start.sh — Create a git worktree for a new task
# Must be SOURCED (not executed) so it can change the caller's CWD.
#
# Usage:
#   source task-start.sh <description words...>
#   source task-start.sh --issue <number|url|IDENTIFIER> [extra description...]
#   source task-start.sh --branch <branch-name>
#
# --issue and --branch are alternatives; supplying both is an error. Which
# --issue forms are valid depends on the host repo's tracker.type:
#   github-issues — an issue number or an issue URL; the Issue is fetched
#   linear        — an identifier plus description words; nothing is fetched,
#                   because bash cannot reach Linear (it is an MCP server)
#
# Examples:
#   source task-start.sh add user login page
#   source task-start.sh --issue 86
#   source task-start.sh --issue https://github.com/owner/repo/issues/86
#   source task-start.sh --issue SIO-9 create app switcher
#   source task-start.sh --branch carllelandtaylor/sio-9-create-app-switcher

# --- Preflight checks (no side effects) ---

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: not inside a git repository."
  return 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: source task-start.sh <description...>"
  echo "       source task-start.sh --issue <number|url|IDENTIFIER> [extra description...]"
  echo "       source task-start.sh --branch <branch-name>"
  return 1
fi

# --- Parse --issue / --branch flags ---

_ts_issue_input=""
_ts_branch_input=""
_ts_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --issue requires a value (issue number, URL, or identifier)."
        unset _ts_issue_input _ts_branch_input _ts_args
        return 1
      fi
      _ts_issue_input="$2"
      shift 2
      ;;
    --branch)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --branch requires a value (a branch name)."
        unset _ts_issue_input _ts_branch_input _ts_args
        return 1
      fi
      _ts_branch_input="$2"
      shift 2
      ;;
    *)
      _ts_args+=("$1")
      shift
      ;;
  esac
done
set -- "${_ts_args[@]}"

if [[ -n "$_ts_issue_input" && -n "$_ts_branch_input" ]]; then
  echo "Error: --branch and --issue are mutually exclusive."
  unset _ts_issue_input _ts_branch_input _ts_args
  return 1
fi

# --- Detect a literal "issue N" token sequence in positional args ---
# If the developer wrote `task-start issue 123` instead of
# `task-start --issue 123`, promote the first matching "issue <number>"
# to issue mode. A Linear identifier ("issue SIO-9") is promoted the same way.
# Case-insensitive; first match wins. The matched two tokens are removed from
# _ts_args for hygiene.
if [[ -z "$_ts_issue_input" && -z "$_ts_branch_input" ]]; then
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
          && ( "$_ts_next" =~ ^[0-9]+$ || "$_ts_next" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ) ]]; then
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

# --- Resolve the host repo's tracker type ---
# Decides which --issue forms are legal and whether the Issue can be fetched at
# all. Defaults to github-issues so a repo with no .facto/settings.json behaves
# exactly as it always has.
_ts_tracker_type="github-issues"
if command -v facto-helper.sh >/dev/null 2>&1 && facto-helper.sh tracker.exists 2>/dev/null; then
  _ts_tracker_type="$(facto-helper.sh tracker.field type 2>/dev/null)"
  [[ -z "$_ts_tracker_type" ]] && _ts_tracker_type="github-issues"
fi

# --- Issue-mode setup (resolves Issue + locks branch prefix from labels) ---

_ts_issue_number=""
_ts_issue_url=""
_ts_issue_title=""
_ts_issue_labels_json=""
_ts_branch_prefix=""
# Initialized rather than left unset: this script is sourced, and the trailing
# unset only runs on the success path, so an aborted run would otherwise leave
# these readable by the next invocation in a different repo.
_ts_branch_pattern=""
_ts_basic_pattern=""
_ts_repo_slug=""

if [[ -n "$_ts_issue_input" ]]; then
  if ! command -v facto-helper.sh >/dev/null 2>&1; then
    echo "Error: --issue requires facto-helper.sh on PATH."
    unset _ts_issue_input _ts_branch_input _ts_args
    return 1
  fi

  if ! facto-helper.sh tracker.exists; then
    echo "Error: --issue requires .facto/settings.json with a tracker section in the host repo."
    unset _ts_issue_input _ts_branch_input _ts_args
    return 1
  fi

  if [[ "$_ts_tracker_type" == "linear" ]]; then
    # Linear lives behind an MCP server, which bash cannot call, so nothing is
    # fetched: the identifier and the title both come from the developer.
    if [[ ! "$_ts_issue_input" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
      echo "Error: --issue on a Linear repo must be an identifier like SIO-9."
      echo "       To use the branch name Linear generates, pass --branch <name> instead."
      unset _ts_issue_input _ts_branch_input _ts_args
      return 1
    fi
    _ts_issue_number="${_ts_issue_input^^}"
    if [[ $# -eq 0 ]]; then
      echo "Error: --issue $_ts_issue_number on a Linear repo requires description words,"
      echo "       e.g. --issue SIO-9 create app switcher."
      unset _ts_issue_input _ts_branch_input _ts_args _ts_issue_number
      return 1
    fi
    _ts_issue_url=""
    _ts_issue_title="$*"
    _ts_branch_prefix="$(facto-helper.sh tracker.field branch_prefix 2>/dev/null)"
  else
    _ts_repo_slug="$(facto-helper.sh tracker.field repo)"
    if [[ -z "$_ts_repo_slug" ]]; then
      echo "Error: could not resolve tracker repo via facto-helper.sh."
      unset _ts_issue_input _ts_branch_input _ts_args _ts_repo_slug
      return 1
    fi

    # Extract numeric issue number from either a bare number or a URL
    if [[ "$_ts_issue_input" =~ ^[0-9]+$ ]]; then
      _ts_issue_number="$_ts_issue_input"
    elif [[ "$_ts_issue_input" =~ /issues/([0-9]+) ]]; then
      _ts_issue_number="${BASH_REMATCH[1]}"
    else
      echo "Error: --issue must be an issue number or a URL containing /issues/<number>."
      unset _ts_issue_input _ts_branch_input _ts_args _ts_repo_slug
      return 1
    fi

    _ts_issue_json="$(gh issue view "$_ts_issue_number" --repo "$_ts_repo_slug" --json number,title,url,labels 2>/dev/null)"
    if [[ -z "$_ts_issue_json" ]]; then
      echo "Error: could not fetch Issue #$_ts_issue_number from $_ts_repo_slug."
      unset _ts_issue_input _ts_branch_input _ts_args _ts_repo_slug _ts_issue_number _ts_issue_json
      return 1
    fi

    _ts_issue_title="$(echo "$_ts_issue_json" | jq -r .title)"
    _ts_issue_url="$(echo "$_ts_issue_json" | jq -r .url)"
    _ts_issue_labels_json="$(echo "$_ts_issue_json" | jq -c '[.labels[].name]')"
  fi
fi

# --- Branch-mode setup (branch name given verbatim; nothing is fetched) ---
# The issue identifier is recovered from the branch name itself via the
# tracker's branch_issue_pattern. A name that matches nothing is not an error —
# it starts a no-issue task, the same as a bare description would.
if [[ -n "$_ts_branch_input" ]]; then
  if command -v facto-helper.sh >/dev/null 2>&1; then
    _ts_branch_pattern="$(facto-helper.sh tracker.field branch_issue_pattern 2>/dev/null)"
  fi
  if [[ -n "${_ts_branch_pattern:-}" ]]; then
    # Strip Perl named-group syntax (?<name>...) → (...) for bash =~, matching
    # how facto-helper.sh consumes the same pattern.
    _ts_basic_pattern="$(echo "$_ts_branch_pattern" | sed 's/(?<[a-zA-Z_][a-zA-Z0-9_]*>/(/g')"
    if [[ "$_ts_branch_input" =~ $_ts_basic_pattern ]]; then
      _ts_issue_number="${BASH_REMATCH[1]}"
      [[ "$_ts_tracker_type" == "linear" ]] && _ts_issue_number="${_ts_issue_number^^}"
    fi
  fi
  if [[ -z "$_ts_issue_number" ]]; then
    echo "Warning: ${_ts_branch_input} does not match this repo's branch_issue_pattern — starting as a no-issue task."
  fi
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

# Infer branch prefix. Only meaningful when this script composes the branch
# name itself from a conventional-commit type — Linear supplies its own leading
# segment, and --branch supplies the whole name.
_ts_prefix="feat"
if [[ -z "$_ts_branch_input" && "$_ts_tracker_type" != "linear" ]]; then
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
fi

# Slugify the description
_ts_title_slug="$(echo "$_ts_description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)"

# No issue: prefix "UNKNOWN-" where the issue identifier would go, so a missing
# issue is explicit rather than looking like a slug whose number was dropped.
if [[ -n "$_ts_branch_input" ]]; then
  # Explicit branch name is used verbatim; the task slug is its last segment.
  # Stripping every leading segment rather than just the first keeps the slug a
  # flat directory name for a branch like carl/feature/sio-9-foo, and keeps it
  # equal to the worktree basename that facto-helper.sh task-slug reads back.
  _ts_branch="$_ts_branch_input"
  _ts_slug="${_ts_branch_input##*/}"
  [[ -z "$_ts_issue_number" ]] && _ts_slug="UNKNOWN-${_ts_slug}"
elif [[ "$_ts_tracker_type" == "linear" && -n "$_ts_issue_number" ]]; then
  # Rebuild the branch name Linear itself would generate, so both entry points
  # produce the same branch for the same issue.
  _ts_slug="${_ts_issue_number,,}-${_ts_title_slug}"
  if [[ -n "$_ts_branch_prefix" ]]; then
    _ts_branch="${_ts_branch_prefix}/${_ts_slug}"
  else
    echo "Warning: tracker.branch_prefix is not set — the branch will not match Linear's copy-button format."
    _ts_branch="$_ts_slug"
  fi
else
  if [[ -n "$_ts_issue_number" ]]; then
    _ts_slug="${_ts_issue_number}-${_ts_title_slug}"
  else
    _ts_slug="UNKNOWN-${_ts_title_slug}"
  fi
  _ts_branch="${_ts_prefix}/${_ts_slug}"
fi

# Create worktree directory
_ts_worktree_dir="${_ts_repo_root}/.facto/worktrees/${_ts_slug}"
mkdir -p "$(dirname "$_ts_worktree_dir")"

# --no-track, deliberately. Git's default branch.autoSetupMerge=true already
# sets an upstream when the start point is a remote-tracking ref, so --track was
# redundant — and the upstream it set (origin/<main>) is false for a feature
# branch: the branch does not exist on the remote at all yet. facto:pr read that
# upstream as proof the branch had been pushed and chose a plain `git push`
# instead of the first-push with -u (Issue #116). Do not restore --track.
git worktree add --no-track "$_ts_worktree_dir" -b "$_ts_branch" "origin/${_ts_main_branch}" --quiet
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
  # A GitHub issue number stays a JSON number, so existing task.json files keep
  # their shape; a Linear identifier ("SIO-9") is not a number and is written as
  # a string. facto-helper.sh reads the field with `jq -r`, so both work.
  if [[ "$_ts_issue_number" =~ ^[0-9]+$ ]]; then
    _ts_issue_number_arg=(--argjson n "$_ts_issue_number")
  else
    _ts_issue_number_arg=(--arg n "$_ts_issue_number")
  fi
  jq -n \
    "${_ts_issue_number_arg[@]}" \
    --arg url "$_ts_issue_url" \
    --arg title "$_ts_issue_title" \
    --arg started "$(date -Iseconds)" \
    '{ issue_number: $n, issue_url: $url, issue_title: $title, started_at: $started }' \
    > "$_ts_task_path" \
    || echo "Warning: could not write task.json at $_ts_task_path"

  # Status -> In progress (best effort). Only the GitHub Project board is
  # reachable from bash; Linear is an MCP server, so its status write is left to
  # whichever skill picks the task up next.
  if [[ "$_ts_tracker_type" == "linear" ]]; then
    echo "Note: Linear status is not set by task-start; /facto:implement or /facto:fix-bug will move $_ts_issue_number to In Progress."
  else
    # --branch skips the fetch, so the repo slug may not have been resolved yet;
    # the item-add fallback below builds an issue URL from it.
    [[ -z "${_ts_repo_slug:-}" ]] && _ts_repo_slug="$(facto-helper.sh tracker.field repo 2>/dev/null)"
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
fi

# Run project-specific setup hook if it exists.
# A failing hook does not undo anything: the developer may want to inspect the
# half-built worktree or re-run setup by hand once they have fixed the cause.
# It must not be mistaken for a working one either, so the failure is repeated
# in red at the very end of the run, below the summary, where it cannot scroll
# away the way the hook's own output does.
_ts_setup_failed=0
if [[ -f "${_ts_repo_root}/.facto/worktree-setup.sh" ]]; then
  echo "Running project worktree-setup hook..."
  if ! bash "${_ts_repo_root}/.facto/worktree-setup.sh" "$_ts_worktree_dir"; then
    _ts_setup_failed=1
  fi
fi

# Change caller's CWD into the worktree
cd "$_ts_worktree_dir"

echo ""
if [[ "$_ts_setup_failed" -eq 1 ]]; then
  echo "Worktree created, but SETUP FAILED:"
else
  echo "Worktree ready:"
fi
echo "  Branch:    ${_ts_branch}"
echo "  Directory: ${_ts_worktree_dir}"
if [[ -n "$_ts_issue_number" ]]; then
  # Linear tasks have no fetched URL — show the identifier instead.
  if [[ -n "$_ts_issue_url" ]]; then
    echo "  Issue:     ${_ts_issue_url}"
  else
    echo "  Issue:     ${_ts_issue_number}"
  fi
fi
echo ""

# Shout about a failed setup hook last of all, so it is what the developer is
# left looking at. Colour only when stdout is a terminal, so a captured log
# stays readable.
if [[ "$_ts_setup_failed" -eq 1 ]]; then
  if [[ -t 1 ]]; then
    _ts_red=$'\033[1;31m'
    _ts_reset=$'\033[0m'
  else
    _ts_red=""
    _ts_reset=""
  fi
  echo "${_ts_red}========================================================================${_ts_reset}"
  echo "${_ts_red}  SETUP FAILED — THIS WORKTREE MAY NOT BE CONFIGURED CORRECTLY.${_ts_reset}"
  echo "${_ts_red}${_ts_reset}"
  echo "${_ts_red}  The project's .facto/worktree-setup.sh exited non-zero. Its output is${_ts_reset}"
  echo "${_ts_red}  further up this run — read it before working here.${_ts_reset}"
  echo "${_ts_red}${_ts_reset}"
  echo "${_ts_red}  The worktree and branch were left in place. Once you have fixed what${_ts_reset}"
  echo "${_ts_red}  the hook reported, re-run it by hand:${_ts_reset}"
  echo "${_ts_red}${_ts_reset}"
  echo "${_ts_red}    bash ${_ts_repo_root}/.facto/worktree-setup.sh ${_ts_worktree_dir}${_ts_reset}"
  echo "${_ts_red}========================================================================${_ts_reset}"
  echo ""
fi

# Clean up temporary variables
unset _ts_red _ts_reset
unset _ts_main_repo _ts_git_dir _ts_description _ts_repo_root
unset _ts_main_branch _ts_prefix _ts_slug _ts_title_slug _ts_branch _ts_worktree_dir
unset _ts_issue_input _ts_issue_number _ts_issue_url _ts_issue_title _ts_issue_labels_json _ts_issue_json
unset _ts_repo_slug _ts_args _ts_task_path
unset _ts_filtered_args _ts_skip_next _ts_i _ts_tok _ts_next
unset _ts_project_owner _ts_project_number _ts_status_field_name _ts_in_progress_name
unset _ts_project_id _ts_status_field_json _ts_status_field_id _ts_in_progress_id _ts_item_id
unset _ts_tracker_type _ts_branch_input _ts_branch_prefix _ts_branch_pattern _ts_basic_pattern
unset _ts_issue_number_arg

# Return non-zero when the setup hook failed, so the run's status matches what
# the banner says. Kept until here because the unsets above would clear it.
if [[ "$_ts_setup_failed" -eq 1 ]]; then
  unset _ts_setup_failed
  return 1
fi
unset _ts_setup_failed
