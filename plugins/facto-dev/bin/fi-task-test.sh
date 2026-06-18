#!/usr/bin/env bash
set -euo pipefail

# fi-task-test.sh — point Facto's global install at the current worktree.
#
# Facto ships as two Claude Code skills-directory plugins:
#
#     <repo>/plugins/facto       (public plugin: skills/ + bin/)
#     <repo>/plugins/facto-dev   (developer plugin: skills/ + bin/)
#
# They are installed by symlinking each into the personal skills dir:
#
#     ~/.claude/skills/facto      -> <main-checkout>/plugins/facto
#     ~/.claude/skills/facto-dev  -> <main-checkout>/plugins/facto-dev
#
# Because those install symlinks point at the MAIN checkout, changes made inside
# a task-start worktree are never active while you develop them. This helper
# bridges that gap by re-pointing the two install symlinks themselves:
#
#   • Run from inside a worktree: re-points ~/.claude/skills/facto and
#     ~/.claude/skills/facto-dev at <worktree>/plugins/facto and
#     <worktree>/plugins/facto-dev, so Facto's global install resolves to
#     the worktree's in-progress copy. Only does this when the main checkout is
#     on the default branch, up to date with origin, and has no uncommitted
#     changes.
#
#   • Run from the main checkout: reverts both install symlinks back to the main
#     checkout's plugins/facto and plugins/facto-dev.
#
# Facto-development-only: refuses to run in repos that merely consume Facto
# (they have no tracked plugins/facto and plugins/facto-dev dirs).
#
# This script is EXECUTED, not sourced — it changes nothing about the caller's
# shell. It only manipulates the two ~/.claude/skills/* install symlinks; it
# never touches tracked files in any checkout.
#
# Usage: fi-task-test.sh [-h|--help]

usage() {
  cat <<'EOF'
Usage: fi-task-test.sh [-h|--help]

Facto-development-only helper. Run with no arguments:

  • From inside a task worktree it re-points Facto's two install symlinks

        ~/.claude/skills/facto      -> <worktree>/plugins/facto
        ~/.claude/skills/facto-dev  -> <worktree>/plugins/facto-dev

    so Facto's global install resolves to this worktree's in-progress
    skills/bin. This is done only if the main checkout is on the default
    branch, up to date with origin, and has no uncommitted changes.

  • From the main checkout it reverts both install symlinks back to the main
    checkout's plugins/facto and plugins/facto-dev.

Only works in the Facto repo itself (a repo with tracked plugins/facto and
plugins/facto-dev directories).
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "ERROR: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
esac

# --- Facto's two plugins and their install symlinks ---
PLUGINS=(facto facto-dev)
SKILLS_DIR="$HOME/.claude/skills"

# --- Resolve the main checkout (works from any worktree) ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"

# --- Facto-repo guard: the main checkout must track both plugin dirs ---
for p in "${PLUGINS[@]}"; do
  if ! git -C "$MAIN_ROOT" ls-tree -d --name-only HEAD "plugins/$p" 2>/dev/null | grep -qx "plugins/$p"; then
    echo "ERROR: this is not the Facto repo — no tracked 'plugins/$p' directory at $MAIN_ROOT." >&2
    echo "       fi-task-test is only for developing Facto itself; repos that consume Facto" >&2
    echo "       don't have the plugins/facto and plugins/facto-dev sources." >&2
    exit 1
  fi
done

# --- Re-point both install symlinks at <root>/plugins/<plugin> ---
# Only ever replaces a symlink (or a missing entry). If an install entry exists
# and is NOT a symlink (e.g. a real directory), abort rather than delete it.
repoint() {
  local root="$1" p link target
  for p in "${PLUGINS[@]}"; do
    link="$SKILLS_DIR/$p"
    target="$root/plugins/$p"
    if [[ -e "$link" && ! -L "$link" ]]; then
      echo "ERROR: $link exists and is not a symlink; refusing to replace it." >&2
      echo "       Remove or back it up manually, then re-run." >&2
      exit 1
    fi
    rm -f "$link"
    ln -s "$target" "$link"
    echo "Linked: $link -> $target"
  done
}

# --- Detect mode: main checkout (reset) vs worktree (link) ---
GIT_DIR_ABS="$(git rev-parse --path-format=absolute --git-dir)"
COMMON_DIR_ABS="$(git rev-parse --path-format=absolute --git-common-dir)"

if [[ "$GIT_DIR_ABS" == "$COMMON_DIR_ABS" ]]; then
  # ── Reset mode (in the main checkout) — no preconditions; this is the escape hatch ──
  mkdir -p "$SKILLS_DIR"
  repoint "$MAIN_ROOT"
  echo "Reset: Facto's install now resolves to the main checkout at $MAIN_ROOT."
  exit 0
fi

# ── Link mode (inside a worktree) ────────────────────────────────────────────
WORKTREE_ROOT="$(git rev-parse --show-toplevel)"

for p in "${PLUGINS[@]}"; do
  if [[ ! -d "$WORKTREE_ROOT/plugins/$p" ]]; then
    echo "ERROR: this worktree has no 'plugins/$p' directory at $WORKTREE_ROOT/plugins/$p." >&2
    exit 1
  fi
done

# Precondition 1: main checkout is on the default branch
MAIN_BRANCH="$(git -C "$MAIN_ROOT" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')"
[[ -n "$MAIN_BRANCH" ]] || MAIN_BRANCH="main"
CURRENT_MAIN_BRANCH="$(git -C "$MAIN_ROOT" branch --show-current)"
if [[ "$CURRENT_MAIN_BRANCH" != "$MAIN_BRANCH" ]]; then
  echo "ERROR: main checkout is on '$CURRENT_MAIN_BRANCH', not '$MAIN_BRANCH'." >&2
  echo "       Switch the main checkout to '$MAIN_BRANCH' before linking." >&2
  exit 1
fi

# Precondition 2: main is up to date with origin
if ! git -C "$MAIN_ROOT" fetch origin --quiet; then
  echo "ERROR: could not fetch from origin to verify the main checkout is up to date." >&2
  exit 1
fi
LOCAL_SHA="$(git -C "$MAIN_ROOT" rev-parse "$MAIN_BRANCH")"
REMOTE_SHA="$(git -C "$MAIN_ROOT" rev-parse "origin/$MAIN_BRANCH")"
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
  echo "ERROR: main checkout's '$MAIN_BRANCH' is not in sync with 'origin/$MAIN_BRANCH'." >&2
  echo "       Update it (e.g. git -C \"$MAIN_ROOT\" pull --ff-only) before linking." >&2
  exit 1
fi

# Precondition 3: no uncommitted changes in the main checkout.
DIRTY="$(git -C "$MAIN_ROOT" status --porcelain)"
if [[ -n "$DIRTY" ]]; then
  echo "ERROR: main checkout has uncommitted changes:" >&2
  echo "$DIRTY" >&2
  echo "       Commit, stash, or revert them before linking." >&2
  exit 1
fi

# --- Re-point both install symlinks at this worktree's plugins ---
mkdir -p "$SKILLS_DIR"
repoint "$WORKTREE_ROOT"

echo "Facto's ~/.claude/skills/{facto,facto-dev} install now resolves to this worktree."
echo "Run 'fi-task-test.sh' from the main checkout to revert."
