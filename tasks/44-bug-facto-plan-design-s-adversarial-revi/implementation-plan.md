# Implementation Plan: Keep `facto:plan-design`'s review loop inside the requested scope

**Requirements:** [Issue #44](https://github.com/carllelandtaylor/facto/issues/44)
**Created:** 2026-07-31

---

## Problem

`facto:plan-design` Phase 4 runs an adversarial review loop. Two things in it have no scope axis:

- The reviewer is told to find "any possible flaw, gap, inefficiency, or non-obvious edge case." A genuine UX gap and an out-of-scope feature idea are indistinguishable in its output, and thoroughness is its only reward.
- The designer is told to "address objectively valid points." Nearly every finding *is* locally valid UX reasoning, so there is no vocabulary for "valid but out of scope" and accepting everything is the compliant path.

Together they inflated a 6-feature MVP design to ~21 features across 3 rounds — each round reviewing the previous round's additions and resolving flow criticisms by adding more capability.

## Approach

Constrain both sides, in Phase 4 only. Nothing else in the skill changes.

Deliberately **not** in this change: binding the design to a specific requirements file or its section names (a PRD isn't always there, and hardcoding its location makes the skill brittle), view-to-feature traceability tables, mock/inventory binding, scope reporting in Phase 6, and any change to the skill's autonomy posture. Those are separate concerns; this fix is about the review loop.

## Steps

### Step 1: Scope the Phase 4 review loop

**Goal:** the reviewer doesn't propose capability beyond what the requirements ask for, and the designer can't fold in a finding by adding one.

**Changes:** `plugins/facto/skills/plan-design/SKILL.md`, Phase 4 — two sentences:

- Reviewer paragraph: add a scoping clause — it judges how well the design delivers the requested feature set, and must not propose new features or capabilities beyond it.
- Acceptance paragraph: address points that are valid *and* within the requested feature set; if a valid point can only be resolved by adding a feature the requirements don't ask for, leave the design alone and note it for the developer in Phase 6. Never resolve a finding by adding a capability.

Refer to scope as "the feature set the requirements ask for" — no file path, no section names.

**Validation:**
- [ ] `git diff --stat` shows one file, two changed lines.
- [ ] `grep -n "objectively valid" plugins/facto/skills/plan-design/SKILL.md` — the phrase survives, now qualified by the scope condition rather than standing alone.
- [ ] Test suites pass: `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done`
- [ ] Phase 4 reads coherently top to bottom, and the Phase 3 flow-inventory-completeness requirement added by #45 still stands.

**Commit message:**
```
Keep plan-design's review loop inside the requested scope

Context:
Phase 4's reviewer was told to find "any possible flaw, gap,
inefficiency, or non-obvious edge case" with no scope axis, and the
designer to "address objectively valid points" with no vocabulary for
"valid but out of scope" — so review rounds turned flow criticisms
into new features and the next round reviewed those (Issue #44: a
6-feature MVP design reached ~21 features in 3 rounds). The reviewer
is now scoped to how well the design delivers the requested features,
and a finding may never be resolved by adding a capability.
```

## Verification Coverage

| Domain | Expertise | Criterion | Verification |
|---|---|---|---|
| Facto skill-prompt authoring | high | The scope constraint is present and unambiguous | automated (grep + read-through) |
| Adversarial-review-loop design for LLM agents | medium | Review findings stay inside the requested feature set | manual-described — run `/facto:plan-design` against a tiered PRD and read the review rounds |
| Empirical validation of prompt-behavior change | **low** | The design covers only the requested features | **blocked-no-tooling** — no eval harness exists in this repo |

## Risks

- **Efficacy can't be demonstrated.** This is prompt text, and the behavior it corrects is partly model disposition — over-weighting incorporation of high-quality critique. No eval harness exists, so a single passing run is an anecdote.
- **The constraint could make designs thinner.** A reviewer applying it too literally might stop reporting real gaps. The wording targets *new features and capabilities* specifically, not thoroughness, but this is what to watch for in a real run.

## Test Plan

- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done`
- [ ] No linter, type checker, build, or CI exists in this repo — nothing to run.
- [ ] Manual: with the install pointed at this worktree (`fi-task-test.sh`), run `/facto:plan-design` in a project whose requirements have explicit in-scope / out-of-scope tiers. Confirm no review round proposes a new capability, and that the design still covers the states its listed features need.

## Flags

- [ ] There is no test harness for skill prompts in this repo — every check above is a grep proving text exists, not behavior. Worth its own Issue.
- [ ] The manual check needs `fi-task-test.sh`, which requires the main checkout to be on the default branch and current with origin.
