---
name: setup-facto
description: "Set up the Facto factory mechanics. Adds the task-* worktree commands to your shell PATH (once per machine), then optionally wires the current repo to a GitHub Issues + Project tracker by writing .facto/settings.json and dropping worktree setup/teardown hook stubs. Run it once after installing the facto plugin, and again in each new project you want tracker integration for. Invoke with /facto:setup-facto. Procedure skill (follow the phases in order)."
disable-model-invocation: true
color: yellow
---

# Setup Facto

> **Model:** when run as a subagent, prefer `model: sonnet`.

Wire up the Facto mechanics so a user goes from "plugin installed" to "ready to work" with no hand-editing of dotfiles or config. Two scopes:

- **Machine-global (once):** put the `task-start` / `task-list` / `task-end` worktree commands on the user's shell PATH (Phases 1–2).
- **Per-project (per repo, optional):** wire the current repo to a GitHub Issues + Project tracker and drop worktree hook stubs (Phases 3–4).

The machine-global phases are idempotent — re-running this skill in a new project skips them and just does the per-project setup.

## Phase 1: Resolve this facto checkout

Derive the absolute path of the `facto` plugin from this skill's own location, and confirm its `bin/` is present:

```bash
FACTO_PLUGIN="$(cd "$(dirname "$(readlink -f ~/.claude/skills/facto/skills/setup-facto/SKILL.md)")"/../.. && pwd)"
FACTO_BIN="$FACTO_PLUGIN/bin"
test -x "$FACTO_BIN/task-start.sh" || { echo "ERROR: resolved '$FACTO_BIN' but task-start.sh isn't there — is the facto plugin symlinked from your factory checkout?" >&2; exit 1; }
echo "Facto bin: $FACTO_BIN"
```

## Phase 2: Put the worktree commands on PATH (machine-global, idempotent)

The `task-*` commands run in the user's own terminal and must be **sourced** (they `cd` into the new worktree), so they go in the shell profile as a PATH entry plus `source` aliases.

Pick the profile file for the user's interactive shells:

```bash
case "$(basename "${SHELL:-bash}")" in
  zsh)  PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bashrc" ;;
  *)    PROFILE="$HOME/.profile" ;;
esac
echo "Profile: $PROFILE"
```

Tell the user which file you picked. (If they keep their config elsewhere, let them name the file and use that instead.)

Then write the block idempotently — if the Facto sentinel is already present, report it and update the PATH line only if `$FACTO_BIN` differs; otherwise append:

```bash
if grep -qsF '# facto: worktree commands on PATH' "$PROFILE"; then
  echo "Facto PATH block already present in $PROFILE:"; grep -nF 'facto' "$PROFILE"
  # If the existing PATH points at a different bin, edit just that one line in place.
else
  printf '\n# facto: worktree commands on PATH\nexport PATH=%q:"$PATH"\nalias task-start='"'"'source task-start.sh'"'"'\nalias task-end='"'"'source task-end.sh'"'"'\nalias task-list='"'"'source task-list.sh'"'"'\n' "$FACTO_BIN" >> "$PROFILE"
  echo "Added Facto worktree commands to $PROFILE"
fi
```

When updating an existing block, edit only the affected line(s) — never rewrite the profile wholesale.

## Phase 3: Wire this repo to a tracker (per-project, optional)

Ask the user whether the **current repo** should use GitHub Issues + a GitHub Project board as its task tracker. The pipeline skills (`facto:plan-implementation`, `facto:implement`, `facto:pr`) and the `task-start --issue` flag read tracker config from `.facto/settings.json` in the repo root; without it those behaviors silently degrade to no-op.

> "Do you want to use GitHub Issues + a Project board as the task tracker for this repo? If yes, I'll write a `.facto/settings.json` that wires it up."

**If no:** skip to Phase 4.

**If yes:** run a short sub-interview, one question at a time:

1. **GitHub repo slug** — default: `gh repo view --json nameWithOwner -q .nameWithOwner` from the current repo. Ask if the remote isn't set yet (e.g. `owner/repo`).
2. **GitHub Project** — ask:
   - Owner (default: the same GitHub user/org as the repo)
   - Display name (the project's title, e.g. `Notepad Pro Roadmap`)
   - Whether the project already exists. If it does, ask for its number. If it doesn't, offer to create it now — `gh project create --title "<name>" --owner "<owner>" --format json` — and read the `number` from the output.
3. **Status field name** — default: `Status`. Ask if they want a different name.
4. **Status option names** — default the five used in this factory (`Backlog`, `In progress`, `In review`, `In test`, `Done`). Ask whether to rename any.
5. **`pr_link_format`** — ask whether `facto:pr` should use `Resolves #{issue}` (auto-close on merge, GitHub default) or `Refs #{issue}` (no auto-close). Default: `Resolves #{issue}`.

Write `.facto/settings.json` in the repo root (`git rev-parse --show-toplevel`) with the answered values. Use this skeleton (substitute the user's answers):

```json
{
  "tracker": {
    "type": "github-issues",
    "repo": "<owner/repo or null to auto-resolve from origin>",
    "project": {
      "owner": "<owner>",
      "number": <number>,
      "name": "<display name>"
    },
    "status_field": "<status field name>",
    "status_values": {
      "backlog":     "<backlog name>",
      "in_progress": "<in-progress name>",
      "in_review":   "<in-review name>",
      "in_test":     "<in-test name>",
      "done":        "<done name>"
    },
    "branch_issue_pattern": "^[a-z]+/(?<issue>[0-9]+)-",
    "pr_link_format": "<Resolves #{issue} or Refs #{issue}>",
    "skill_signature_prefix": "{skill} says:",
    "labels": {
      "ignore": ["test-fi"]
    }
  }
}
```

To keep task planning docs somewhere other than the default `facto-tasks/`, add a top-level `"tasks_dir": "<relative-or-absolute-path>"` to this file. Omit it to use the default.

## Phase 4: Worktree hook stubs (per-project, optional)

Ask whether this repo needs per-task setup/teardown (install deps, copy `.env`, run migrations, start/stop services, free ports). If yes, create stub hooks in the repo's `.facto/` dir (don't overwrite existing ones):

- `.facto/worktree-setup.sh` — runs after `task-start` creates a worktree.
- `.facto/worktree-teardown.sh` — runs before `task-end` removes it.

Each receives the worktree path as `$1`. Seed them as executable no-op templates with commented examples, and tell the user to fill them in.

## Phase 5: Activate and verify

PATH/alias changes only take effect in new shells. Report to the user:

- The profile file the PATH block went in, and that they should open a new terminal (or `source` it) for `task-start`/`task-list`/`task-end` to work.
- Whether a tracker was configured, and if so the repo slug + Project written to `.facto/settings.json`. Verify it parses: `facto-helper.sh tracker.field repo` should print the repo slug.
- Which worktree hook stubs were created, if any.
