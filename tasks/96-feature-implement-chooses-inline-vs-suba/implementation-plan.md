# Implementation Plan: `facto:implement` chooses inline vs subagent execution per step

**Created:** 2026-07-31
**Task:** `96-feature-implement-chooses-inline-vs-suba`
**Based on:** GitHub Issue [#96](https://github.com/carllelandtaylor/facto/issues/96) — "FEATURE: implement chooses inline vs subagent execution per step". No PRD or design doc exists for this task; the Issue body is the requirements input.
**Also read:** `DEVELOPMENT.md` (§1.3 Facto principles, §2.1 skill conventions, §4.2 testing), root `CLAUDE.md`, `OKRS.md`, `facto-dev:ref-skill-writing`.

---

## Summary

`facto:implement` always spawns a subagent per plan step. In the `moodmaker-mythos-test` three-build comparison the orchestrator overhead around those subagents (triage, dispatch, re-validating each subagent's claims — 262 Opus messages over a growing conversation) plus per-agent cold-start cache reads cost ~$37, while the eight step subagents themselves cost $16.35. The plan's steps were a strict dependency chain, so the fan-out bought zero wall-clock.

This change makes the mode a per-step judgment call the orchestrator makes and can revise mid-build. It is a documentation change to three files. No scripts, no new skills, no new tests.

## Decisions made with the developer

1. **Where the choice lives** — a new numbered item in `implement` Phase 1, plus a short re-evaluation rule in Phase 2. No new skill, no helper script.
2. **How prescriptive** — very concise and judgment-framed. Named considerations are examples, not a checklist. The implement agent decides.
3. **Default** — none. The skill instructs the agent to decide; it does not name a default and does not state that there is no default.
4. **Parallelism** — steps stay sequential. A subagent buys no wall-clock, so parallelism is not a reason to pick one. Concurrent dispatch would need per-step worktree isolation (two writers in one worktree violates DEVELOPMENT.md principle 1) and belongs in its own Issue.
5. **Committing in inline mode** — inline steps call `/facto:commit-or-amend` directly, in context, with no subagent. A commit-only subagent measured ~32k tokens during this change's own build — 55–77% of a full step subagent's cost (42–59k) — so paying it on every inline step defeated the point of going inline. The Core Rule that forbade calling the Skill tool from within `implement` is **deleted**, not amended: a rule stating a prohibition and then carving an exception out of it was more confusing than useful. The individual phases still say when to launch a subagent (Phase 2e, Phase 3), which is what the reader actually needs. *(Supersedes the original decision 5, which routed the commit through a small Sonnet subagent to preserve that rule. Both this and the deletion were decided after the plan was accepted and implemented.)*
6. **Tests** — no new test suite. Verified by review and a dogfood build. See Risks.
7. **Reporting** — the Phase 4 Summary reports which steps ran in which mode and any mid-build switches.

## Out of scope

- Requiring `facto:plan-implementation` to annotate step footprints (files touched, dependencies). The developer explicitly declined this.
- Concurrent execution of independent steps.
- Facto-side cost tracking.

---

## Step 1: Make execution mode a per-step choice in `facto:implement`

**Goal:** `facto:implement` decides per step whether to implement inline or in a subagent, can revise that choice mid-build, validates identically either way, and reports the modes used.

**Changes — all in `plugins/facto/skills/implement/SKILL.md`:**

- **Line 3 (frontmatter `description`)** — replace "Implements each step with a separate subagent" with wording that states the choice, e.g. "Chooses per step whether to implement inline or in a subagent". Keep the rest of the sentence and keep the trailing type tag `Procedure skill (follow the phases in order).` character-for-character.

- **Phase 1 (`## Phase 1: Before Starting`, lines 40–86)** — insert a new numbered item **5**, "Choose the execution mode", before the existing item 5 ("Create per-step tasks"), which becomes item 6. Keep it to roughly five or six lines. It must:
  - instruct the agent to decide, per step, between implementing inline in this context and implementing in a subagent, and to record the choice;
  - state the trade-off plainly — a subagent isolates context and survives a long build; inline avoids the per-step cold start and the overhead of dispatching and re-checking another agent's work;
  - name repo size and expected build length as *examples* of what might tip the decision, explicitly not a checklist;
  - note that steps run in order either way, so a subagent buys no wall-clock.

  It must not name a default mode, and must not contain a sentence asserting that there is no default — it just tells the agent to decide.

- **Phase 2 step c (lines 112–124)** — retitle `#### c. Implement in a Subagent` to `#### c. Implement`. Rewrite the body as:
  - one sentence telling the agent to re-evaluate this step's mode before implementing it and switch if the build has changed (a step larger than planned, or a context long enough that compaction is a risk);
  - an **Inline** branch: make the code changes in this context, then run `/facto:commit-or-amend` via the Skill tool in this context with the step's commit message and context. (Superseded decision 5: as originally written this step launched a subagent to run `/facto:commit-or-amend`.)
  - a **Subagent** branch: the existing instructions, preserved as-is (what to give the subagent — full step description, project guidelines, prior-step context, commit message; and what the subagent should do — make the changes, run `/facto:commit-or-amend` via the Skill tool, not modify anything outside the step's scope).

- **Phase 2 step d (line 127)** — change the opening from "After the subagent completes, run the step's validation instructions yourself" to mode-neutral wording that states validation is the same regardless of mode, e.g. "After the step's changes are committed, run the step's validation instructions yourself — identically in either mode". Leave the three bullets below it unchanged.

- **Phase 4 Summary (lines 209–216)** — add a new numbered item **5**, "Execution mode", reporting which steps ran inline vs in a subagent and any mid-build switches. "Decisions and problems" becomes item 6.

**Do not change:** Phase 2 step e (Handle Failures), Phase 3, or any other phase. (Superseded decision 5: the Core Rule was originally on this list; it is now deleted from the skill entirely.)

**Validation:**
- [ ] `bash -c 'for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done'` — all four suites print `PASS` lines and no `FAILED:` line. (These suites do not cover SKILL.md; this confirms nothing else broke.)
- [ ] `grep -n 'separate subagent' plugins/facto/skills/implement/SKILL.md` — no output.
- [ ] `grep -n 'Procedure skill (follow the phases in order).' plugins/facto/skills/implement/SKILL.md` — matches line 3, unchanged.
- [ ] `grep -n 'Never call the Skill tool directly' plugins/facto/skills/implement/SKILL.md` — no output. The `## Core Rules` list has four bullets, none about Skill-tool invocation.
- [ ] Read Phase 1 and Phase 2 top-to-bottom: the numbered items in Phase 1 run 1–6 with no duplicates or gaps; Phase 4's items run 1–6.
- [ ] Read the new Phase 1 item: it does not name a default mode and contains no sentence asserting there is no default.
- [ ] The new Phase 1 item is at most six lines.

**Commit message:**
```
feat: let facto:implement choose inline or subagent execution per step

Context:
facto:implement always spawned a subagent per plan step, which cost more
in orchestrator overhead (dispatch, re-validating each subagent's claims,
per-agent cold-start cache reads) than the step agents themselves on a
chain-shaped build. The skill now decides per step, revisable mid-build,
and reports the modes used. Inline mode still commits through a small
subagent so the no-nested-Skill-call rule holds. Steps stay sequential.

Verification:
Automated:
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
  grep -n 'separate subagent' plugins/facto/skills/implement/SKILL.md
Manual:
  1. Read Phase 1 — items number 1-6, the new item 5 tells the agent to
     decide the mode and names no default.
  2. Read Phase 2c — it has an Inline branch and a Subagent branch, and
     both end in /facto:commit-or-amend via a subagent.
  3. Read Phase 2d — validation wording is mode-neutral.
  4. Read Phase 4 — the summary reports execution mode per step.
```

---

## Step 2: Update the docs that assert subagent-per-step

**Goal:** `README.md` and `DEVELOPMENT.md` no longer describe `facto:implement` as unconditionally spawning a subagent per step.

**Changes:**

- **`README.md:198`** (under `##### /facto:implement`) — currently opens "Hands the plan to subagents and runs autonomously: implements each step, …". Replace the opening so it describes the choice, e.g. "Runs the plan autonomously: implements each step — inline or in a subagent, whichever it judges better for the build — …". Keep the rest of the sentence (validates after each, commits via `/facto:commit-or-amend`, runs `/facto:review-loop-code`, creates a PR via `/facto:pr`) intact.

- **`DEVELOPMENT.md:70`** (the worked example for principle 4, "Skills as the primary primitive") — currently "`facto:implement` is a skill that spawns Sonnet subagents per step rather than relying on a custom `implement-worker` agent definition." Reword so the example still makes principle 4's point (transient subagents, not a custom agent definition) without asserting per-step-always — e.g. "spawns transient Sonnet subagents when a step warrants one". Do not change principle 4's statement or its *Why:* line.

**Do not change:** `README.md:69` (the pipeline list), `README.md:224` (`fix-bug`'s own escalation description — that is a different mechanism), `DEVELOPMENT.md:64` and `:76` (they reference `facto:implement` but make no claim about subagent-per-step), or `OKRS.md`.

**Validation:**
- [ ] `bash -c 'for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done'` — no `FAILED:` line.
- [ ] `grep -rn 'subagents per step\|Hands the plan to subagents' README.md DEVELOPMENT.md` — no output.
- [ ] `git diff HEAD~1 --stat` shows only `README.md` and `DEVELOPMENT.md`.
- [ ] Read `DEVELOPMENT.md` principle 4 in full — the example still illustrates "subagents are transient workers, not first-class building blocks".
- [ ] Read the `README.md` `/facto:implement` entry — it matches the behavior now described in `plugins/facto/skills/implement/SKILL.md`.

**Commit message:**
```
docs: stop describing facto:implement as subagent-per-step

Context:
facto:implement now chooses inline or subagent execution per step, so
README's skill catalog entry and DEVELOPMENT.md's principle-4 example
were stale. The principle-4 example still makes its point — subagents
are transient workers, not custom agent definitions — without claiming
one is spawned for every step.
```

---

## Test Plan

- [ ] All project test suites pass:
  ```bash
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
  ```
  Passing = every suite prints `PASS` per case and no `FAILED:` line appears.
- [ ] No linter, type checker, or build step exists in this repo (no CI config, no `package.json`, no `Makefile`) — nothing to run.
- [ ] No stale claims remain: `grep -rn 'separate subagent\|subagents per step\|Hands the plan to subagents' --include='*.md' . | grep -v '^./tasks/'` returns nothing.
- [ ] Manual verification:
  - [ ] **AC1 — the choice exists.** Read `plugins/facto/skills/implement/SKILL.md` Phase 1 item 5. It instructs the agent to decide between inline and subagent execution per step. *(verifies: "the orchestrator decides whether to implement inline or via subagents")*
  - [ ] **AC2 — revisable mid-build.** Read Phase 2c. It tells the agent to re-evaluate the mode before each step and names conditions that argue for switching. *(verifies: "per step, revisable mid-build")*
  - [ ] **AC3 — judgment, not a rubric.** Read Phase 1 item 5. Considerations are framed as examples; no scoring rule, no threshold, no default named. *(verifies: "using its own judgment; considerations include …")*
  - [ ] **AC4 — validation is mode-independent.** Read Phase 2d. The wording applies to both modes. *(verifies: "Step validation is identical in either mode")*
  - [ ] **AC5 — inline mode commits in context.** Read Phase 2c's Inline branch. Edits and the `/facto:commit-or-amend` call both happen in context, with no subagent. *(verifies: superseded decision 5)*
  - [ ] **AC6 — docs agree.** Read `README.md:198` and `DEVELOPMENT.md:70` against the skill. No document claims a subagent per step. *(verifies: cross-doc consistency)*
  - [ ] **AC7 — reporting.** Read Phase 4. The summary reports execution mode per step and mid-build switches. *(verifies: decision 7)*
  - [ ] **AC8 — the skill still runs end-to-end (dogfood, manual).** Run `fi-task-test.sh` from this worktree to point the global install at these plugins, then run `/facto:implement` on a small real plan in a host repo. Confirm it picks a mode, states it, implements and validates every step, and the Phase 4 summary names the modes used. Run `fi-task-test.sh` from the main checkout afterwards to restore. *(verifies: the changed prose is actually followable — manual-described)*
  - [ ] **AC9 — cost outcome.** Not verifiable inside Facto. See Risks.

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Claude Code skill-prompt authoring (SKILL.md phases, frontmatter, type tags) | high | AC1 — implement chooses inline vs subagent rather than always spawning | manual-described |
| Claude Code skill-prompt authoring | high | AC2 — choice is per step and revisable mid-build | manual-described |
| Claude Code skill-prompt authoring | high | AC3 — judgment-framed, considerations are examples, no default named | manual-described |
| Claude Code skill-prompt authoring | high | AC4 — step validation identical in either mode | manual-described |
| Claude Code sub-skill invocation constraints (nested `Skill` tool calls) | high | AC5 — inline mode commits without a direct `Skill` call | manual-described |
| Cross-doc consistency (README, DEVELOPMENT, skill description) | high | AC6 — no doc asserts subagent-per-step | automated (`grep`, in the Test Plan) |
| Agent orchestration economics (subagent cold-start cache reads, context growth, compaction risk) | medium | AC8 — the heuristic actually picks the cheaper mode on a real build | manual-described (dogfood run + judgment) |
| Empirical per-build cost measurement | low | AC9 — orchestrator overhead drops on chain-shaped builds | **blocked-no-tooling** |

---

## Risks

1. **The cost win is unmeasurable inside Facto today** (`blocked-no-tooling`, `low` expertise). `OKRS.md:154` records "No Facto-side cost tracking today" as 🔴. AC9 has no automated or scripted check. The only way to confirm the saving is for the developer to read `/cost` or the Claude Code session logs across a build before and after, which is outside what this change delivers. This plan verifies that the behavior changed, not that it saved money.

2. **Heuristic calibration is a guess** (`medium` expertise). We have one data point — the moodmaker comparison. Decision 2 deliberately keeps the guidance judgment-framed rather than a threshold rubric, which is consistent with DEVELOPMENT.md principle 7 ("empirical gotchas over speculative rules"), but it also means the agent may pick badly at first. Expect to file follow-up observations via `/facto-dev:observe` after the next few builds and tighten the wording from real failures.

3. **No test guards the change** (decision 6). A future editing agent could drop the mode-selection block from Phase 1 or re-collapse Phase 2c to a single subagent branch, and nothing would catch it — the four existing suites cover shell scripts and the design-mock template only. The precedent for a grep-based structural test exists (`plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh`) if this turns out to regress.

4. **Inline mode raises compaction risk on long builds.** That is precisely the case the subagent mode exists for, but the agent has to notice it in the moment. Phase 2c's re-evaluation sentence is the only guard, and it is a prompt, not a hook — DEVELOPMENT.md principle 2 says prompts guide and can be ignored. If builds start dying to compaction, the fix is a harder trigger, not more prose.

5. **Parallelism stays on the table but undelivered.** Issue #96 lists step parallelizability as a consideration; this plan states the opposite — that a subagent buys no wall-clock — because steps run sequentially and concurrent writers would violate DEVELOPMENT.md principle 1. If the developer wants real parallel steps, that needs per-step worktree isolation and its own Issue.

## Note on tests

This repo has a test framework (four homemade bash suites, `DEVELOPMENT.md` §4.2), but it covers shell scripts and one HTML template — nothing tests SKILL.md prose. Per decision 6 no test is added here. Risk 3 above records what that leaves unguarded.
