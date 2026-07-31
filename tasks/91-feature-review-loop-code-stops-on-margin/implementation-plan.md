# Implementation Plan: review-loop-code stops on marginal value

**Requirements and specs:** [Issue #91 — "FEATURE: review-loop-code stops on marginal value — severity-gated cycle continuation"](https://github.com/carllelandtaylor/facto/issues/91). No PRD or design docs exist for this task; the Issue body (What's missing / Why it would help / Sketch / Open questions) is the requirements input, as amended by the developer during this planning session.
**Created:** 2026-07-31

---

## Requirements Summary

- `facto:review-loop-code` has a binary stopping rule today: `SKILL.md:31` says "Repeat the following cycle. Stop when a review cycle produces no feedback." Any finding at all, however trivial, buys another full-stack Opus review cycle.
- `SKILL.md:63` compounds it — "Address **all in-scope** feedback items — including minor ones" — so a cosmetic nit is not merely reported, it is fixed, and the fix then needs another cycle to validate.
- Observed cost, `moodmaker-mythos-test` three-build comparison (2026-07-30/31): the loop ran all 5 cycles at $65.79, roughly 40% of a $166 build. Cycle 3's only finding was one minor (two popovers open at once). Cycle 4's single important finding was a **regression introduced by cycle 3's minor fix** (drag-select closing the popover). Only cycle 5 found a genuinely new defect.
- **Wanted:** a severity gate on cycle continuation. Any in-scope critical or important finding → fix and run another full cycle. All in-scope findings minor → that cycle was the final one; no further cycle runs either way.
- **Wanted:** on a terminal (all-minor) cycle the orchestrator uses its own judgment on whether to fix those last minors. Anything left unfixed goes into the final report.
- **Wanted:** a fix made in that terminal position gets a review scoped to just that diff, never another whole-stack cycle. This is the mechanic that would have caught the cycle-3 regression for a fraction of a full cycle's cost. **What shipped:** this diff-scoped re-review was built as Phase 4, then removed on developer review of PR #100 as unneeded complexity — see the "Review coverage for a terminal-cycle fix" row in Key Decisions for the history.
- **Severity definitions stay undefined** (developer decision, this session). The Issue sketched behavioral anchors ("important = a user-visible failure or spec violation; minor = cosmetic or hypothetical"); the developer declined them in favour of letting the reviewing model use its judgment. `SKILL.md:56`'s bare `critical / important / minor` list is unchanged.
- **No changes to the skills that invoke the review loop** (developer decision, this session). Deferred minors are reported by the review loop itself and are not relayed onward by `facto:implement` or `facto:fix-bug`.
- The max-cycles cap (default 5) stays as a backstop on top of the gate.
- OKR ties: moves `cost-effective` (per-session spend, OKRS.md:145) without giving up `code-correctness`'s self-review KR (OKRS.md:61) or `reliability`'s completion-verification KR (OKRS.md:122).

## Key Decisions

| Decision | Options Considered | Chosen | Rationale |
|---|---|---|---|
| Severity vocabulary | (a) keep critical/important/minor, "blocker" reads as a synonym for critical; (b) add "blocker" as a fourth level | (a) | Three levels are already in use and the gate only needs a binary split (critical-or-important vs. minor). A fourth level adds a classification boundary the reviewer has to get right for no behavioral gain. |
| Whether to define the severities | (a) write behavioral anchors; (b) anchors plus a required per-finding consequence sentence; (c) leave them undefined, model judgment decides | (c) | Developer's call. Consistent with DEVELOPMENT.md principle 8 — each harness component is an assumption about model capability, and over-constraining behavior the model already handles is counterproductive. Accepted trade-off: gate behavior is less predictable run-to-run, since "important" means whatever the reviewing subagent decides it means. |
| Max-cycles cap | (a) keep at default 5 as a backstop; (b) drop it, the gate is now the stopping rule | (a) | The gate and the cap fail differently. The gate stops a loop that has converged; the cap stops one that hasn't — importants on every cycle means fix-churn or a genuinely hard problem, which should stop and report for human judgment rather than burn the budget. |
| Minors found in a cycle that also has critical/important findings | (a) fix them alongside; (b) always defer minors to the report, never fix one | (a) | The Issue's churn came specifically from fixing a minor in a *terminal* position where nothing reviewed the fix. When a cycle is continuing anyway, the next full review covers those minor fixes for free. (b) would degrade quality for no saving. |
| Review coverage for a terminal-cycle fix | (a) one review scoped to just the fix diff, re-scoped up to 2 passes, never re-entering a full cycle; (b) no review at all; (c) any fix re-opens a full cycle (status quo) | (b) | (a) was built as Phase 4, then removed on developer review of PR #100 as unneeded complexity. It had also proven the most defect-prone part of the change: review cycle 1 found it would silently no-op, because Phase 3 stages fixes without committing, so the plain `git diff` the scoped review named returned empty; review cycle 3 found its re-fix path never staged the re-fix, so a second pass would re-read the first pass's diff and burn the cap re-reporting an already-fixed issue. (c) is the status quo being replaced; (b) is what shipped instead — a regression escaping a terminal-cycle fix is expected to surface in `/facto:pr` review or CI (see Risks). |
| Where unfixed minors go | (a) the skill's own final report; (b) also auto-file via `/facto:observe` | (a) | (b) spends tokens and creates tracker noise for cosmetic findings, and `facto:observe` is for observations about the app being built, not a code-review punch list. |
| Automated regression test | (a) add a homemade bash structure test under `plugins/facto/skills/review-loop-code/tests/`; (b) rely on review | (a) | Concrete failure mode: a future editing agent "simplifies" the gate back to stop-when-no-feedback and nothing notices. This repo has exactly one automated guard mechanism and it was established for this same situation (`ref-design-mock/tests/template-task-spec.test.sh`). Costs a DEVELOPMENT.md §4.2 count and table update. |
| Changes to skills that invoke the review loop | (a) surface the deferred-minor list in `implement` / `fix-bug` summaries; (b) also restate the gate in each; (c) no changes at all | (c) | Developer's call — deferred minors stop at the review loop and are not relayed onward. Also avoids the `ref-skill-writing:27` violation that (b) would be: a caller must not restate the called skill's internals. |
| `README.md` stopping-rule description | (a) update it; (b) leave it | (a) | `README.md:200-201` says the loop "repeats until clean (default max 5 cycles)". That describes the stopping rule, not the deferred-minor list, and it becomes factually wrong. Distinct from the (c) decision above. |

**Out of scope (agreed):** `plugins/facto/skills/implement/SKILL.md`, `plugins/facto/skills/fix-bug/SKILL.md`, and `OKRS.md`. The two invoking skills need no edit under the decisions above — they pass a max-cycles budget, which is unchanged, and they do not restate the stopping rule. `OKRS.md` progress indicators are updated manually by the developer (`facto-dev:mine-logs` SKILL.md:270), never by a task.

## Notable Technical Choices

- **Homemade bash structure test** — this repo's established convention (DEVELOPMENT.md §4.2): self-contained `*.test.sh` files, no framework, `PASS`/`FAIL` printed per case, non-zero exit if any case fails. Reused rather than introducing a test framework, because the assertions are grep-level structural invariants over a static markdown file and zero-dependency bash runs in any checkout.
- **Negative assertion in the test** — one case asserts the *old* binary stopping sentence is absent, not just that the new rule is present. A reverting edit that re-adds the old rule alongside the new one produces two contradictory instructions in one prompt, which is worse than either alone; a presence-only test would pass on that.
- **New test location `plugins/facto/skills/review-loop-code/tests/`** — second instance of the skill-tests root that `ref-design-mock` established. The DEVELOPMENT.md §4.2 run-all glob (`plugins/*/skills/*/tests/*.test.sh`) already matches it, so no glob change is needed this time — only the file count and the suite table.
- **No new libraries, services, or APIs.** Everything is markdown prose and bash.

---

## Commits

1. `feat: gate review-loop-code cycles on finding severity` — replaces the binary stopping rule with a severity gate and stands up a bash structure test guarding all of it.
2. `docs: describe severity-gated stopping in the README` — corrects the user-facing one-line description of the skill.

---

## Steps

### Step 1: Gate the review loop on finding severity

**Goal:** A review cycle whose in-scope findings are all minor is the last cycle that runs; a fix made in that terminal cycle is committed without further review, rather than triggering another whole-stack cycle; and a bash suite fails if a future edit removes any of that.

**Changes:**

- `plugins/facto/skills/review-loop-code/SKILL.md`

  - **Line 31, the loop preamble.** Currently: "Repeat the following cycle. Stop when a review cycle produces no feedback." Replace the second sentence — the stopping rule is now severity-gated, and Phase 2 owns it. New text states that the cycle repeats while in-scope findings warrant it, and points at Phase 2 for the rule. Per `ref-skill-writing:29`, delete the old sentence rather than leaving it as a prohibition.

  - **Phase 1 (Review), lines 33-56.** Two changes, both small:
    - Leave `SKILL.md:56`'s `**Severity** — critical / important / minor` exactly as-is. No definitions, no anchors, no extra required field. This is the developer's decision from planning; the reviewing subagent judges severity itself.
    - Add one sentence after the feedback-item field list noting that severity now controls whether another cycle runs, so the reviewer should assign it deliberately. This is the only place the gate is signalled to the reviewer, and without it the reviewer has no idea its labels are load-bearing.

  - **Phase 2, lines 57-59.** This phase is currently titled "Check for Completion" and is three lines: no feedback items → done. Rewrite it as the gate. Retitle to reflect that it decides continuation, and specify three outcomes over the **in-scope** list only (out-of-scope findings never gate anything — they are reported, never fixed, per `SKILL.md:49`):
    1. **No in-scope findings** — loop is done, go to "Done". (Existing behavior, preserved.)
    2. **One or more in-scope critical or important findings** — continue: Phase 3 fixes them, and another full cycle follows.
    3. **In-scope findings exist but every one is minor** — this cycle is the final cycle. Phase 3 runs in terminal mode (below); no further full cycle runs whether or not anything gets fixed.

  - **Phase 3 (Fix), lines 61-71.** Line 63 currently reads "Address **all in-scope** feedback items — including minor ones." Replace it with two branches matching Phase 2's outcomes:
    - **Continuing cycle** (outcome 2): fix all in-scope items, minors included. State why the minors are safe to fix here — another full cycle follows and will catch any regression they introduce at no extra cost.
    - **Terminal cycle** (outcome 3): the orchestrator judges each minor on whether fixing it is worth the risk of a late unreviewed change. Fix what is clearly worth fixing, skip what isn't. Anything skipped is reported (see "Done" below). If the terminal cycle fixes nothing, the loop is already done — skip straight to "Done" rather than paying for a commit subagent and a re-validation of an unchanged tree.
    - Leave lines 65-71 (parallel sonnet fix subagents, stage-don't-commit) untouched — that mechanism is unchanged.

  - **Phase 6 (Repeat), lines 87-89.** Currently an unconditional "Go back to Phase 1." Make it conditional on Phase 2's outcome 2 — a terminal cycle falls through to "Done" after re-validation instead of looping.

  - **Guardrails, line 95.** Keep the maximum-cycles guardrail as written (caller-specified, default 5, stop and report if the limit is hit with feedback outstanding). Add one clause noting it is now a backstop over the severity gate, and that hitting it means importants kept appearing every cycle — a signal of fix-churn or a genuinely hard problem that wants human judgment.

  - **Done section, lines 103-113.** Line 110 already reads "Any items you chose not to address and why", which covers deferred minors without new text. Extend it just enough to name the terminal-cycle case explicitly, so the orchestrator does not read "chose not to address" as being only about the out-of-scope list on line 111. Add one report line: whether the loop ended on a clean cycle, on an all-minor terminal cycle, or on the cycle cap. Do **not** add anything requiring the invoking skill to relay this onward.

- `plugins/facto/skills/review-loop-code/tests/skill-structure.test.sh` (new)

  - Follow the shape of `plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh`: `set -uo pipefail` (deliberately not `-e`, so every case runs and the tally is complete), a `pass`/`fail` counter pair, one function per case printing `PASS: <case>` / `FAIL: <case>`, non-zero exit if any case failed. Resolve `SKILL.md` by path relative to the script's own location so it runs from anywhere. Read-only — creates nothing, leaves nothing behind.
  - Header comment must state the same intent the design-mock suite's does: these assertions are pinned to specific marker phrases, and a future prose edit must either preserve them or update this test deliberately. It is not a loose contract.
  - Cases:
    1. **The old binary rule is gone** — `SKILL.md` does not contain "Stop when a review cycle produces no feedback". Negative assertion; guards against a revert that re-adds the old rule.
    2. **Terminal-cycle rule present** — the all-minor outcome is described as the final cycle.
    3. **Continuation rule present** — critical/important findings continue the loop.
    4. **Max-cycles backstop retained** — the default-5 cycle cap survives.
    5. **Severity list unchanged** — `critical / important / minor` still appears. Pins the developer's decision that the three buckets stay and stay undefined; a future edit adding a fourth level or baking in definitions has to change this test on purpose.
    6. **Terminal-mode fix branch present** — Phase 3 branches on the Phase 2 outcome, so a terminal cycle judges each minor rather than fixing all of them.
    7. **Repeat phase is conditional** — a terminal cycle falls through to "Done" instead of looping back to Phase 1.
    8. **Deferred minors are reported** — the "Done" report names the minors a terminal cycle skipped, which is the other half of the judge-each-minor requirement.
    9. **No-fix terminal cycle short-circuits** — a terminal cycle that fixes nothing skips the commit and re-validate phases entirely.
  - Pin short phrases, not whole sentences, so ordinary prose editing does not break the suite.

- `DEVELOPMENT.md`, §4.2 (lines 197-225)

  - Line 200: "four self-contained `*.test.sh` files" → "five".
  - Suite table (lines 203-208): add a row — `plugins/facto/skills/review-loop-code/tests/skill-structure.test.sh` | "review-loop-code severity gate — terminal-cycle rule, retained cycle cap".
  - The run-all glob on line 224 already matches `plugins/*/skills/*/tests/*.test.sh`. **No glob change.**
  - Line 210-214 describes the suites: the sentence currently splits them into "the script suites set up their own disposable git repos" and "the template suite only reads the template". Widen the second half to cover both read-only suites rather than naming only the template one.

**Validation:**

- [ ] New suite passes on its own: `bash plugins/facto/skills/review-loop-code/tests/skill-structure.test.sh` — every case prints `PASS`, exit code 0.
- [ ] New suite actually fails when it should. Temporarily revert the Phase 2 gate text in a scratch copy of `SKILL.md`, point the test at it, confirm cases 1-3 print `FAIL` and the script exits non-zero. Discard the scratch copy. A structure test that cannot fail is worthless.
- [ ] Full suite passes: `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — five suites run, no `FAILED:` lines.
- [ ] `DEVELOPMENT.md` §4.2's stated file count matches the actual count: `ls plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh | wc -l` returns 5.
- [ ] Read `SKILL.md` start to finish. Confirm there is exactly one stopping rule stated, that Phase 2 / Phase 3 / Phase 6 / Guardrails agree with each other, and that no sentence describes the old behavior as something to avoid (`ref-skill-writing:29` — replaced instructions get deleted, not negated).
- [ ] Confirm `plugins/facto/skills/implement/SKILL.md` and `plugins/facto/skills/fix-bug/SKILL.md` are untouched: `git diff --name-only` lists only the three intended files.

**Commit message:**

```
feat: gate review-loop-code cycles on finding severity

Context:
The review loop stopped only on a completely clean cycle, so any finding
bought another full-stack Opus review. In the moodmaker-mythos-test build
that meant all 5 cycles at $65.79 (~40% of a $166 build), where cycle 3's
sole finding was a minor and cycle 4's sole important finding was the
regression cycle 3's fix introduced. Continuation is now gated on
severity: critical/important continues, all-minor makes that cycle the
last one. A fix made in that terminal position is committed without
further review rather than triggering another whole-stack cycle.
Severities stay undefined on purpose — the reviewing model judges them.
The max-cycles cap stays as a backstop.

Verification:
Automated:
  bash plugins/facto/skills/review-loop-code/tests/skill-structure.test.sh
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
Manual:
  1. Read plugins/facto/skills/review-loop-code/SKILL.md end to end.
     Expect exactly one stopping rule, with Phase 2, Phase 3, Phase 6 and
     the Guardrails section agreeing on it.
  2. Run `git diff --name-only` against the merge base. Expect only
     SKILL.md, the new test, and DEVELOPMENT.md — the skills that invoke
     the review loop are deliberately unchanged.
```

---

### Step 2: Correct the README's description of the stopping rule

**Goal:** The user-facing one-line description of `/facto:review-loop-code` describes what the skill now does.

**Changes:**

- `README.md`, lines 200-201. Current text: "Iterative review/fix/validate cycle on a stack of commits. Reviews the diff, fixes all in-scope feedback, folds fixes into the right commits via `/facto:commit-or-amend`, and repeats until clean (default max 5 cycles)."
  - Two clauses are now wrong: "fixes all in-scope feedback" (terminal-cycle minors are a judgment call) and "repeats until clean" (it stops on an all-minor cycle).
  - Replace with a description of the same length and register as the surrounding entries — the loop repeats while findings are critical or important, treats an all-minor cycle as the last one, and keeps the max-5 cap as a backstop. Keep the `/facto:commit-or-amend` reference; that part is unchanged.
  - Per `ref-skill-writing:27`, keep it at contract level — what the skill achieves, not how Phase 2 or Phase 3 work internally.

**Validation:**

- [ ] `grep -n "repeats until clean" README.md` returns nothing.
- [ ] Read the `/facto:review-loop-code` entry in context against the entries around it (`/facto:implement`, `/facto:pr`). Confirm it stays one short paragraph and does not describe internal phase mechanics.
- [ ] `git diff --name-only` lists only `README.md` for this step.

**Commit message:**

```
docs: describe severity-gated stopping in the README

Context:
The skill catalog entry still described the old binary stopping rule —
"fixes all in-scope feedback" and "repeats until clean". Both became
wrong when the loop started gating continuation on severity. Kept at
contract level per the ref-skill-writing rule that a description states
what a skill achieves, not how its phases work.
```

---

## Verification Coverage

| Domain | Expertise | PRD criterion (Issue #91) | Verification |
|---|---|---|---|
| Claude Code agentic skill authoring (loop-control prompts) | medium | Critical or important in-scope findings: fix, then run another cycle | automated — structure test case 3 asserts the rule is present |
| Claude Code agentic skill authoring (loop-control prompts) | medium | An all-minor cycle is the final cycle; no further cycle runs either way | automated (case 2, rule present) + manual-described (real run needed to confirm the orchestrator obeys it) |
| Claude Code agentic skill authoring (loop-control prompts) | medium | Orchestrator judges whether to fix the last minors; unfixed ones are reported | manual-described — run the loop on a real stack, check the final report names them |
| Loop guardrail configuration | high | The max-cycles cap stays as a backstop | automated — structure test case 4 |
| Severity classification by model judgment | medium | Three buckets stay, and stay undefined | automated — structure test case 5 |
| Bash structural testing of a markdown prompt | high | (implementation-level) A future edit cannot silently revert the gate | automated — the suite itself, plus the deliberate-failure check in Step 1's validation |
| Per-session cost measurement | low | ~$10–15 saved per build; the review loop stops being ~40% of session spend | blocked-no-tooling |

## Risks

- **The cost saving cannot be verified by Facto — `blocked-no-tooling`.** This is the Issue's entire justification and there is no way to measure it here. OKRS.md:154 states plainly that no Facto-side cost tracking exists. The only signal is the developer reading Claude Code's own session cost after a real build and comparing against the $65.79 baseline. Nothing in this plan produces that number.
- **Per-session cost measurement is a `low`-expertise domain** and no mechanism in this repo produces a per-skill spend figure, so building one is not available within this task's scope.
- **Every behavioral criterion is `manual-described`, not automated.** The change is prose that an Opus orchestrator has to follow. The structure test proves the instruction is *written*; it can never prove it is *obeyed*. First real signal comes from the next `/facto:implement` run on a real build.
- **Undefined severities make the gate's behavior variable.** Accepted deliberately (developer decision, Key Decisions table). "important" means whatever the reviewing subagent decides it means on that run, so the same diff could terminate on cycle 2 once and cycle 4 the next time. The failure mode to watch for is severity inflation — a reviewer that labels nits "important" restores the old cost profile silently, and nothing in this plan detects that. If it shows up in practice, behavioral anchors are the fix that was declined here.
- **Terminal-cycle minor fixes get no review at all.** The diff-scoped re-review that would have covered them was built and then removed on developer review of PR #100 (see Key Decisions) as unneeded complexity — and it had also proven the most defect-prone part of the change while it existed. A fix made in the terminal position is now committed unreviewed. This is the intended trade — the Issue argues the full cycle is not worth $6–8 for a cosmetic fix — but a regression escaping into the PR is a real possibility. It should surface in `/facto:pr` review or CI rather than in the loop.
- **Structure tests over prose are brittle by nature.** Mitigated by pinning short marker phrases rather than sentences, and by the header comment stating that a prose edit must update the test deliberately. It will still occasionally fail on an innocuous rewording. That is the cost of having any automated guard at all here.
- **No CI runs any of this.** `.github/` contains only `ISSUE_TEMPLATE/`. The new suite runs only when someone runs it by hand or an agent runs the §4.2 glob. Pre-existing repo-wide condition, not introduced here, but it does bound what the test actually buys.

## Test Plan

- [ ] All project tests pass: `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — five suites, no `FAILED:` lines.
- [ ] Linter passes: **n/a** — this repo has no linter.
- [ ] Type checker passes: **n/a** — this repo has no type checker.
- [ ] Build succeeds: **n/a** — this repo has no build step; the plugins are consumed as source.
- [ ] Manual verification:
  - [ ] The new suite fails when the gate is removed. Revert the Phase 2 gate in a scratch copy, run the suite against it, confirm non-zero exit. (Also listed under Step 1 — repeated here because it is the single check that makes the rest of the automated coverage meaningful.)
  - [ ] Read `plugins/facto/skills/review-loop-code/SKILL.md` end to end. Exactly one stopping rule; Phase 2, Phase 3, Phase 6 and Guardrails agree; no leftover negation of the old rule.
  - [ ] `plugins/facto/skills/implement/SKILL.md` and `plugins/facto/skills/fix-bug/SKILL.md` are byte-identical to their pre-change state.
  - [ ] `OKRS.md` is untouched.
  - [ ] **End-to-end, requires a real build (Issue #91 criteria 2-5).** With `fi-task-test.sh` pointing the global install at this worktree, run `/facto:implement` on a real task in a host project. Confirm: the loop reports the severities it saw per cycle; it stops on the first cycle whose in-scope findings are all minor; a terminal-cycle fix is committed without further review rather than triggering a new full cycle; the final report names any minors left unfixed. This is the only check that verifies the behavior rather than the text.
  - [ ] **Cost comparison, developer-only (Issue #91's justification).** After that run, compare the session's review-loop spend against the $65.79 / 5-cycle baseline. Facto cannot produce this number — see Risks.

## Flags

- [ ] **The headline benefit is unverifiable by Facto.** The Issue is justified on a ~$10–15 per-build saving and there is no per-session cost tracking in this repo (OKRS.md:154 — `cost-effective` KR "Facto tracks per-session, per-PR, and/or per-skill token spend" is 🔴). Whether this change worked is a judgment you make from Claude Code's own cost reporting after a real build.
- [ ] **Severity inflation is the failure mode with no detector.** With severities left to model judgment, a reviewer that labels nits "important" quietly restores the old cost profile and nothing flags it. Worth watching across the first few builds. If it happens, the behavioral anchors declined during planning are the available fix.
- [ ] **No CI.** `.github/` has only `ISSUE_TEMPLATE/`, so the new suite — and the four existing ones — run only when invoked by hand. Adding a workflow that runs the §4.2 glob on PRs is a small, separate piece of work; flagged here, not included.
- [ ] **`OKRS.md` references a `code-quality` OKR that does not exist.** `plugins/facto-dev/skills/mine-logs/SKILL.md` lines 16 and 270 both route "a `facto:review-loop-code` run exceeded the cycle target" to a `code-quality` KR, but `OKRS.md` has no `code-quality` objective. Pre-existing, unrelated to this change, and deliberately not fixed here — noting it because this task is the one that made it visible.
