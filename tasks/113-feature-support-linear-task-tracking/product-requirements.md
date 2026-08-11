# Product Requirements: Linear Task Tracking

**Feature area:** Task tracker support — using Linear instead of GitHub Issues as the issue tracker a Facto-managed repo works against.
**Issue:** [#113 — FEATURE: Support Linear task tracking](https://github.com/carllelandtaylor/facto/issues/113)
**Created:** 2026-08-11

---

## The Problem

Facto hardwires GitHub Issues plus a GitHub Project board as the only tracker a repo can use. The coupling is spread across the whole product:

- `.facto/settings.json` carries a GitHub repo slug and a GitHub Project owner/number/name, with lifecycle state held in that Project's single-select `Status` field.
- `facto-helper.sh` derives the active issue from the branch name, assuming a numeric issue number.
- `task-start.sh` fetches the issue with `gh issue view` and writes its Project status with `gh project item-edit`.
- Six skills embed literal `gh` commands to read issues or move their status: `observe`, `pr`, `implement`, `fix-bug`, `plan-implementation`, and `setup-facto`.

A developer whose work lives in Linear cannot use Facto against it at all. There is no partial path — the tracker is assumed, not configured.

This is being built now because the developer is evaluating Linear for their own work and wants Facto to keep working during and after that move.

## Who This Is For

The developer of this repo, working on their own projects. This is not a response to demand from other Facto adopters, and no second user's Linear setup is being designed for.

Concretely, that means:

- One Linear workspace, one team per repo.
- Interactive use from a terminal, with a Claude Code session that has the Linear MCP server connected and authenticated.
- Pull requests still live on GitHub. Only issue tracking moves to Linear.

## What Users Want to Accomplish

- Run a complete Facto task against a Linear-tracked repo: start a worktree, plan, implement, open a PR, and have the Linear issue's state move correctly along the way.
- Choose a tracker per repo through configuration, not by editing skills or scripts.
- Keep using Linear's own conventions — its branch names, its identifiers, its workflow states — so that Facto fits into Linear rather than fighting it.
- Have every existing GitHub-tracked repo keep behaving exactly as it does today.

## Feature Overview

`.facto/settings.json` gains a `tracker.type` of `"linear"` alongside the existing `"github-issues"`. Exactly one tracker is active per repo; there is no mixed mode and no per-skill override.

On a Linear repo, skills reach Linear through the official Linear MCP server (OAuth). Shell scripts cannot call MCP tools, so `task-start.sh` does not talk to Linear at all — the developer supplies the issue identity directly, normally by pasting the branch name Linear generates. `observe` is not supported on Linear in this release and refuses to run there.

Branch names follow Linear's own format so that Linear's automatic PR linking works without extra configuration.

## Core Features (In Scope)

### 1. Linear tracker configuration

`.facto/settings.json` accepts `tracker.type: "linear"`. The Linear shape carries the workspace and team key, a Linear-appropriate `branch_issue_pattern`, a `pr_link_format`, and `status_values` naming Linear workflow states. The GitHub-only `repo` and `project` blocks are absent.

Everything already read through `facto-helper.sh tracker.field` continues to work, since that accessor is a generic jq path lookup.

### 2. Lifecycle state mapping

Facto's five states map onto Linear's built-in team workflow states. Linear has no equivalent of Facto's **In test**, and it maps to **Done**.

| Facto state | Linear workflow state |
|---|---|
| Backlog | Backlog |
| In progress | In Progress |
| In review | In Review |
| In test | Done |
| Done | Done |

Accepted consequence: on Linear, an issue reaches its terminal state when its PR merges, rather than after evidence that the change works. The post-merge window in which an issue can be reopened on contradicting evidence does not exist on Linear. This is acceptable in this release because `observe`, the only skill that uses that window, is out of scope.

### 3. Branch naming and issue identity

Linear repos adopt Linear's own branch name format, e.g. `carllelandtaylor/sio-9-create-app-switcher`. The issue identifier (`SIO-9` — the team key plus a per-team sequential number) is recovered from the branch through the configured `branch_issue_pattern`.

Derived from that branch, the task slug and task directory drop the leading username segment: `tasks/sio-9-create-app-switcher`.

Accepted consequence: Linear's format puts the author's username where Facto puts a `feat/` / `fix/` / `chore/` type prefix, so branch typing is not visible in Linear repos and `task-start.sh` no longer infers a type from issue labels.

### 4. `task-start.sh` on Linear

`task-start.sh` gains a `--branch` flag and extends `--issue`. The two flags are alternatives — exactly one may be given, and supplying both is an error.

- **`--branch <name>`** — use this branch name verbatim. This is the normal Linear path: copy the branch name from the Linear issue and paste it. The issue identifier is extracted via `branch_issue_pattern`. Also accepted on GitHub repos, where it simply names the branch.
- **`--issue <value>`** — an issue identifier. On GitHub, a number or an issue URL, fetched as today. On Linear, an identifier plus description words (`--issue SIO-9 create app switcher`), from which the branch is constructed in Linear's format.

On a Linear repo, `task-start.sh` performs no network calls to Linear. It does not fetch the issue and does not set its state. `task.json` records the identifier and whatever title the developer supplied.

Accepted consequences: a mistyped identifier produces a plausible-looking branch that links to nothing; `task.json` holds the typed title rather than the canonical one; and the issue is not moved to In progress at task start. The last is largely covered already, because `implement` and `fix-bug` both move a Backlog issue to In progress when they begin.

Error messages for `--issue` state which forms are valid for the configured tracker.

### 5. Issue-reading skills

`plan-implementation` and `fix-bug` read the active issue's title, body, and comments to ground their work. Both do so on Linear via MCP.

### 6. Status-writing skills

- `implement` and `fix-bug` move a Backlog issue to In progress when they begin work.
- `pr` inserts the tracker-appropriate issue-link line into the PR body using `pr_link_format`, and moves the issue to In review once the PR is created.

On Linear these go through MCP. As today, all status writes are best-effort: a failure warns and continues rather than aborting the skill.

### 7. `observe` refuses to run on Linear

`observe` is not supported on Linear in this release. On a repo with `tracker.type: "linear"` it exits with an error that names the limitation. It must not run partially, create Linear issues, or silently do nothing.

### 8. `setup-facto` can wire a repo to Linear

`setup-facto`'s tracker phase asks which tracker the repo should use. For Linear it collects the workspace and team key, writes the Linear config shape, prints the exact command for adding the Linear MCP server, and reminds the developer to authenticate. It also states that `observe` is unavailable on Linear.

### 9. No regression on GitHub

Every repo configured with `tracker.type: "github-issues"` behaves exactly as it does today, including this repo and the `facto-dev` plugin. This is a hard requirement on the release, not a goal.

### 10. Documentation and tests

README and CLAUDE.md describe tracker selection, the Linear config shape, the `--branch` flag, and the `observe` limitation. `plugins/facto/bin/tests` covers the new flag handling, the Linear branch pattern, and identifier extraction.

## User Workflows

### Wiring an existing repo to Linear

1. Developer adds the Linear MCP server to their Claude Code setup and authenticates via OAuth.
2. Developer runs `/facto:setup-facto` in the repo.
3. The skill asks which tracker; the developer picks Linear and gives the workspace and team key.
4. The skill writes `.facto/settings.json` with the Linear tracker shape and reports what it wrote, including that `observe` is unavailable.

### Running a task on a Linear repo

1. Developer opens the issue in Linear and copies its git branch name.
2. `source task-start.sh --branch carllelandtaylor/sio-9-create-app-switcher` creates the worktree and branch, and writes `task.json`. Nothing is sent to Linear.
3. Developer runs `/facto:plan-product`, `/facto:plan-design`, and `/facto:plan-implementation`; planning docs land in `tasks/sio-9-create-app-switcher/`. `plan-implementation` reads `SIO-9` from Linear for context.
4. `/facto:implement` moves `SIO-9` from Backlog to In progress, does the work, and opens a PR.
5. `pr` puts the Linear link line in the PR body and moves `SIO-9` to In review. Linear also links the PR automatically from the branch name.
6. PR merges. The developer moves `SIO-9` to Done in Linear.

### Starting a task without the Linear UI open

1. Developer knows the identifier but is not looking at Linear.
2. `source task-start.sh --issue SIO-9 create app switcher` builds the same branch in Linear's format from the identifier plus the typed words.
3. Everything downstream is identical to the workflow above.

## Success Criteria

- A full task can be run end to end on a Linear-tracked repo — worktree, planning docs, implementation, PR — with the Linear issue moving Backlog → In progress → In review without manual state edits.
- `--branch` is a single paste from Linear, with no retyping of the identifier or title.
- Linear links the PR to the issue automatically, with no manual linking.
- Choosing a tracker requires editing only `.facto/settings.json`.
- Running `observe` on a Linear repo produces a clear error, never a partial or silent result.
- Every GitHub-tracked repo, including this one, behaves identically to before the change.

## Out of Scope

- **`observe` on Linear.** The largest piece of work in the area — a routing and dedup engine over issue lists and status, plus issue creation, commenting, and autonomous closes. Deferred so the build path ships sooner. It errors on Linear instead.
- **Migrating existing GitHub issues into Linear.** Linear's own importer does this better.
- **More than one Linear team per repo.**
- **`task-end.sh` setting Done on merge.** It does not write status today on GitHub either.
- **`facto-dev`.** It tracks the Facto repo itself on GitHub and stays GitHub-only.
- **Any Linear access path other than MCP**, including giving `task-start.sh` the ability to fetch from Linear via an API key.
- **Preserving a distinct In test state on Linear**, e.g. by creating a custom workflow state in the developer's team.

## Future Enhancements

- `observe` on Linear, which would make Facto's improvement loop work there.
- A distinct In test workflow state on Linear, restoring the post-merge window where an issue can be reopened on contradicting evidence. Only useful together with `observe`.
- An API-key access path, which would let `task-start.sh` fetch the issue and set its state, and would let Facto run against Linear non-interactively — in cron jobs or headless agents.
- Support for additional trackers such as Jira, if the tracker abstraction proves to hold.

## Open Questions

- Which Linear workflow states exist in the developer's actual team, and whether their names match the defaults assumed by the mapping in Core Feature 2. If they differ, `status_values` records the real names and nothing else changes.
- What `pr_link_format` should be for Linear. Linear recognises reference forms in a PR's title and description, and the branch name already links the PR, so the line may be for human readers rather than for Linear.
- Whether `--branch` should be rejected when the given name does not match `branch_issue_pattern`, or accepted with a warning and treated as a no-issue task.
