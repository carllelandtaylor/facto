---
name: setup-facto-dev
description: "One-time developer setup for running Facto from any repo. Detects the Facto checkout and writes FACTO_REPO to your shell profile so the facto-dev skills (observe, think, status, mine-logs, mine-web) can locate Facto's tracker config, OKRs, and Issue templates regardless of which repo you invoke them from. Invoke with /facto-dev:setup-facto-dev. Procedure skill (follow the phases in order)."
disable-model-invocation: true
color: yellow
---

# Facto Dev: Setup Facto-Dev

> **Model:** when run as a subagent, prefer `model: sonnet`.

One-time, per-machine setup so the `facto-dev:*` skills can find the Facto repo from any working directory.

## Why this is needed

The `facto-dev:*` skills operate on Facto's *own* improvement memory — its GitHub Issue tracker (configured in `.facto/settings.json`), its `OKRS.md`, and its Issue templates — but you invoke them while working in *other* repos, so the current directory is the wrong place to look. They locate Facto via the **`FACTO_REPO`** environment variable, falling back to a fragile skill-symlink-path walk only when it is unset. Setting `FACTO_REPO` makes that resolution robust and independent of how the plugin is installed.

`FACTO_REPO` is a per-developer global (you have one Facto, used across all your projects), so it belongs in your shell profile — not in any project's committed config.

## Phase 1: Resolve this Facto checkout

Derive the absolute path of the Facto repo from this skill's own location, and confirm it is really Facto:

```bash
FACTO_REPO="$(cd "$(dirname "$(readlink -f ~/.claude/skills/facto-dev/skills/setup-facto-dev/SKILL.md)")"/../../../.. && pwd)"
test -f "$FACTO_REPO/.facto/settings.json" || { echo "ERROR: resolved '$FACTO_REPO' but it has no .facto/settings.json — is the facto-dev plugin symlinked from your Facto checkout?" >&2; exit 1; }
echo "Facto repo: $FACTO_REPO"
```

## Phase 2: Choose the shell profile

Pick the profile file that runs for the developer's interactive shells:

```bash
case "$(basename "${SHELL:-bash}")" in
  zsh)  PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bashrc" ;;
  *)    PROFILE="$HOME/.profile" ;;
esac
echo "Profile: $PROFILE"
```

Tell the developer which file you picked, and proceed. (If they keep their exports elsewhere, let them name the file and use that instead.)

## Phase 3: Write the export (idempotent)

If `FACTO_REPO` is already exported in the profile, report its current value and update it only if it differs from `$FACTO_REPO`. Otherwise append it:

```bash
if grep -qsE '^[[:space:]]*export[[:space:]]+FACTO_REPO=' "$PROFILE"; then
  echo "Existing entry:"; grep -nE '^[[:space:]]*export[[:space:]]+FACTO_REPO=' "$PROFILE"
  # Replace it only if the path differs; edit the line in place.
else
  printf '\n# facto-dev: let the facto-dev skills find the Facto repo from any cwd\nexport FACTO_REPO=%q\n' "$FACTO_REPO" >> "$PROFILE"
  echo "Added FACTO_REPO to $PROFILE"
fi
```

When replacing an existing line, edit that one line in place (preserve everything else in the file) — never rewrite the profile wholesale.

## Phase 4: Activate and verify

The profile only takes effect in new shells, so export it into the current session too, then confirm a facto-dev skill resolves Facto without the fallback:

```bash
export FACTO_REPO="$FACTO_REPO"
facto-helper.sh --root "$FACTO_REPO" tracker.field repo  # should print Facto's tracker repo slug
```

Report to the developer:
- The Facto path written to `FACTO_REPO` and the profile file it went in.
- That they should open a new terminal (or `source` the profile) for it to apply to future sessions.
- The tracker repo slug printed by the verification, as proof the resolution works.
