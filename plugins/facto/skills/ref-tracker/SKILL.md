---
name: ref-tracker
description: "Documents the tracker operations Facto skills use to read and update the active issue — reading an issue, reading its lifecycle state, and setting that state — with a recipe per supported tracker (GitHub Issues, Linear). Reference skill (independent how-tos — use what you need, in any order)."
color: yellow
---

# Tracker Operations — Reference

> **Model:** when run as a subagent, prefer `model: sonnet`.

Facto works against one issue tracker per repo, chosen by `tracker.type` in the host repo's `.facto/settings.json`. This reference defines each tracker operation once, with a recipe per tracker, so the skills that need them do not each carry their own copy.

**This is a reference, not a procedure.** There's no required order — go to the operation you need.

Supported values of `tracker.type`:

| Value | Reached via | Notes |
|---|---|---|
| `github-issues` | `gh` CLI | The default when `.facto/settings.json` is absent. |
| `linear` | the Linear MCP server | Requires the server to be connected and authenticated. Not reachable from shell scripts. |

---

## Preamble: resolve the tracker once

Every operation below branches on the tracker type. Resolve it once per run:

```bash
TRACKER_TYPE="$(facto-helper.sh tracker.field type 2>/dev/null)"
[[ -z "$TRACKER_TYPE" ]] && TRACKER_TYPE="github-issues"
```

Config field availability differs by tracker. `repo`, `project.*`, and `status_field` exist only for `github-issues`; `workspace`, `team`, `team_key`, `branch_prefix`, and `promote_from_status_types` exist only for `linear`. `status_values.*`, `branch_issue_pattern`, `pr_link_format`, and `skill_signature_prefix` exist for both.

---

## Invariants

These hold for every operation and every tracker. They are the contract callers rely on.

1. **Status writes are best-effort.** A failed write warns and continues — it never aborts the calling skill. The skill's actual deliverable is the code, the plan, or the PR; the bookkeeping is secondary.
2. **The promotion guard belongs to the caller, not to `set_issue_status`.** `set_issue_status` writes what it is told. Deciding *whether* to promote an issue to in-progress — and only doing so when the issue has not been started — is the caller's job, because only the caller knows it is beginning work. See "How to promote an issue to in-progress" for the guard itself.
3. **Missing tracker config is not an error.** If `facto-helper.sh tracker.exists` fails or `resolve_active_issue` yields nothing, skip the operation and carry on. A repo with no tracker is a supported configuration.

---

## `resolve_active_issue`

Returns the identifier of the issue the current worktree or branch is for, or nothing. Tracker-independent — `facto-helper.sh` already knows how to read both forms.

```bash
ISSUE=""
if facto-helper.sh tracker.exists 2>/dev/null; then
  ISSUE="$(facto-helper.sh current-issue 2>/dev/null)" || ISSUE=""
fi
```

The shape of `$ISSUE` depends on the tracker: a bare number on `github-issues` (`113`), a team-scoped identifier on `linear` (`SIO-9`, already uppercased). Pass it through to the other operations unchanged — none of them need it parsed.

---

## `read_issue`

Fetch the issue's title, body, and comments, for use as context.

### `github-issues`

```bash
REPO_SLUG="$(facto-helper.sh tracker.field repo)"
gh issue view "$ISSUE" --repo "$REPO_SLUG" --json title,body,comments
```

### `linear`

Two calls — `get_issue` does not return comments:

1. `get_issue` with `id` set to `$ISSUE` — returns the title and description. It also returns `gitBranchName`, Linear's canonical branch name for the issue, if a caller needs it.
2. `list_comments` with `issueId` set to `$ISSUE` — returns the comments.

---

## `get_issue_status`

Read the issue's current lifecycle state.

### `github-issues`

State lives in the Project board's single-select field, not on the Issue itself:

```bash
PROJECT_NAME="$(facto-helper.sh tracker.field project.name)"
REPO_SLUG="$(facto-helper.sh tracker.field repo)"
CURRENT_STATUS="$(gh issue view "$ISSUE" --repo "$REPO_SLUG" --json projectItems \
  | jq -r --arg n "$PROJECT_NAME" \
    '[.projectItems[]? | select(.title == $n) | .status.name] | first // ""')"
```

