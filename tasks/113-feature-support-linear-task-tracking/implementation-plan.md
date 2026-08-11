# Implementation Plan: Linear Task Tracking

**Based on:** [product-requirements.md](product-requirements.md) (2026-08-11) and [Issue #113](https://github.com/carllelandtaylor/facto/issues/113). No design docs — this feature has no UI.
**Created:** 2026-08-11

---

## Prerequisites — SATISFIED 2026-08-11

The Linear MCP server is installed at project scope (`/home/carltaylor/git/facto/.mcp.json`, currently untracked) and authenticated. Discovery is complete; the values below are read from the live workspace, not assumed.

**Workspace and team**

| Value | Discovered |
|---|---|
| Workspace slug | `carl-social-impact-org` |
| Team | "Social Impact Org" (the workspace's only team) |
| Team key | `SIO` |
| Branch prefix | `carllelandtaylor` |
| `gitBranchName` sample | `carllelandtaylor/sio-9-create-app-switcher` (issue `SIO-9`) |

The sample confirms the `branch_issue_pattern` below matches real Linear branch names unchanged.

**Team workflow states** — `Backlog` (backlog), `Todo` (unstarted), `In Progress` (started), `Done` (completed), `Duplicate` (duplicate), `Canceled` (canceled).

There is **no `In Review` state**, so `in_review` maps onto `Done` (see Decisions Taken).

**Linear MCP tools** — verified against the connected server, not guessed:

| Operation | Linear MCP call |
|---|---|
| `read_issue` | `get_issue(id)` for title/description, `list_comments(issueId)` for comments |
| `get_issue_status` | `get_issue(id)` — returns `status` (name) and `statusType` (category) |
| `set_issue_status` | `save_issue(id, state)` — `state` accepts a state type, name, or ID |
| enumerate states | `list_issue_statuses(team)` |

`get_issue` also returns `gitBranchName`, so skills can read Linear's canonical branch name even though `task-start.sh` cannot.

**One caveat if `.mcp.json` stays untracked:** it lives in the main checkout's working directory, so worktree sessions will not load it. Committing it makes it appear in every checkout.

---

## Decisions Taken

Settled during planning; recorded here so the implementation does not relitigate them.

| Decision | Choice | Why |
|---|---|---|
| Where GitHub/Linear branching lives | A new `facto:ref-tracker` reference skill defining each operation once, with a GitHub recipe and a Linear recipe | Matches existing precedent (`ref-design-mock`, `ref-design-system`). The inline `gh` blocks are ~20 lines each in four skills; duplicating them per tracker doubles that and lets the copies drift. |
| PR link format on Linear | `Fixes {issue}` | Linear's magic words move the issue on merge, which removes the one manual step left in the PRD's workflow. Reversible via config if the automation is unwanted. |
| Branch construction for `--issue KEY words` | New `tracker.branch_prefix` config field supplies the username segment | Deterministic, and byte-identical to what Linear's copy button produces, so both entry points yield the same branch for the same issue. |
| Identifier case | `facto-helper.sh current-issue` uppercases the identifier when `tracker.type` is `linear` | Branch names carry `sio-9`; Linear's canonical form is `SIO-9`. Normalizing once in the helper keeps every caller from doing it. |
| `task.json` shape | Keep the `issue_number` field; write a JSON string on Linear, a number on GitHub | Smallest change. `facto-helper.sh current-issue` reads it with `jq -r`, so both types work, and no existing GitHub `task.json` changes type. |
| `--branch` with a name not matching `branch_issue_pattern` | Accept with a warning; treat as a no-issue task (`UNKNOWN-…`) | Consistent with how `_normalize_slug` already handles unrecognized slugs, and it is what makes `--branch` usable on GitHub for freely-named branches. |
| `in_review` with no `In Review` state in the team | Map onto `Done` | Developer's call, taken over adding a state to the Linear workspace. Consequence recorded in Risks: `pr` writes `in_review` at PR *creation*, so the issue reads Done from the moment a PR opens rather than when it merges. Changing it later is one config line. |
| Promotion guard on Linear | Fires when the issue is in `Backlog` **or** `Todo` | The GitHub guard promotes only from Backlog. Linear's `Todo` is a normal resting state in this team (SIO-5 sits there now), so a Backlog-only guard would silently never promote those issues. Match on `statusType` ∈ {`backlog`, `unstarted`} rather than on state names. |

## Canonical Linear config shape

Written by `setup-facto` in Step 6, and the reference for every step that reads config:

```json
{
  "tracker": {
    "type": "linear",
    "workspace": "carl-social-impact-org",
    "team": "Social Impact Org",
    "team_key": "SIO",
    "branch_prefix": "carllelandtaylor",
    "status_values": {
      "backlog":     "Backlog",
      "in_progress": "In Progress",
      "in_review":   "Done",
      "in_test":     "Done",
      "done":        "Done"
    },
    "promote_from_status_types": ["backlog", "unstarted"],
    "branch_issue_pattern": "^[^/]+/(?<issue>[a-z][a-z0-9]*-[0-9]+)-",
    "pr_link_format": "Fixes {issue}",
    "skill_signature_prefix": "{skill} says:",
    "labels": { "ignore": [] }
  }
}
```

`repo`, `project`, and `status_field` are absent — Linear holds lifecycle state in per-team workflow states, not a project board with a single-select field.

`team` carries the team *name* because that is what `list_issue_statuses` and `save_issue` accept; `team_key` carries `SIO` for identifier validation in `task-start.sh`.

Three of Facto's five states collapse onto `Done` in this team, so the observable lifecycle is `Backlog`/`Todo` → `In Progress` → `Done`. `promote_from_status_types` lists the `statusType` values the promotion guard treats as "not yet started"; matching on type rather than name keeps the guard working if the states are renamed.

---

## Step 1: Teach `facto-helper.sh` Linear identifiers

**Goal:** `task-slug`, `task-dir`, and `current-issue` handle Linear identifiers correctly, and `facto-helper.sh` has automated test coverage for the first time.

**Changes:**

- `plugins/facto/bin/facto-helper.sh`
  - `_normalize_slug` (line 77): widen the passthrough regex from `^([0-9]+|UNKNOWN)-` to also accept a Linear identifier segment, i.e. `^([0-9]+|UNKNOWN|[a-z][a-z0-9]*-[0-9]+)-`. Without this, `sio-9-create-app-switcher` is mangled to `UNKNOWN-sio-9-create-app-switcher`. Update the function comment to name the third accepted form.
  - `current-issue`: after a successful `BASH_REMATCH` match, uppercase the captured identifier when `.tracker.type` is `linear`. Read the type via the same `--root`-propagating pattern already used for `branch_issue_pattern` (lines 216–220). Leave the `task.json` path alone — Step 2 writes the identifier already uppercased, and re-uppercasing is a no-op.
  - Header comment block (lines 22–30): note that `current-issue` returns a GitHub issue number or a Linear identifier.

- `plugins/facto/bin/tests/facto-helper.test.sh` (new)
  - Follow the shape of `task-start.test.sh`: `set -eo pipefail`, a pass/fail counter pair, one function per case printing `PASS: <case>` / `FAIL: <case>`, non-zero exit if any case fails. Self-contained — build a disposable git repo with `git init`, write `.facto/settings.json` variants into it, and invoke the script under test by path with `--root`.
  - Cases: numeric slug passes through; `UNKNOWN-` slug passes through; Linear slug `sio-9-foo` passes through unchanged; a bare description gets `UNKNOWN-` prefixed; `current-issue` returns `113` from a GitHub branch; `current-issue` returns `SIO-9` (uppercased) from `carl/sio-9-foo` with Linear config; `current-issue` exits non-zero on a branch matching neither; `task-dir` honors `tasks_dir` for a Linear slug.

**Validation:**
- [ ] `bash plugins/facto/bin/tests/facto-helper.test.sh` — every case prints `PASS`, exit 0.
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines. Confirms the existing four suites still pass.
- [ ] In this repo (GitHub config, branch `feat/113-…`): `facto-helper.sh current-issue` still prints `113` and `facto-helper.sh task-dir` still prints the `113-…` path.

**Commit message:**
```
feat: accept Linear issue identifiers in facto-helper.sh

Context:
Linear identifies issues as <TEAM-KEY>-<number> (e.g. SIO-9) rather than a
bare number, so _normalize_slug rejected Linear task slugs and prefixed them
with UNKNOWN-. Widens the slug regex to accept that form and uppercases the
identifier returned by current-issue when the tracker is Linear, since branch
names carry it lowercased. Adds the first test suite for this script.

Verification:
Automated:
  bash plugins/facto/bin/tests/facto-helper.test.sh
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
Manual:
  1. From this worktree run `facto-helper.sh current-issue` — prints 113.
  2. Run `facto-helper.sh task-dir` — path ends in /tasks/113-feature-support-linear-task-tracking.
```

---

## Step 2: Add `--branch` and Linear `--issue` to `task-start.sh`

**Goal:** a Linear task can be started from a pasted branch name or an identifier plus words, with no network calls to Linear.

**Changes:**

- `plugins/facto/bin/task-start.sh`
  - **Parse `--branch <name>`** alongside `--issue`. Error if both are supplied: `Error: --branch and --issue are mutually exclusive.` Error if `--branch` has no value, matching the existing `--issue` style.
  - **Resolve tracker type once**, after the `facto-helper.sh` availability check: `_ts_tracker_type="$(facto-helper.sh tracker.field type 2>/dev/null)"`, defaulting to `github-issues` when unset so config-free repos are unaffected.
  - **Gate the GitHub fetch block** (lines 94–128) on `_ts_tracker_type == "github-issues"`. The `repo` lookup and the `gh issue view` call must not run for Linear.
  - **Linear `--issue` path:** accept a value matching `^[A-Za-z][A-Za-z0-9]*-[0-9]+$`, uppercase it into `_ts_issue_number`, and require at least one description word (error otherwise, since there is no title to fetch: `Error: --issue <KEY> on a Linear repo requires description words, e.g. --issue SIO-9 create app switcher.`). Set `_ts_issue_url` to empty and `_ts_issue_title` to the joined words. Reject a bare number on a Linear repo with a message naming the valid forms.
  - **Branch construction for Linear:** `_ts_branch="${branch_prefix}/${identifier,,}-${_ts_title_slug}"`, where `branch_prefix` comes from `facto-helper.sh tracker.field branch_prefix`. If `branch_prefix` is empty, omit the segment and warn once that the branch will not match Linear's copy-button format. Skip the `feat`/`fix` prefix inference entirely on Linear — that convention does not apply.
  - **`--branch` path:** use the value verbatim as `_ts_branch`. Derive the slug by stripping the leading `<segment>/` (the existing `${branch#*/}` idiom). Extract the identifier by matching the slug against `branch_issue_pattern` with the same named-group-stripping `sed` that `facto-helper.sh` uses; on no match, warn (`Warning: <name> does not match this repo's branch_issue_pattern — starting as a no-issue task.`) and leave `_ts_issue_number` empty so the `UNKNOWN-` convention applies. Uppercase the identifier on Linear.
  - **`task.json` (line 197):** switch `--argjson n` to `--arg n` when the identifier is non-numeric, keeping `--argjson` for GitHub so existing files keep their number type. Skip the `issue_url` field's value when empty rather than writing `""`… keep writing it for shape stability, but leave it empty on Linear.
  - **Status write (lines 206–237):** wrap the whole block in `if [[ "$_ts_tracker_type" == "github-issues" ]]`. On Linear, print one line instead: `Note: Linear status is not set by task-start; /facto:implement or /facto:fix-bug will move SIO-9 to In Progress.`
  - **Token promotion (line 66):** widen the `^[0-9]+$` guard so `task-start issue SIO-9 …` is promoted too.
  - **Final summary (line 253):** print `Issue: SIO-9` when there is no URL.
  - Add the new variables to the `unset` list at the end.
  - Update the usage comment block at the top with `--branch` and the Linear `--issue` form.

- `plugins/facto/bin/tests/task-start.test.sh`
  - The existing stub `facto-helper.sh` must answer `tracker.field type` and `tracker.field branch_prefix`; make its responses switchable per case via an env var the stub reads, so GitHub and Linear cases share one stub.
  - New cases: `--branch carl/sio-9-create-app-switcher` yields branch `carl/sio-9-create-app-switcher`, slug `sio-9-create-app-switcher`, and `gh` never called (assert via the existing `_GH_SENTINEL`); `--branch` with a non-matching name warns and produces an `UNKNOWN-` slug; `--issue SIO-9 create app switcher` on Linear yields `carl/sio-9-create-app-switcher`; `--issue SIO-9` with no words errors; `--issue 123` on a Linear repo errors; `--branch` plus `--issue` errors; `task.json` holds the string `SIO-9`; and the existing GitHub cases still pass unchanged.

**Validation:**
- [ ] `bash plugins/facto/bin/tests/task-start.test.sh` — every case prints `PASS`, exit 0, including all pre-existing GitHub cases.
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines.
- [ ] Manual, in this GitHub repo: `source task-start.sh --issue 113` still creates `feat/113-…` and sets Status. Then `task-end` the throwaway worktree.

**Commit message:**
```
feat: start tasks from a Linear branch name or identifier

Context:
Bash cannot call MCP tools, so task-start.sh cannot reach Linear the way it
reaches GitHub through gh. Instead the developer supplies the issue identity:
--branch takes the branch name Linear's copy button produces and uses it
verbatim, and --issue takes an identifier plus description words. Both skip
the fetch and the status write on Linear; the GitHub path is unchanged and
still gated on tracker.type.

Verification:
Automated:
  bash plugins/facto/bin/tests/task-start.test.sh
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
Manual:
  1. In this repo run `source task-start.sh --issue 113` — creates feat/113-…
     and sets Status to In progress, exactly as before.
  2. Run `task-end` on that worktree to clean up.
```

---

## Step 3: Make `observe` refuse to run on Linear

**Goal:** running `/facto:observe` on a Linear repo fails immediately with a clear message, never partially.

**Changes:**

- `plugins/facto/skills/observe/SKILL.md`
  - At the very top of the tracker-resolution section (before the `REPO_SLUG` lookup at line 26), add a guard: read `facto-helper.sh tracker.field type`; if it is `linear`, stop and tell the developer that `observe` does not support Linear in this release, that the tracker is configured as Linear in `.facto/settings.json`, and that GitHub-tracked repos are unaffected. Do not create issues, comment, or write status.
  - Word it as a hard stop, not a preference — this is the one place a partial run would create junk in a real Linear workspace.

- `plugins/facto/skills/observe/tests/skill-structure.test.sh` (new)
  - Model on `plugins/facto/skills/review-loop-code/tests/skill-structure.test.sh`: read `SKILL.md` and assert the guard's markers are present — that `tracker.field type` and `linear` appear before the first `REPO_SLUG` assignment. Guards against a future edit silently dropping the check.

**Validation:**
- [ ] `bash plugins/facto/skills/observe/tests/skill-structure.test.sh` — every case prints `PASS`, exit 0.
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines; confirms the run-all glob picks up the new suite.
- [ ] Manual: temporarily set `.facto/settings.json` `tracker.type` to `linear`, run `/facto:observe`, confirm it stops with the message and writes nothing. Revert the config.

**Commit message:**
```
feat: stop facto:observe from running on Linear repos

Context:
observe is out of scope for Linear in this release — it is a routing and dedup
engine built on gh issue list plus project Status, with issue creation and
autonomous closes. Rather than run partially against a tracker it cannot read,
it now hard-stops when tracker.type is linear. A structure test keeps a future
edit from dropping the guard.

Verification:
Automated:
  bash plugins/facto/skills/observe/tests/skill-structure.test.sh
Manual:
  1. Set tracker.type to "linear" in .facto/settings.json.
  2. Run /facto:observe — it stops with the unsupported message and creates
     no Issues, comments, or Status writes.
  3. Revert .facto/settings.json.
```

---

## Step 4: Add the `facto:ref-tracker` reference skill

**Prerequisites are satisfied** — the tool names below are verified against the connected server. Do not substitute assumed names.

**Goal:** every tracker operation is defined once, with a recipe per tracker. Nothing calls it yet, so this step cannot regress anything.

**Changes:**

- `plugins/facto/skills/ref-tracker/SKILL.md` (new) — a reference skill (independent how-tos), following the conventions in `facto-dev:ref-skill-writing`. It defines four operations, each with a `github-issues` recipe and a `linear` recipe, and a preamble showing how a caller resolves `TRACKER_TYPE="$(facto-helper.sh tracker.field type)"` and branches on it:

  1. **`resolve_active_issue`** — tracker-agnostic; `facto-helper.sh tracker.exists` then `facto-helper.sh current-issue`. Returns a GitHub number or a Linear identifier (already uppercased by Step 1).
  2. **`read_issue`** — title, body, and comments. GitHub: the existing `gh issue view "$ISSUE" --repo "$REPO_SLUG" --json title,body,comments`. Linear: `get_issue(id: "$ISSUE")` for title and description, then `list_comments(issueId: "$ISSUE")` for comments — two calls, since `get_issue` does not return comments.
  3. **`get_issue_status`** — the issue's current lifecycle state. GitHub: the existing `gh issue view --json projectItems` + `jq` snippet from `fix-bug`, returning a state name. Linear: `get_issue(id: "$ISSUE")`, returning both `status` (the name, comparable to `status_values.*`) and `statusType` (the category, which is what the promotion guard compares against `promote_from_status_types`).
  4. **`set_issue_status <status_values key>`** — GitHub: the existing `gh project view` / `field-list` / `item-list` / `item-edit` sequence, moved here verbatim so behavior is byte-identical. Linear: `save_issue(id: "$ISSUE", state: "<resolved name>")`, resolving the target through `status_values`. `state` accepts a name, so no ID lookup is needed; `list_issue_statuses(team)` exists if a caller ever needs to enumerate.

  Document three invariants that callers rely on today and must keep: status writes are **best-effort — warn and continue**, never fatal; the conditional promotion guard belongs to the caller, not to `set_issue_status`; and the guard compares `statusType` against `promote_from_status_types` on Linear, versus the Backlog state name on GitHub.

  Document the Linear-specific notes: `in_review`, `in_test`, and `done` all resolve to `Done` in this workspace, so a caller asking for any of them produces the same write; there is no `repo` or `project` field to read; and `get_issue` also returns `gitBranchName` if a caller needs Linear's canonical branch name.

**Validation:**
- [ ] `facto-helper.sh tracker.field type` returns `github-issues` in this repo — confirms the accessor the skill's preamble depends on.
- [ ] The GitHub recipes are byte-identical to the snippets currently in `pr`, `implement`, and `fix-bug`: `diff` the moved blocks against the originals before Step 5 deletes them.
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines.

**Commit message:**
```
feat: add facto:ref-tracker reference skill

Context:
Four skills each embed the same ~20 lines of gh commands to read an Issue or
move its Status. Supporting a second tracker inline would duplicate all of it
and let the copies drift, so the operations are defined once here with a
recipe per tracker, following the ref-design-mock/ref-design-system pattern.
The GitHub recipes are moved verbatim; the Linear recipes use the MCP tool
names read from the connected server. Nothing calls this yet — Step 5 does.
```

---

## Step 5: Point the four tracker-touching skills at `ref-tracker`

**Goal:** `pr`, `implement`, `fix-bug`, and `plan-implementation` work against either tracker, with GitHub behavior unchanged.

**Changes:**

- `plugins/facto/skills/plan-implementation/SKILL.md` — replace the "Optional: Active Issue context" block (lines 44–58) with a call to `ref-tracker`'s `resolve_active_issue` + `read_issue`. Keep the existing degradation rule verbatim: never block planning on issue retrieval.
- `plugins/facto/skills/fix-bug/SKILL.md` — Phase 1's `gh issue view` becomes `read_issue`; the inline status block (lines 53–80) becomes `get_issue_status` + conditional `set_issue_status in_progress`. The guard stays in the skill, and gains its Linear form: promote when `statusType` is in `promote_from_status_types` (`backlog` or `unstarted`), versus the existing Backlog-name comparison on GitHub.
- `plugins/facto/skills/implement/SKILL.md` — same treatment for its status fallback (lines 53–76), including the same two-form guard.
- `plugins/facto/skills/pr/SKILL.md` — the "Active Issue link + Status write" section (lines 202–224) calls `resolve_active_issue` and `set_issue_status in_review`. The `pr_link_format` substitution already handles both trackers, so on Linear it yields `Fixes SIO-9`; update the section's worked example to show both forms. Leave the update-path no-write rule untouched — it must keep applying to both trackers.

**Validation:**
- [ ] `grep -rn "gh project\|gh issue view" plugins/facto/skills/{pr,implement,fix-bug,plan-implementation}/SKILL.md` returns nothing — all tracker calls now go through `ref-tracker`.
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines.
- [ ] Manual, GitHub no-regression, on this repo's own PR for this branch: run `/facto:pr` and confirm the body still gets `Resolves #113` and Issue #113 moves to In review on the project board.

**Commit message:**
```
refactor: route tracker operations through facto:ref-tracker

Context:
Moves the inline gh blocks out of pr, implement, fix-bug, and
plan-implementation and points them at the ref-tracker recipes added in the
previous commit. GitHub behavior is unchanged — the recipes are the same
commands — and the same four skills now work against Linear.

Verification:
Automated:
  grep -rn "gh project\|gh issue view" plugins/facto/skills/{pr,implement,fix-bug,plan-implementation}/SKILL.md
  (expected: no matches)
Manual:
  1. Run /facto:pr on this branch — the PR body contains "Resolves #113".
  2. Check the Facto project board — Issue #113 is In review.
```

---

## Step 6: Teach `setup-facto` to wire a Linear repo

**Goal:** `/facto:setup-facto` can configure a repo for Linear end to end.

**Changes:**

- `plugins/facto/skills/setup-facto/SKILL.md` — Phase 3 (lines 61–105):
  - Ask which tracker the repo should use rather than assuming GitHub Issues.
  - GitHub branch: unchanged.
  - Linear branch: collect the workspace slug, team name, team key, and branch prefix. Enumerate the team's real workflow states with `list_issue_statuses(team)` and map `status_values` onto what actually exists rather than assuming Linear's defaults — this workspace has no `In Review`, and another will differ again. Where a Facto state has no counterpart, ask which existing state to map it onto and record the consequence. Set `promote_from_status_types` from the `statusType` values of the states the developer considers "not started". Write the shape from this plan's "Canonical Linear config shape" section.
  - Print the exact command for adding the Linear MCP server and remind the developer to authenticate, noting that skills cannot reach Linear until that is done.
  - State plainly in the Phase 3 output that `/facto:observe` is unavailable on Linear in this release.
  - Update the Phase 5 report (line 126) to name the tracker type it wrote.
- `plugins/facto/skills/setup-new-project/SKILL.md` (line 154) — the Development Workflow section records which tracker, not just whether Facto's GitHub tracker is used.

**Validation:**
- [ ] Manual: run `/facto:setup-facto` against a scratch repo, choose Linear, and confirm the written `.facto/settings.json` parses (`jq . .facto/settings.json`) and matches the canonical shape.
- [ ] `facto-helper.sh --root <scratch-repo> tracker.field type` prints `linear`, and `tracker.field status_values.in_review` prints the configured name.
- [ ] Re-run against a scratch repo choosing GitHub; confirm the output is identical to before this change.

**Commit message:**
```
feat: let setup-facto wire a repo to Linear

Context:
Phase 3 previously assumed GitHub Issues plus a Project board. It now asks
which tracker and writes the matching config: for Linear, the workspace, team
key, branch prefix, and the team's real workflow state names, with in_test
mapped onto Done since Linear has no equivalent state. Also prints the MCP
setup command and states that observe is unavailable on Linear.

Verification:
Manual:
  1. Run /facto:setup-facto in a scratch repo, choose Linear.
  2. `jq . .facto/settings.json` parses; tracker.type is "linear".
  3. `facto-helper.sh --root <scratch> tracker.field status_values.in_review`
     prints the configured state name.
```

---

## Step 7: Document Linear support

**Goal:** the docs describe tracker selection, the Linear config, the new flags, and the `observe` limitation.

**Changes:**

- `README.md` — the tracker bullets (lines 37, 101) say GitHub Issues *or* Linear. The command reference (lines 127–129) documents `task-start --branch <name>` and the Linear `--issue <KEY> <words>` form. Add a short "Choosing a tracker" subsection with both config shapes side by side and the `observe` limitation.
- `CLAUDE.md` — the Issue tracking section states this repo uses GitHub Issues and that Linear is the alternative for projects using Facto, so an agent reading it does not assume GitHub universally. Note that `<task-slug>` may be `<issue-number>-…` or `<team-key>-<number>-…`.
- `DEVELOPMENT.md` §4.2 — add the two new suites to the table (`facto-helper.test.sh`, `observe/tests/skill-structure.test.sh`) and update "five self-contained `*.test.sh` files" to seven.

**Validation:**
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — the count of suites run matches the number claimed in DEVELOPMENT.md §4.2.
- [ ] Every command shown in the README's new text is one that exists in `task-start.sh`'s argument parser.

**Commit message:**
```
docs: document Linear tracker support

Context:
Covers tracker selection, both config shapes, task-start's --branch flag and
Linear --issue form, and the fact that facto:observe is GitHub-only in this
release. Also refreshes the DEVELOPMENT.md test-suite table for the two
suites added by this work.
```

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Bash arg parsing, git worktree scripting | high | `--branch` is a single paste; correct branch, worktree, slug | automated (Step 2) |
| jq / JSON config schema | high | Choosing a tracker requires editing only `.facto/settings.json` | automated (Steps 1, 6) |
| Claude Code skill authoring | high | `observe` errors on Linear, never partial or silent | automated (Step 3) |
| GitHub CLI issue/project commands | high | Every GitHub repo behaves identically to before | automated (all steps) + manual (Step 5) |
| Linear conventions — identifiers, branch format, workflow states | high (verified against the live workspace) | Linear links the PR to the issue automatically | manual-described |
| Linear MCP server tool surface | high (schemas read from the connected server) | Full task end to end, states move Backlog/Todo → In Progress → Done | manual-described |

## Risks

1. **`in_review` → `Done` marks issues complete at PR creation, not at merge.** `pr` writes `in_review` when it opens the PR, so the Linear issue reads `Done` from that moment. A PR closed without merging leaves the issue incorrectly in `Done`, and "has a PR up" is not distinguishable from "shipped" anywhere in Linear. Accepted by the developer over adding an `In Review` state to the team; reversible by changing one line of `status_values`.
2. **No Linear-side verification is possible until a real task runs.** The tool schemas and workspace values are now verified, but no criterion that exercises the full pipeline has been executed. Every Linear row above stays `manual-described` until the first real Linear task. This is why Steps 1–3 — the fully automatable half — come first.
3. **Linear's PR-linking behavior is assumed, not tested.** `Fixes {issue}` is expected to link the PR and move the issue on merge, but the exact behavior depends on the team's PR automation settings. Since `in_review` already writes `Done` at PR creation, a failure here is close to invisible — the issue is already `Done` by then. Verify on the first real Linear PR that the *link* appears; if it does not, only `pr_link_format` changes.
4. **Step 5 touches a working GitHub path.** Moving the `gh` blocks into `ref-tracker` risks a transcription error in code used daily. Mitigated by moving the snippets verbatim in Step 4 and diffing them against the originals before Step 5 deletes them, plus the manual GitHub no-regression check on this branch's own PR.
5. **No CI and no linter.** `.github/` holds only issue templates, and `shellcheck` is not installed. Every validation is a suite run by hand, so a step that skips its validation gets no second chance to catch the problem.

## Test Plan

- [ ] All suites pass: `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines.
- [ ] New suites pass individually: `bash plugins/facto/bin/tests/facto-helper.test.sh` and `bash plugins/facto/skills/observe/tests/skill-structure.test.sh`.
- [ ] No linter, type checker, or build exists in this repo — nothing to run.
- [ ] Manual verification — GitHub no-regression (criterion: every GitHub repo behaves identically):
  - [ ] `facto-helper.sh current-issue` prints `113` in this worktree; `task-dir` resolves under `tasks/113-…`.
  - [ ] `source task-start.sh --issue 113` in the main checkout creates `feat/113-…` and moves Issue #113 to In progress. Clean up with `task-end`.
  - [ ] `/facto:pr` on this branch produces a body containing `Resolves #113` and moves Issue #113 to In review.
  - [ ] `/facto:observe` still runs normally here.
- [ ] Manual verification — Linear (criterion: full task end to end). Run against a real `SIO` issue in a repo configured per the canonical shape:
  - [ ] `source task-start.sh --branch carllelandtaylor/sio-9-create-app-switcher` creates the worktree, names the branch verbatim, derives slug `sio-9-create-app-switcher`, and writes `task.json` with `issue_number` as the string `"SIO-9"`.
  - [ ] `source task-start.sh --issue SIO-9 create app switcher` produces the byte-identical branch name.
  - [ ] `facto-helper.sh current-issue` prints `SIO-9`, uppercased, from that branch.
  - [ ] `/facto:plan-implementation` reads the issue's description and comments for context.
  - [ ] `/facto:implement` moves the issue to `In Progress`. Repeat starting from an issue in `Todo` (e.g. SIO-5) to confirm the widened promotion guard fires there too, not just from `Backlog`.
  - [ ] `/facto:pr` puts `Fixes SIO-9` in the body; Linear shows the PR linked to the issue, and the issue moves to `Done` (expected at PR creation — see Risk 1).
  - [ ] `/facto:observe` stops with the unsupported message and writes nothing to Linear.
