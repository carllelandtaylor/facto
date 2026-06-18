---
name: repro-bug
description: "Use this skill to reproduce a reported bug in the running app and capture precise, repeatable reproduction steps. Brings up the app, drives it until the bug is observed (exploring when the report lacks exact steps), then distills the minimal repeatable sequence and evidence — or reports a clean 'could not reproduce'. Usable standalone or as the first step of /facto:fix-bug. Invoke with /facto:repro-bug. Procedure skill (follow the phases in order)."
color: yellow
---

# Bug Reproduction Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Reproduce a reported bug in the running application and return a precise, repeatable reproduction sequence — preconditions, exact ordered actions, observed-wrong vs. expected behavior, and supporting evidence. If the bug cannot be reproduced within a bounded effort, say so explicitly and report what was tried. Never guess that a bug reproduces without observing it.

## Supporting Files

- **Reproduction report template** — the structure and format to follow for the result: [repro-template.md](repro-template.md)

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Understand the Report` — activeForm: `Understanding the report`
2. `Phase 2: Bring Up the App` — activeForm: `Bringing up the app`
3. `Phase 3: Attempt Reproduction` — activeForm: `Attempting reproduction`
4. `Phase 4: Confirm & Distill` — activeForm: `Confirming and distilling repro steps`
5. `Phase 5: Report` — activeForm: `Reporting the result`

All tasks start as `pending`. At the start of each phase, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that phase, set it to `completed`.

---

## Input

You should have or be given:
- A bug to reproduce — a GitHub Issue number, or a free-text description of the symptom
- Optionally: a bounded effort cap (how many reproduction attempts / how long to explore before giving up). Default: a reasonable bounded exploration (roughly 8–10 distinct attempts) before reporting "could not reproduce".

---

## Phase 1: Understand the Report

Set the `Phase 1` task to `in_progress`.

- If given an issue number, read the full report with `gh issue view <n>` (include comments: `gh issue view <n> --comments`). Otherwise use the free-text description provided.
- Extract the essentials:
  - **Expected behavior** — what should happen.
  - **Actual behavior** — what goes wrong (the symptom).
  - **Affected area** — which screen, command, endpoint, or module is involved.
  - Any preconditions, inputs, environment, or exact steps the report already provides.
- If the affected area is a visual view with an evergreen spec at `docs/design/<surface>/views/<view>/<view>.html` (discoverable via `docs/design/index.md`, per `/facto:ref-design-system`), use it as the authority for intended design: read it for the intended behaviour and states, and — when the bug is about *appearance* (layout, spacing, color, alignment) — **render** the spec (serve + Playwright screenshot, per `/facto:ref-design-mock`) and compare it against a render of the running app while reproducing, rather than judging intent from the markup.
- Search the codebase for the relevant code (by feature name, route, error string, command, or UI label) so you know where the behavior lives and what to watch while reproducing.

Set the `Phase 1` task to `completed`.

---

## Phase 2: Bring Up the App

Set the `Phase 2` task to `in_progress`.

- Find how this project runs. Look for a project-specific run skill or instructions, then the README / docs; defer to the built-in `run` skill where it fits the project type. Identify the start command(s) and any prerequisites (deps, env, migrations, seed data).
- Start the necessary services and confirm the app is up before driving it.
- Pick the driver that matches the affected area:
  - **Web UI** — Playwright MCP: `browser_navigate`, `browser_snapshot`, `browser_take_screenshot`, and the interaction tools (`browser_click`, `browser_type`, etc.).
  - **CLI / API** — run the command directly, or `curl` the endpoint.
  - **Library / internal logic** — a small targeted script or a focused test that exercises the code path.

Set the `Phase 2` task to `completed`.

---

## Phase 3: Attempt Reproduction

Set the `Phase 3` task to `in_progress`.

- **If the report has exact steps**, follow them precisely and observe whether the bug occurs.
- **If the report lacks exact steps**, form a hypothesis about what triggers the bug from the affected area and the code you traced, then explore: vary inputs, preconditions, data, ordering, and edge values likely to surface the symptom.
- Watch for the symptom in the right place (UI state, response body, exit code, logs, output).
- Stay within the bounded effort cap. Track what you have tried so you can either confirm the bug or report precisely what was attempted.

Set the `Phase 3` task to `completed`.

---

## Phase 4: Confirm & Distill

Set the `Phase 4` task to `in_progress`.

Once you observe the bug, both goals must be met before you finish: **confirm it reproduces** AND **log a repeatable sequence**.

- Reduce the path to the **minimal precise repeatable sequence** — drop any step that is not required to trigger the bug.
- Record, exactly:
  - **Preconditions / data** — required state, fixtures, env, accounts.
  - **Ordered actions** — the exact numbered steps, with the precise input/click/command at each.
  - **Observed (wrong) result** vs. **expected result**.
- Capture **evidence** — a screenshot, log excerpt, command output, or response body that shows the wrong behavior.
- Re-run the minimal sequence once to confirm it reliably reproduces. If it only reproduces intermittently, note that and the observed frequency.

Set the `Phase 4` task to `completed`.

---

## Phase 5: Report

Set the `Phase 5` task to `in_progress`.

Return the structured result using [repro-template.md](repro-template.md): Bug, Environment / preconditions, Reproduction steps (numbered), Observed result, Expected result, Evidence, and Reproduced? (yes/no + notes).

- **If reproduced:** mark `Reproduced? yes` and include the minimal steps and evidence.
- **If not reproduced after the effort cap:** mark `Reproduced? no`, and state explicitly what was tried (paths, inputs, variations) and any hypotheses for why it did not surface. Do **not** guess or claim a reproduction you did not observe.

Set the `Phase 5` task to `completed`.
