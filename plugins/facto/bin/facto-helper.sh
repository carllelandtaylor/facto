#!/usr/bin/env bash
set -euo pipefail

# facto-helper.sh — internal resolver for Facto's skills.
#
# This is the single read-only chokepoint the Facto skills shell out to in order
# to answer questions about the current repo and task: it reads the host repo's
# .facto/settings.json and inspects git state to resolve tracker config, the
# active issue number, the canonical task slug, and the per-task planning-doc
# directory. Centralizing that logic here (slug normalization, the "UNKNOWN-"
# convention, the tasks_dir override) keeps it out of the individual skills.
#
# NOT a user command. You are not meant to run this by hand — the skills and the
# task-*.sh scripts call it for you. It changes nothing; every subcommand is a
# lookup that prints to stdout (or sets an exit code).
#
# Usage (invoked by skills, not humans): facto-helper.sh [--root <path>] <subcommand> [args...]
#
# Options:
#   --root <path>              — use <path> as the repo root instead of git rev-parse --show-toplevel
#
# Subcommands:
#   tracker.exists             — exit 0 if config.json exists and has .tracker; exit 1 otherwise (silent)
#   tracker.field <jq-path>    — print .tracker.<jq-path> to stdout
#   current-issue              — print the active issue number to stdout
#   task-slug                  — print the canonical task slug for the current worktree/branch
#   task-dir [<slug>]          — print the absolute per-task planning-doc dir (<root>/facto-tasks/<slug>
#                                by default; override the "facto-tasks" segment via .tasks_dir in
#                                .facto/settings.json). With <slug>, resolve the dir for that slug
#                                instead of deriving it

