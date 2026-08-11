---
name: fix-bug
description: "Use this skill to fix a reported bug end-to-end and autonomously. Reproduces the bug (facto:repro-bug), diagnoses the root cause, fixes it with adaptive escalation (a direct commit for small/localized fixes; facto:plan-implementation + facto:implement for large/structural ones), verifies against the logged repro steps, opens a PR (facto:pr), and watches CI until green (facto:watch-and-fix-ci). Invoke with /facto:fix-bug. Procedure skill (follow the phases in order)."
color: red
---

# Bug Fix Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Fix a reported bug end-to-end with no developer intervention: reproduce it, find the real root cause, fix it (escalating to heavier tooling when the fix is large), verify the bug is gone without regressions, open a PR, and drive CI to green. Escalation is about heavier *tooling* for a bigger change — it is never a request for developer review; this skill runs autonomously start to finish.

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Understand & Locate` — activeForm: `Understanding and locating`
2. `Phase 2: Reproduce` — activeForm: `Reproducing the bug`
3. `Phase 3: Diagnose Root Cause` — activeForm: `Diagnosing root cause`
4. `Phase 4: Fix Loop` — activeForm: `Fixing the bug`
5. `Phase 5: Quality Pass` — activeForm: `Running quality pass`
6. `Phase 6: PR` — activeForm: `Creating the PR`
7. `Phase 7: Watch CI` — activeForm: `Watching CI`
8. `Phase 8: Summary` — activeForm: `Summarizing`

All tasks start as `pending`. At the start of each phase, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that phase, set it to `completed`.

---

## Input

You should have or be given:
- A bug to fix — a GitHub Issue number, or a free-text description of the symptom.
- Optionally: a maximum number of fix attempts, review cycles, and/or CI cycles (defaults: 5 each).

---

## Core Guardrails

- **Fix the root cause, not the symptom.** Trace to the actual cause; do not paper over the symptom (e.g. swallowing an error, special-casing the one input from the report).
- **Do not remove or alter working functionality to make the bug disappear.** The fix must not delete, disable, or weaken correct behavior just to silence the symptom. No regressions.
- **Add a regression test** that fails before the fix and passes after — where the project has a test suite. If the project has no tests, rely on the verified repro steps instead.
- **Work autonomously.** Don't stop for questions unless truly blocked — the main blocking case is being unable to reproduce the bug (Phase 2).

---

## Phase 1: Understand & Locate

Set the `Phase 1` task to `in_progress`.

- Read the bug: when given an issue, use `facto:ref-tracker`'s `resolve_active_issue` + `read_issue`; otherwise use the description you were given. Capture expected vs. actual behavior and the affected area.
- Find and trace the relevant code so you understand where the behavior lives.
- **Optional Status write (best-effort, warn-and-continue).** If the repo has an active issue tracker, promote the issue to in-progress following `facto:ref-tracker`'s "How to promote an issue to in-progress". The guard there matters: an issue already in review or done must not be moved backwards.

Set the `Phase 1` task to `completed`.

---

## Phase 2: Reproduce

Set the `Phase 2` task to `in_progress`.

- Launch a **subagent** (Agent tool, `model: "opus"`) and tell it to run `/facto:repro-bug` via the Skill tool, passing the issue identifier or description.
- Save the confirmed repro: minimal steps, preconditions, observed-wrong vs. expected, and evidence. You will verify the fix against exactly these steps.
- **If the bug cannot be reproduced**, STOP and report the "could not reproduce" result with what was tried. Do not attempt a speculative fix for a bug you cannot observe.

Set the `Phase 2` task to `completed`.

---

## Phase 3: Diagnose Root Cause

Set the `Phase 3` task to `in_progress`.

- Trace from the reproduced symptom to the **actual cause** in the code (not the surface location where it manifests).
- Write a one-line **root-cause statement** and a short **proposed fix approach**. These drive the next phase's path choice and (if escalated) seed the implementation plan.

Set the `Phase 3` task to `completed`.

---

## Phase 4: Fix Loop (Adaptive Escalation)

Set the `Phase 4` task to `in_progress`.

Choose the path with this checklist. **Escalate** if *any* of these holds:
- touches more than ~2 files, or shared/core logic many things depend on;
- introduces a new abstraction or interface;
- requires a schema / API / migration change;
- is otherwise large or multi-step.

Otherwise the fix is small/localized → **direct path**.

- **Direct path:** launch a **subagent** (`model: "sonnet"`) to make the edits (plus a regression test where the project has tests), then run `/facto:commit-or-amend` via the Skill tool with a clear message.
- **Escalated path:** run `/facto:plan-implementation` via the Skill tool in this context. Pass it the root cause, the logged repro steps, and the no-regression constraint (**do not remove or alter working functionality**). Then launch a **subagent** (`model: "opus"`) to run `/facto:implement` via the Skill tool (it bundles the review loop and PR creation).

**Verify against the logged repro steps:** re-run the exact reproduction. The fix is good only when the bug is gone **AND** nothing else regressed. If the bug persists or a regression appears, diagnose further and retry — bounded by the maximum fix attempts. After exhausting attempts, stop and report.

Set the `Phase 4` task to `completed`.

---

## Phase 5: Quality Pass

Set the `Phase 5` task to `in_progress`.

Ensure a review loop has run over the fix:
- **Direct path:** launch a **subagent** (`model: "opus"`) to run `/facto:review-loop-code` via the Skill tool over the fix commits (pass the root cause, repro steps, and validation).
- **Escalated path:** `/facto:implement` already ran the review loop — no separate pass needed.

Set the `Phase 5` task to `completed`.

---

## Phase 6: PR

Set the `Phase 6` task to `in_progress`.

- **If `/facto:implement` already opened the PR** (escalated path), ensure it is current.
- **Otherwise** (direct path), run `/facto:pr` via the Skill tool. Pass it the repro steps and the verification so they land in the PR body. Issue linking and the Verification section are handled by `/facto:pr` (it links the active Issue).

Set the `Phase 6` task to `completed`.

---

## Phase 7: Watch CI

Set the `Phase 7` task to `in_progress`.

- Launch a **subagent** (`model: "opus"`) to run `/facto:watch-and-fix-ci` via the Skill tool. It watches the PR's checks, fixes failures, and loops until green (bounded by the max CI cycles).
- If CI cannot be made green within the cycle budget, report it as stuck rather than thrashing.

Set the `Phase 7` task to `completed`.

---

## Phase 8: Summary

Set the `Phase 8` task to `in_progress`.

Report:
- **Bug** — what was reported.
- **Root cause** — the one-line statement.
- **Path taken** — direct vs. escalated, and why.
- **Verification** — outcome against the logged repro steps (bug gone, no regressions), and the regression test added (if any).
- **CI result** — green, or stuck with details.
- **PR URL.**

Set the `Phase 8` task to `completed`.
