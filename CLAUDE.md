# CLAUDE.md

Quick reference for Claude Code working in this repo. Avoid duplicating info already in other documentation.

## Project contents

This repo is the Facto software factory — two Claude Code skills-directory plugins under `plugins/`:

- **`plugins/facto/`** — public plugin. Pipeline skills (`/facto:<name>`) in `skills/`; user-facing worktree scripts (`facto-helper.sh`, `task-start.sh`, …) in `bin/`.
- **`plugins/facto-dev/`** — developer-only plugin. The factory-improvement skills (`/facto-dev:<name>`) in `skills/`; developer scripts in `bin/`.

For factory **usage** (setup, workflows, the full skill catalog) see [README.md](README.md). For the factory's **design and improvement system** see [DEVELOPMENT.md](DEVELOPMENT.md).

## Per-task planning docs

All planning docs for one task (product requirements, design, architecture, implementation plan) live together in a single per-task directory: `tasks/<task-slug>/`, with fixed filenames (`product-requirements.md`, `design-decisions.html`, `design-mock.html`, `design-inventory.md`, `architecture.md`, `implementation-plan.md`). (This repo overrides the factory default `facto-tasks/` to `tasks/` via `"tasks_dir"` in `.facto/settings.json` — it dogfoods the override.) Resolve the directory with `facto-helper.sh task-dir` — never hand-build the slug. The producing skill commits its doc when the developer accepts it. Shared, product-wide inputs such as the files under `docs/design/` (the design system and the evergreen design docs) stay outside the task directory.

`<task-slug>` format: issue-backed tasks are `<issue-number>-<kebab-description>` (e.g. `111-c-observe`). Tasks with no issue are prefixed `UNKNOWN-` where the number would go (e.g. `UNKNOWN-c-design-mock`), so a missing issue is explicit rather than looking like a dropped number. This is consistent everywhere: `task-start.sh` names no-issue worktrees and branches the same way (`feat/UNKNOWN-…`), and `facto-helper.sh task-slug` normalizes any bare slug to the `UNKNOWN-` form.

## Issue tracking

Work in this repo is tracked as **GitHub Issues** on `carllelandtaylor/facto`, with lifecycle state held on the **[Facto GitHub Project](https://github.com/users/carllelandtaylor/projects/1)** (project #1). Every improvement Issue is also a project item; supporting observations are comments on the relevant Issue. Tracker config — repo, project owner/number/name, and the Status field/value names — lives in `.facto/settings.json`, the single source of truth read by `facto-helper.sh` and the skills. The hardcoded values named here just reflect that file.

Name feature branches `<type>/<issue#>-<slug>` so the Issue auto-links (`feat/42-csv-export`, `fix/57-login-redirect`, `chore/63-bump-deps`).

**Status field** — the single-select project field is the canonical lifecycle state; an Issue's open/closed is secondary and derivable from it:

| Status | Open/Closed | Meaning |
|---|---|---|
| **Backlog** | Open | No code change started yet. Agents may comment/observe without changing Status. |
| **In progress** | Open | An agent is actively working a solution; no PR up yet. |
| **In review** | Open | One or more solutions are up in a PR, not yet merged to main. |
| **In test** | Open | PR merged to main, but not enough signal yet that the improvement works. |
| **Done** | Closed | Merged + enough signal it works. Also the terminal state for `not-planned` closes. |

**Linking PRs:** put `Resolves #<Issue>` in the PR description (one line per Issue; multiple Issues are fine). It populates GitHub's "Linked pull requests" field and a timeline cross-reference, but does **not** auto-close on merge — that repo setting is disabled, so Status is what closes Issues.

**Labels:**

| Label | Purpose |
|---|---|
| `test-fi` | Marks plan-validation test Issues for bulk cleanup. Filtered out by all `facto-dev:*` skills; never written by automation. |
| `needs-review` | Triage flag for evidence that contradicts a recently-resolved Issue. Not lifecycle state. |
