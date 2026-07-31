---
name: watch-and-fix-ci
description: "Use this skill to make CI pass on the current branch's open PR. Watches the PR's checks, and when one fails, pulls its logs, reproduces the failure locally by re-running that check's own command, fixes the root cause, pushes via facto:iterate/facto:pr, and loops until every check is green. Usable standalone or as the final step of /facto:fix-bug. Invoke with /facto:watch-and-fix-ci. Procedure skill (follow the phases in order)."
color: purple
---

# CI Make-Green Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Watch CI on the current branch's open PR and drive it to green. For each failing check, read its logs, reproduce the failure locally by re-running that check's own command, fix the root cause, push the fix, and loop until all checks pass. A CI failure already names the exact command that failed, so reproduction is re-running that command — this skill does **not** use `/facto:repro-bug` (that is for app-level bugs without exact steps).

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Identify PR & Checks` — activeForm: `Identifying PR and checks`
2. `Phase 2: Wait for Checks` — activeForm: `Waiting for checks`
3. `Phase 3: Evaluate & Reproduce Locally` — activeForm: `Evaluating and reproducing failures`
4. `Phase 4: Fix & Push` — activeForm: `Fixing and pushing`
5. `Phase 5: Done` — activeForm: `Reporting CI status`

All tasks start as `pending`. At the start of each phase, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that phase, set it to `completed`. Phases 2–4 form a loop; re-open and re-run their tasks on each cycle as needed.

---

## Input

You should have or be given:
- The current branch with an **open PR** (detect via `gh pr view`).
- Optionally: a maximum number of fix cycles (default: 5).

---

## Phase 1: Identify PR & Checks

Set the `Phase 1` task to `in_progress`.

- Find the open PR for the current branch:
  ```bash
  gh pr view --json number,url,state
  ```
- **Stop conditions:** if there is no open PR (`state` is not `OPEN`, or the command fails), stop and report that there is no open PR to watch — there is nothing to make green.

Set the `Phase 1` task to `completed`.

---

## Phase 2: Wait for Checks

Set the `Phase 2` task to `in_progress`.

- Wait until the checks finish running (block, don't busy-poll tightly):
  ```bash
  gh pr checks <pr> --watch
  ```
  If `--watch` is unavailable or returns immediately, poll `gh pr checks <pr>` until nothing is `pending`/`in_progress`.
- **Tolerate "no checks configured":** if the PR has no checks at all, treat that as nothing to fix — go to Phase 5 and report that there are no checks. Do not hang waiting for checks that will never appear.

Set the `Phase 2` task to `completed`.

---

## Phase 3: Evaluate & Reproduce Locally

Set the `Phase 3` task to `in_progress`.

- Read the check results: `gh pr checks <pr>`.
- **If every check is green:** go to Phase 5 (Done).
- **Otherwise, for each failed check:**
  - Pull the failing logs: `gh run view <run-id> --log-failed` (use `gh pr checks` / `gh run list` to map the check to its run).
  - Identify the exact command the check ran (test / lint / type-check / build) and **reproduce the failure locally by re-running that same command** in the worktree.
  - Diagnose the **root cause** from the local failure — not just the surface error. This skill does NOT use `/facto:repro-bug`; a CI failure already names its failing command, so local re-run is the reproduction.

Set the `Phase 3` task to `completed`.

---

## Phase 4: Fix & Push

Set the `Phase 4` task to `in_progress`.

- Make the fix that addresses the root cause, and confirm the previously-failing command now passes locally.
- Push the update: run `/facto:iterate` (or `/facto:pr`) via the Skill tool to commit and push the fix and update the PR.
- Loop back to **Phase 2** to wait for the re-triggered checks.

Set the `Phase 4` task to `completed`.

---

## Phase 5: Done

Set the `Phase 5` task to `in_progress`.

Report:
- Final CI status (all green, or stopped with remaining failures).
- What was fixed in each cycle.
- How many cycles were used.
- The PR URL.

Set the `Phase 5` task to `completed`.

---

## Guardrails

- **Max cycles.** Stop after the configured maximum (default 5) and report the remaining failures — something may need human judgment.
- **Never disable or delete a legitimate test to make CI pass.** Fix the underlying cause. Skipping, deleting, or weakening a real assertion to turn a check green is not a fix and is forbidden.
- **Distinguish flaky from real.** If a failure looks like a flake (timeouts, network, ordering, known-intermittent), note it as a suspected flake; an optional single re-run is allowed to confirm. Do not paper over a real failure by calling it flaky.
- **Stop and surface if stuck.** If a check cannot be reproduced locally, keeps failing after a fix, or is outside the branch's control (e.g. infra/secrets), stop and report it clearly rather than thrashing.