# Parse optional --root <path> flag before the subcommand
EXPLICIT_ROOT=""
while [[ "${1:-}" == "--root" ]]; do
  if [[ $# -lt 2 ]]; then
    echo "ERROR: --root requires a path argument" >&2
    exit 1
  fi
  EXPLICIT_ROOT="$2"
  shift 2
done

# Resolve host repo root (works from any cwd)
HOST_ROOT="${EXPLICIT_ROOT:-$(git rev-parse --show-toplevel)}"

# Validate explicit root if provided
if [[ -n "$EXPLICIT_ROOT" ]]; then
  if [[ ! -d "$EXPLICIT_ROOT" ]]; then
    echo "ERROR: --root path does not exist or is not a directory: $EXPLICIT_ROOT" >&2
    exit 1
  fi
fi

CONFIG="$HOST_ROOT/.facto/settings.json"

# Resolve the per-task planning-doc base dir. Default "facto-tasks" (relative to the
# repo root); override via the top-level .tasks_dir in .facto/settings.json. An absolute
# .tasks_dir is honored as-is; a relative one is resolved under the repo root. Works
# config-free — when settings.json is absent or has no .tasks_dir, the default applies.
_tasks_base() {
  local dir="facto-tasks"
  if [[ -f "$CONFIG" ]]; then
    local configured
    configured="$(jq -r '.tasks_dir // empty' "$CONFIG" 2>/dev/null)" || configured=""
    [[ -n "$configured" ]] && dir="$configured"
  fi
  if [[ "$dir" = /* ]]; then
    printf '%s\n' "$dir"
  else
    printf '%s\n' "$HOST_ROOT/$dir"
  fi
}

# Normalize a task slug: issue-backed ("<n>-…") and already-"UNKNOWN-" slugs
# pass through unchanged; anything else gets the "UNKNOWN-" prefix so a missing
# issue number is explicit rather than looking like a dropped number.
_normalize_slug() {
  local s="$1"
  if [[ ! "$s" =~ ^([0-9]+|UNKNOWN)- ]]; then
    s="UNKNOWN-$s"
  fi
  printf '%s\n' "$s"
}

subcommand="${1:-}"

# ──────────────────────────────────────────────────────────────────────────────
# tracker.exists
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$subcommand" == "tracker.exists" ]]; then
  if [[ -f "$CONFIG" ]] && jq -e '.tracker' "$CONFIG" >/dev/null 2>&1; then
    exit 0
  fi
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# task-slug / task-dir — per-task planning-doc directory. task-slug is git-only;
# task-dir derives the slug the same way, then resolves the base dir (default
# facto-tasks, or .tasks_dir from settings.json when present — see _tasks_base).
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$subcommand" == "task-slug" ]]; then
  # Derive a base slug from the worktree/branch, then normalize it (see below).
  base=""
  # Inside a worktree, the directory basename is the canonical slug — it matches
  # what task-start.sh named the worktree. Detect a worktree by comparing the
  # per-worktree git-dir against the shared git-common-dir.
  git_dir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" || true
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || true
  if [[ -n "$git_dir" && -n "$common_dir" && "$git_dir" != "$common_dir" ]]; then
    base="$(basename "$HOST_ROOT")"
  else
    # Not a worktree (e.g. a feature branch in the main checkout): derive the
    # slug from the branch name minus its prefix.
    branch="$(git branch --show-current 2>/dev/null)" || true
    if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]]; then
      base="${branch#*/}"
    fi
  fi
  # Detached HEAD or on the default branch — caller must ask the developer.
  [[ -z "$base" ]] && exit 1
  _normalize_slug "$base"
  exit 0
fi

if [[ "$subcommand" == "task-dir" ]]; then
  # Optional explicit slug: `task-dir <slug>` resolves the dir for a given slug
  # (used by callers that have to ask the developer when no slug is derivable).
  # It's normalized the same way, so callers never construct the path themselves.
  explicit_slug="${2:-}"
  if [[ -n "$explicit_slug" ]]; then
    slug="$(_normalize_slug "$explicit_slug")"
  elif [[ -n "$EXPLICIT_ROOT" ]]; then
    slug="$("$0" --root "$EXPLICIT_ROOT" task-slug)" || exit 1
  else
    slug="$("$0" task-slug)" || exit 1
  fi
  echo "$(_tasks_base)/$slug"
  exit 0
fi

# All remaining subcommands need the config to exist
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: config.json not found at $CONFIG" >&2
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# tracker.field <jq-path>
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$subcommand" == "tracker.field" ]]; then
  path="${2:-}"
  if [[ -z "$path" ]]; then
    echo "ERROR: tracker.field requires a jq path argument" >&2
    exit 1
  fi

  # Special-case: repo — if null, resolve from git remote
  if [[ "$path" == "repo" ]]; then
    raw_value=$(jq -r ".tracker.repo" "$CONFIG")
    if [[ "$raw_value" == "null" || -z "$raw_value" ]]; then
      (cd "$HOST_ROOT" && gh repo view --json nameWithOwner -q .nameWithOwner)
    else
      echo "$raw_value"
    fi
    exit 0
  fi

  # Detect whether the value is a scalar (string/number/boolean) or a container (array/object)
  value_type=$(jq -r ".tracker.${path} | type" "$CONFIG" 2>/dev/null) || {
    echo "ERROR: failed to parse .tracker.${path} from $CONFIG" >&2
    exit 1
  }

  case "$value_type" in
    string|number|boolean)
      jq -r ".tracker.${path}" "$CONFIG"
      ;;
    null)
      # Return empty string and exit 0 for legitimate null fields
      echo ""
      exit 0
      ;;
    array|object)
      jq -c ".tracker.${path}" "$CONFIG"
      ;;
    *)
      echo "ERROR: unexpected type '$value_type' for .tracker.${path}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# current-issue
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$subcommand" == "current-issue" ]]; then
  # 1. Check task.json (worktree-local task file)
  task_json_path="$(git rev-parse --git-path task.json 2>/dev/null)" || true
  if [[ -n "$task_json_path" && -f "$task_json_path" ]]; then
    issue_num=$(jq -r '.issue_number // empty' "$task_json_path" 2>/dev/null) || true
    if [[ -n "$issue_num" && "$issue_num" != "null" ]]; then
      echo "$issue_num"
      exit 0
    fi
  fi

  # 2. Try branch name pattern
  branch="$(git branch --show-current 2>/dev/null)" || true
  if [[ -z "$branch" ]]; then
    exit 1
  fi

  # Propagate --root to the recursive call so the same config root is used
  if [[ -n "$EXPLICIT_ROOT" ]]; then
    pattern="$("$0" --root "$EXPLICIT_ROOT" tracker.field branch_issue_pattern)"
  else
    pattern="$("$0" tracker.field branch_issue_pattern)"
  fi
  if [[ -z "$pattern" ]]; then
    exit 1
  fi

  # Strip Perl named-group syntax (?<name>...) → (...) for bash =~ compatibility
  basic_pattern=$(echo "$pattern" | sed 's/(?<[a-zA-Z_][a-zA-Z0-9_]*>/(/g')

  if [[ "$branch" =~ $basic_pattern ]]; then
    echo "${BASH_REMATCH[1]}"
    exit 0
  fi

  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# Unknown subcommand
# ──────────────────────────────────────────────────────────────────────────────
echo "ERROR: unknown subcommand '$subcommand'" >&2
echo "Usage: facto-helper.sh [--root <path>] tracker.exists | tracker.field <path> | current-issue | task-slug | task-dir" >&2
exit 1
