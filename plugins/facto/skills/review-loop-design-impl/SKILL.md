---
name: review-loop-design-impl
description: "Use this skill to make an implementation's UI/UX match its design. When a design mock exists, it screenshots both the mock and the running app, compares them dimension-by-dimension against a structured rubric, and runs a capped fix loop until the implementation matches — reporting any infeasible divergences. When no mock exists, it falls back to a sanity check that flags anything visually broken or wrong. Invoke with /facto:review-loop-design-impl. Procedure skill (follow the phases in order; Phase 1 selects which path to run)."
color: purple
---

# Design Implementation Review Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Make the UI you built match the design — not approximately, but precisely. When there's a mock to compare against, keep fixing the differences until the implementation matches it; comparison is the means, a matching UI is the goal. The failure mode this prevents is shipping a UI with visible differences from the mock because nobody compared them carefully and corrected them. A claim of "looks right" without screenshot evidence is not acceptable.

## Input

None — this skill resolves what it needs itself.

---

## Phase 1: Detect the Design Spec (Path Selection)

Resolve the task directory: `TASK_DIR="$(factory.sh task-dir 2>/dev/null)"`. If that fails, fall back to any design-mock path the caller passed. Then pick the path:
- **A `design-mock.html` was found** — run the mock-comparison path: Phases A1–A6.
- **No `design-mock.html` and no mock path** — run the no-mock path: **Phase B1: Sanity Check** instead.

## Phase A1: Enumerate In-Scope Screens/States

From `design-mock.html` (its labeled frames/bands) and `design-decisions.html` (screen inventory, states, copy), list the specific screens and states the implementation should reproduce. Cover only the screens this task touched — never the whole app.

## Phase A2: Render the Mock

Read `/facto:ref-design-mock` for the exact serve/inspect mechanics and follow them. Save the mock screenshots to disk.

## Phase A3: Render the Implementation

Launch the real app and navigate to each in-scope screen/state, capturing a screenshot at a viewport matching the corresponding mock frame. Launch the app via a **subagent** using the Agent tool, telling it to use the project's documented launch method (from the plan, CLAUDE.md, or project docs) — **never call the Skill tool directly from within this skill** (see Guardrails). If the app cannot be brought up (no runnable UI surface, missing tooling, or launch fails after a reasonable attempt), do not stall: record a `manual-described` fallback — a per-screen checklist telling the developer exactly what to eyeball against the mock — report it to the caller, and stop.

## Phase A4: Compare (Structured, Evidence-Required)

Launch a dedicated comparison **subagent** (`model: "opus"`) per screen (or batched across screens), giving it the matched mock screenshot, the implementation screenshot, and the relevant design-system tokens. Instruct it to evaluate **every** dimension explicitly and emit a verdict for each — never a blanket "looks good":
- layout & structure (presence, order, alignment, grouping of elements)
- spacing & sizing (margins, padding, element dimensions, proportions)
- color & theme tokens (backgrounds, text, borders, states — light and dark if both are mocked)
- typography (family, size, weight, line-height, letter-spacing)
- iconography & imagery (correct icons/assets, sizing, placement)
- copy/text (exact wording, capitalization, punctuation)
- component states (default/hover/active/disabled/empty/error/loading as mocked)
- observable transitions/interactions (where feasible to capture)

It returns a **structured discrepancy list** — for each finding: `screen`, `dimension`, `severity` (blocking / minor), `classification` (fixable / infeasible), and a short `note` describing the gap and the mock's intent. Infeasible means the mock cannot be built as shown given a real dependency/platform limitation or an impossibility in the design itself; the note must say *why* and what the closest faithful approximation is.

## Phase A5: Fix Loop (Capped, Convergent)

While blocking, fixable discrepancies remain and you are below the cap (3 cycles):
- Fix them in a **subagent** (`model: "sonnet"`), staying within the touched UI's scope.
- Have a subagent (`model: "sonnet"`) run `/facto:commit-or-amend` via the Skill tool, passing the base ref and the fixes' context.
- Re-render the affected implementation screens and re-run the comparison subagent on them.
- Stop when no blocking, fixable discrepancies remain, or the cap is hit.

Fix minor discrepancies opportunistically, but they do not block completion. Never loop on **infeasible** discrepancies — record them (with reason + closest approximation) for the report instead.

## Phase A6: Clean Up and Report

Stop the HTTP server and close the browser/app. Report to the caller:
- Which screens were compared
- The final per-screen result: matched / minor gaps / blocking gaps unresolved at the cycle cap
- The full list of infeasible divergences with reasons and closest approximations
- The manual-described fallback checklist, if one was produced

---

## Phase B1: Sanity Check (No-Mock Path)

Run this phase *instead of* Phases A1–A6, only when Phase 1 found no design mock. Launch the app and inspect all UI surfaces the task modified for anything that looks broken or wrong.

1. **Identify modified UI surfaces.** From the plan and git diff, identify the screens, components, and states this task changed.

2. **Launch the app and screenshot.** Launch the real app via a **subagent** (same as Phase A3). Navigate to each modified UI surface and capture a screenshot. If the app cannot be brought up, record a `manual-described` fallback checklist and report to the caller.

3. **Inspect.** Launch a **subagent** (`model: "opus"`) with the screenshots. Instruct it to flag anything that looks broken or visually wrong — layout problems, clipped or overflowing content, misaligned elements, missing content, obvious rendering errors, anything that reads as a bug to a user. There is no reference to compare against; the bar is "does this look intentional and working?"

4. **Report.** Stop the HTTP server and close the app. Report which screens were inspected, what issues were found (or "no issues found"), and the manual fallback checklist if the app couldn't be launched.

---

## Guardrails

- **Never call the Skill tool directly from within this skill.** When this skill needs to run another skill (e.g. `/facto:commit-or-amend`), launch a **subagent** using the Agent tool and tell the subagent to invoke the sub-skill via the Skill tool.
- **Stay within the in-scope screens.** Never compare the whole app — only screens the task touched.
- **Evidence is mandatory.** Real on-disk screenshots of both mock and implementation are required before comparison.
- **Infeasible means infeasible.** If a design element genuinely can't be built (platform limitation, impossible mock), record it with a reason and the closest approximation — don't loop forever trying to achieve it.
