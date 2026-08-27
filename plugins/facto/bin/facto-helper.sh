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
#   tracker.exists             — exit 0 if .facto/settings.json exists and has .tracker; exit 1 otherwise (silent)
#   tracker.field <jq-path>    — print .tracker.<jq-path> to stdout
#   current-issue              — print the active issue's identifier to stdout: a number on a
#                                github-issues tracker ("113"), a team-scoped identifier on a
#                                linear tracker ("SIO-9", uppercased)
#   task-slug                  — print the canonical task slug for the current worktree/branch
#   task-dir [<slug>]          — print the absolute per-task planning-doc dir (<root>/facto-tasks/<slug>
#                                by default; override the "facto-tasks" segment via .tasks_dir in
#                                .facto/settings.json). With <slug>, resolve the dir for that slug
#                                instead of deriving it
#   push-plan                  — print the push plan for the current branch as key=value lines:
#                                branch, remote_branch (absent|present), remote_sha, base, ahead,
#                                behind, action (nothing-to-push|first-push|push|force-with-lease),
#                                command. Keyed on whether origin/<branch> exists — NOT on @{u}, which
#                                on a task-start.sh branch points at origin/<main>. Read-only, but
#                                unlike every other subcommand it makes one network call (git ls-remote).

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

# Normalize a task slug: issue-backed slugs and already-"UNKNOWN-" slugs pass
# through unchanged; anything else gets the "UNKNOWN-" prefix so a missing issue
# is explicit rather than looking like a dropped number. Three forms count as
# issue-backed: a GitHub number ("113-…"), a Linear identifier ("sio-9-…"), and
# the "UNKNOWN-" marker itself.
_normalize_slug() {
  local s="$1"
  if [[ ! "$s" =~ ^([0-9]+|UNKNOWN|[a-z][a-z0-9]*-[0-9]+)- ]]; then
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

# ──────────────────────────────────────────────────────────────────────────────
# push-plan
# ──────────────────────────────────────────────────────────────────────────────
#
# Answers "how should this branch be pushed?" for facto:pr and task-end.sh.
#
# The decision keys on whether a SAME-NAMED remote branch exists, never on
# @{u}. Those are independent: `git worktree add --track ... origin/main` (what
# task-start.sh used to do) sets an upstream of origin/<main> on a branch that
# has never been pushed, so "has an upstream" is not evidence of a remote copy.
# Reading @{u} here is what caused Issue #116.
#
# Resolve the default branch name without a network call. refs/remotes/origin/HEAD
# is frequently unset in a task worktree, so it cannot be relied on alone.
_resolve_main_branch() {
  local ref
  ref="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || ref=""
  if [[ -n "$ref" ]]; then
    echo "${ref#origin/}"
    return 0
  fi
  if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    echo "main"
    return 0
  fi
  if git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    echo "master"
    return 0
  fi
  echo "main"
}

if [[ "$subcommand" == "push-plan" ]]; then
  branch="$(git branch --show-current 2>/dev/null)" || branch=""
  if [[ -z "$branch" ]]; then
    echo "ERROR: not on a branch" >&2
    exit 1
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "ERROR: no 'origin' remote" >&2
    exit 1
  fi

  # Authoritative: asks the remote directly, so it is correct even when the
  # local remote-tracking refs have never been fetched. A failure here must not
  # be mistaken for "no remote branch" — that would silently downgrade a
  # force-with-lease to a first-push.
  if ! ls_remote_out="$(git ls-remote --heads origin "$branch" 2>/dev/null)"; then
    echo "ERROR: could not reach 'origin' to list remote branches" >&2
    exit 1
  fi
  # ls-remote patterns match the TAIL of a ref, so asking for "sio-9-app" also
  # returns "refs/heads/carllelandtaylor/sio-9-app" — and that prefixed form is
  # exactly the Linear branch convention. Taking the first line would report a
  # never-pushed branch as present. Match the full ref path exactly instead.
  remote_sha="$(printf '%s\n' "$ls_remote_out" \
    | awk -F'\t' -v r="refs/heads/${branch}" '$2 == r { print $1; exit }')" || remote_sha=""

  local_sha="$(git rev-parse HEAD 2>/dev/null)" || local_sha=""

  if [[ -z "$remote_sha" ]]; then
    # ── No same-named remote branch: this branch has never been pushed. ───────
    remote_branch="absent"
    main_branch="$(_resolve_main_branch)"
    base="origin/${main_branch}"
    if ! git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
      base="$main_branch"
    fi

    if git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
      ahead="$(git rev-list --count "${base}..HEAD" 2>/dev/null)" || ahead=0
    else
      # Nothing to measure against (no main ref at all) — treat any commit as
      # pushable rather than claiming there is nothing to do.
      base=""
      ahead=1
    fi
    behind=0

    if [[ "$ahead" -eq 0 ]]; then
      action="nothing-to-push"
      push_cmd=""
    else
      action="first-push"
      push_cmd="git push -u origin ${branch}"
    fi
  else
    # ── A same-named remote branch exists. ───────────────────────────────────
    remote_branch="present"
    base="origin/${branch}"

    if [[ "$remote_sha" == "$local_sha" ]]; then
      action="nothing-to-push"
      push_cmd=""
      ahead=0
      behind=0
    elif git cat-file -e "${remote_sha}^{commit}" 2>/dev/null \
      && git merge-base --is-ancestor "$remote_sha" HEAD 2>/dev/null; then
      # Fast-forward. Push an explicit refspec so push.default cannot redirect
      # this at origin/<main> — the destructive variant described in Issue #116.
      action="push"
      push_cmd="git push origin ${branch}"
      ahead="$(git rev-list --count "${remote_sha}..HEAD" 2>/dev/null)" || ahead=0
      behind=0
    else
      # Diverged, or the remote object was never fetched.
      #
      # The lease is deliberately the DEFAULT form, with no explicit value. It
      # leases against refs/remotes/origin/<branch> — what this clone last saw —
      # which is exactly the question --force-with-lease exists to ask. Pinning
      # it to the SHA just read from the remote would be tautological: that
      # value always matches, so the push could never be refused and the lease
      # would silently degrade to a bare --force. Its staleness is the signal,
      # not a defect. When the remote-tracking ref is missing entirely (this
      # branch was never fetched) git refuses too, which is right — we cannot
      # know what we would be destroying.
      action="force-with-lease"
      push_cmd="git push --force-with-lease origin ${branch}"
      if git cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
        counts="$(git rev-list --left-right --count "${remote_sha}...HEAD" 2>/dev/null)" || counts=""
        if [[ -n "$counts" ]]; then
          behind="$(printf '%s' "$counts" | cut -f1)"
          ahead="$(printf '%s' "$counts" | cut -f2)"
        else
          behind="unknown"
          ahead="unknown"
        fi
      else
        # Divergence cannot be measured without the object locally.
        behind="unknown"
        ahead="unknown"
      fi
    fi
  fi

  echo "branch=${branch}"
  echo "remote_branch=${remote_branch}"
  echo "remote_sha=${remote_sha}"
  echo "base=${base}"
  echo "ahead=${ahead}"
  echo "behind=${behind}"
  echo "action=${action}"
  echo "command=${push_cmd}"
  exit 0
fi

# All remaining subcommands need the config to exist
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: .facto/settings.json not found at $CONFIG" >&2
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
    issue_id="${BASH_REMATCH[1]}"
    # Linear branch names carry the identifier lowercased ("sio-9"); Linear's
    # canonical form is uppercase ("SIO-9"), and its API echoes that. Normalize
    # here so no caller has to.
    if [[ -n "$EXPLICIT_ROOT" ]]; then
      tracker_type="$("$0" --root "$EXPLICIT_ROOT" tracker.field type)"
    else
      tracker_type="$("$0" tracker.field type)"
    fi
    if [[ "$tracker_type" == "linear" ]]; then
      issue_id="${issue_id^^}"
    fi
    echo "$issue_id"
    exit 0
  fi

  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# Unknown subcommand
# ──────────────────────────────────────────────────────────────────────────────
echo "ERROR: unknown subcommand '$subcommand'" >&2
echo "Usage: facto-helper.sh [--root <path>] tracker.exists | tracker.field <path> | current-issue | task-slug | task-dir | push-plan" >&2
exit 1
