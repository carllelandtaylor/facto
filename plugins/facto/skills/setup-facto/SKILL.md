---
name: setup-facto
description: "Set up the Facto mechanics. Adds the task-* worktree commands to your shell PATH (once per machine), then optionally wires the current repo to a GitHub Issues + Project tracker by writing .facto/settings.json and dropping worktree setup/teardown hook stubs. Run it once after installing the facto plugin, and again in each new project you want tracker integration for. Invoke with /facto:setup-facto. Procedure skill (follow the phases in order)."
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
test -x "$FACTO_BIN/task-start.sh" || { echo "ERROR: resolved '$FACTO_BIN' but task-start.sh isn't there — is the facto plugin symlinked from your Facto checkout?" >&2; exit 1; }
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

Ask the user which tracker the **current repo** should use. The pipeline skills (`facto:plan-implementation`, `facto:implement`, `facto:pr`) and the `task-start --issue` / `--branch` flags read tracker config from `.facto/settings.json` in the repo root; without it those behaviors silently degrade to no-op.

> "Which task tracker should this repo use — GitHub Issues + a Project board, Linear, or none? If you pick one, I'll write a `.facto/settings.json` that wires it up."

Pull requests are GitHub PRs either way; only issue tracking varies.

**If none:** skip to Phase 4.

**If Linear:** go to "Phase 3b: Linear" below.

**If GitHub Issues:** run a short sub-interview, one question at a time:

1. **GitHub repo slug** — default: `gh repo view --json nameWithOwner -q .nameWithOwner` from the current repo. Ask if the remote isn't set yet (e.g. `owner/repo`).
2. **GitHub Project** — ask:
   - Owner (default: the same GitHub user/org as the repo)
   - Display name (the project's title, e.g. `Notepad Pro Roadmap`)
   - Whether the project already exists. If it does, ask for its number. If it doesn't, offer to create it now — `gh project create --title "<name>" --owner "<owner>" --format json` — and read the `number` from the output.
3. **Status field name** — default: `Status`. Ask if they want a different name.
4. **Status option names** — default the five used in Facto (`Backlog`, `In progress`, `In review`, `In test`, `Done`). Ask whether to rename any.
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

### Phase 3b: Linear

Linear is reached through its MCP server, which only agents can call — shell scripts cannot. Two consequences to state to the user before configuring anything:

- **`/facto:observe` is unavailable on Linear** in this release. It stops with an error on a Linear repo.
- **`task-start` cannot fetch from Linear.** Starting a task means pasting the branch name Linear generates (`task-start --branch <name>`) or giving an identifier plus words (`task-start --issue ENG-42 add csv export`). It also cannot set the issue's state; the first skill to pick the task up does that.

Then run the sub-interview:

1. **Workspace slug** — the segment in Linear URLs, e.g. `acme-labs` in `https://linear.app/acme-labs/issue/ENG-42/…`.
2. **Team** — the team's *name*, which is what the MCP tools accept. `list_teams` enumerates them.
3. **Team key** — the uppercase prefix in issue identifiers, e.g. `ENG` in `ENG-42`.
4. **Branch prefix** — the leading segment of Linear's generated branch names, usually the user's Linear username. Read it off any issue's `gitBranchName` via `get_issue` rather than guessing.
5. **Status mapping** — enumerate the team's real workflow states with `list_issue_statuses` and map Facto's five keys onto them. **Do not assume Linear's defaults exist.** Teams vary: a team may have no `In Review` state, and no Linear team has an equivalent of Facto's `In test`. For each Facto key with no natural counterpart, ask which existing state it should map onto and tell the user what that costs — e.g. mapping `in_review` onto `Done` means an issue reads Done from the moment a PR opens, not when it merges.
6. **`promote_from_status_types`** — the `statusType` values that count as "not started", so a skill beginning work knows what it may promote. Usually `["backlog", "unstarted"]`; confirm against the states enumerated above.
7. **`pr_link_format`** — ask whether to use a magic word (`Fixes {issue}`) so Linear can move the issue when the PR merges, or a plain reference (`{issue}`) for human readers only. Linear links the PR from the branch name regardless.

Write `.facto/settings.json` with the answered values:

```json
{
  "tracker": {
    "type": "linear",
    "workspace": "<workspace slug>",
    "team": "<team name>",
    "team_key": "<TEAM>",
    "branch_prefix": "<branch prefix>",
    "status_values": {
      "backlog":     "<backlog state>",
      "in_progress": "<in-progress state>",
      "in_review":   "<in-review state>",
      "in_test":     "<in-test state>",
      "done":        "<done state>"
    },
    "promote_from_status_types": ["backlog", "unstarted"],
    "branch_issue_pattern": "^[^/]+/(?<issue>[a-z][a-z0-9]*-[0-9]+)-",
    "pr_link_format": "<Fixes {issue} or {issue}>",
    "skill_signature_prefix": "{skill} says:",
    "labels": {
      "ignore": []
    }
  }
}
```

`repo`, `project`, and `status_field` are absent by design — Linear holds lifecycle state in per-team workflow states, not a project board with a single-select field.

Finally, tell the user how to connect the MCP server if it isn't already, and that they must authenticate before any skill can reach Linear:

```bash
claude mcp add --transport http --scope project linear https://mcp.linear.app/mcp
```

Then `/mcp` → `linear` → complete the OAuth login. Note that project scope writes `.mcp.json` at the repo root, which git worktrees only see once it is committed.

## Phase 4: Worktree hook stubs (per-project, optional)

Ask whether this repo needs per-task setup/teardown (install deps, copy `.env`, run migrations, start/stop services, free ports). If yes, create stub hooks in the repo's `.facto/` dir (don't overwrite existing ones):

- `.facto/worktree-setup.sh` — runs after `task-start` creates a worktree.
- `.facto/worktree-teardown.sh` — runs before `task-end` removes it.

Each receives the worktree path as `$1`. Seed them as executable no-op templates with commented examples, and tell the user to fill them in.

## Phase 5: Activate and verify

PATH/alias changes only take effect in new shells. Report to the user:

- The profile file the PATH block went in, and that they should open a new terminal (or `source` it) for `task-start`/`task-list`/`task-end` to work.
- Which tracker was configured, if any, and what was written to `.facto/settings.json`. Verify it parses with `facto-helper.sh tracker.field type`, which should print the configured type. Then check a tracker-specific field: `tracker.field repo` prints the repo slug on GitHub Issues; `tracker.field team` prints the team name on Linear. For Linear, also restate that the MCP server must be authenticated and that `/facto:observe` is unavailable.
- Which worktree hook stubs were created, if any.