Yields a status *name* comparable to `status_values.*`, or an empty string when the issue is not on the board.

### `linear`

`get_issue` with `id` set to `$ISSUE`. Two fields matter:

- `status` — the state's display name, comparable to `status_values.*`.
- `statusType` — the state's category (`backlog`, `unstarted`, `started`, `completed`, `canceled`, `duplicate`). Compare against this rather than the name wherever the logic is about what kind of state it is, since names are workspace-specific and renameable.

---

## `set_issue_status <status_values key>`

Move the issue to the state configured for one of Facto's five lifecycle keys: `backlog`, `in_progress`, `in_review`, `in_test`, `done`. Resolve the key through config rather than hardcoding a state name:

```bash
TARGET_NAME="$(facto-helper.sh tracker.field "status_values.<key>")"
```

Per Invariant 1, every failure path here warns and continues.

### `github-issues`

Resolve the project, field, and option IDs dynamically — hardcoded IDs break if the project is recreated:

```bash
PROJECT_OWNER="$(facto-helper.sh tracker.field project.owner)"
PROJECT_NUMBER="$(facto-helper.sh tracker.field project.number)"
STATUS_FIELD_NAME="$(facto-helper.sh tracker.field status_field)"
REPO_SLUG="$(facto-helper.sh tracker.field repo)"

PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json | jq -r .id)"
FIELD_JSON="$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json \
  | jq --arg name "$STATUS_FIELD_NAME" '.fields[] | select(.name == $name)')"
FIELD_ID="$(echo "$FIELD_JSON" | jq -r .id)"
OPTION_ID="$(echo "$FIELD_JSON" | jq -r --arg n "$TARGET_NAME" '.options[] | select(.name == $n) | .id')"
ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 200 \
  | jq -r --argjson num "$ISSUE" '.items[] | select(.content.type == "Issue" and .content.number == $num) | .id')"

if [[ -z "$ITEM_ID" ]]; then
  ITEM_ID="$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
    --url "https://github.com/$REPO_SLUG/issues/$ISSUE" \
    --format json | jq -r .id)"
fi

gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID" \
  >/dev/null 2>&1 || echo "Warning: could not set Issue #$ISSUE Status -> $TARGET_NAME"
```

`--argjson num` requires a numeric identifier, which is why this recipe is GitHub-only. Paginate `item-list` if the board holds more than 200 items.

### `linear`

`save_issue` with `id` set to `$ISSUE` and `state` set to `$TARGET_NAME`. `state` accepts a state name, so no ID lookup is needed. `list_issue_statuses` with `team` set to `tracker.team` enumerates the team's states if a caller needs to check what exists.

**Several Facto keys may resolve to the same Linear state.** Linear teams have no built-in equivalent of Facto's *In test*, and a team may lack *In Review* as well, so `in_review`, `in_test`, and `done` can all map onto `Done`. Asking for any of them then produces the same write. That is expected, not a bug — the configured mapping is authoritative.

---

## How to promote an issue to in-progress

The common caller pattern: a skill beginning work moves the issue to in-progress, but only if nobody has started it. Promoting an issue that is already in review or done would move it backwards.

1. `get_issue_status`.
2. Decide whether the issue counts as not-yet-started:
   - **`github-issues`** — the status name equals `status_values.backlog`.
   - **`linear`** — the `statusType` is one of `tracker.promote_from_status_types` (typically `backlog` and `unstarted`). Linear teams commonly have both a *Backlog* and a *Todo* state, and an issue resting in either has not been started, so matching on the backlog name alone would silently skip the *Todo* case.
3. If so, `set_issue_status in_progress`. Otherwise do nothing.

---

## How to link a PR to the active issue

Build the line from config rather than hardcoding a format:

```bash
LINK_LINE="$(facto-helper.sh tracker.field pr_link_format | sed "s/{issue}/$ISSUE/")"
```

`pr_link_format` is `Resolves #{issue}` on `github-issues` (yielding `Resolves #113`) and typically `Fixes {issue}` on `linear` (yielding `Fixes SIO-9`).

The two trackers link differently, which affects what the line is for. GitHub populates its "Linked pull requests" field from this line. Linear links the PR from the *branch name* when it contains the issue identifier, so the line is mostly for human readers there — though a magic word in it may also move the issue on merge, depending on the team's PR automation settings.
