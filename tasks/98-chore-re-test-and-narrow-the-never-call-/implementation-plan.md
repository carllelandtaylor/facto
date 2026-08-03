# Implementation Plan: Decide subagent-vs-inline per call site

**Created:** 2026-07-31
**Task:** `98-chore-re-test-and-narrow-the-never-call-`
**Based on:** GitHub Issue [#98](https://github.com/carllelandtaylor/facto/issues/98) — *CHORE: Re-test and narrow the never-call-Skill-directly subagent rule*. No PRD or design docs exist for this task; the Issue body plus the developer's decisions in the planning session are the requirements.
**Base:** rebased onto `origin/main` at `098533f`. All line numbers below are post-rebase.

---

## What this is

Five skills carry a verbatim blanket rule: never call the Skill tool directly; wrap every sub-skill invocation in an Agent-tool subagent. It is a workaround for a harness quirk, not a design principle, and it costs a full extra opus context per hop.

This change deletes the rule and replaces it with nothing. There is no new rule and no replacement rule. Each place a skill spawns a subagent or invokes a sub-skill gets an instruction that says what to do at that point, stated positively, with no text about what not to do.

A subagent survives a site when it is doing work a subagent is actually for:

- **Parallel fan-out** — genuinely concurrent, independent work.
- **Read-only reviewer** — DEVELOPMENT.md principle 1: multiple intelligences feeding one writer.
- **Heavy payload isolation** — screenshots, browser snapshots, and app output that should not enter the caller's context.
- **Long-running sub-skill** — a sub-skill that runs a whole build or a multi-cycle loop, whose accumulated context should not land in the caller. (Developer decision during planning.)

Everything else becomes an inline Skill call.

### Note on Issue #98's headline case

Issue #98 singled out `facto:implement` invoking `facto:review-loop-code` as the hop that "exists solely for the quirk," and it is the hop that stalled twice on task 91. **This plan keeps that wrapper**, on the fourth criterion above: `review-loop-code` runs up to 5 review cycles, each spawning its own reviewer and fix agents, and that accumulated context should not land in `implement`. The wrapper stays but its stated reason changes from a workaround to context isolation.

So the depth of the deepest chain is largely unchanged. What changes is that every remaining wrapper has a real reason written at the site, and the wrappers that had no reason beyond the workaround are gone. The stall risk that motivated the Issue is **not** resolved by this change; it is Issue #98's open question 3, which remains out of scope (see below).

### What PR #99 already did

Issue [#96](https://github.com/carllelandtaylor/facto/issues/96) landed as PR #99 while this was being planned. It reworked `facto:implement`'s Phase 2 to choose inline vs subagent execution per step, and in doing so already deleted `facto:implement`'s copy of the blanket rule. Six rule copies became five. It also established the in-repo precedent this plan leans on: `implement`'s inline execution branch (line 117) runs `/facto:commit-or-amend` directly via the Skill tool, in-context, with no wrapper.

## Explicitly out of scope

- **`facto:implement`'s per-step execution mode** (Phase 1 item 5; the Phase 2 `Inline:` / `Subagent:` fork at lines 117–130). Shipped by PR #99 and already correct.
- **Parent-side stalled-descendant detection** (Issue #98 open question 3). No mechanism exists to build on. Since the deepest wrappers are being kept, the stall exposure observed on task 91 persists — this is the follow-up work, not part of this change.
- **Empirical re-testing of the harness quirk.** Per developer direction, we make the changes without a test run first.
- **`facto:research`, `facto:plan-design`, `facto-dev:mine-logs`.** Audited, no changes needed — every Agent use in them is parallel fan-out or a deliberate fresh-context adversarial reviewer, and none wraps a sub-skill for the workaround.

---

## Verification Coverage

| Domain | Expertise | Issue #98 criterion | Verification |
|---|---|---|---|
| Facto skill-prompt authoring (markdown conventions, self-containment) | high | Blanket rule is gone from all five remaining skills | **automated** — `grep` assertions per step |
| Facto skill architecture (principle 1 reviewer separation) | high | `review-loop-code`'s read-only reviewer hop is preserved | **automated** — `grep` assertion |
| Facto skill architecture (which sites keep a subagent, and why) | high | Remaining subagents have a stated, real reason | **manual-described** — read the diff; the judgment is editorial |
| Claude Code harness: nested Skill-tool call control flow | **low** | Inlined sites do not stop their parent mid-procedure | **manual-described** — surfaces only on a real run |
| Bash structural test suites (`plugins/*/bin/tests/`, `plugins/*/skills/*/tests/`) | high | Change breaks nothing existing | **automated** — the four suites |

**Risks:**

1. **The harness-behavior row is `low` expertise and `manual-described`.** Whether a nested Skill call still stops its parent is undocumented internal behavior with sparse training data, and per developer direction we are not testing it first. If the quirk still reproduces, the failure mode is a skill stopping mid-procedure, intermittently. That lands on the `reliability` KR in `OKRS.md`, already 🟡 for `facto:implement`. **Mitigation:** one commit per file, so any single skill reverts independently.
2. **Keeping the long-running wrappers preserves the stall exposure.** Per decision 1(b), `implement` invoking `review-loop-code`, and `fix-bug` invoking `implement` and `watch-and-fix-ci`, stay wrapped. Those are exactly the hops where a stalled descendant is invisible to its parent. This change does not make that better or worse; it just does not fix it. Issue #98 should stay open on question 3 after this merges.
3. **The inlined hops are the least-evidenced ones.** The two in-repo precedents (`pr` line 49, and `implement` line 117 from PR #99) both invoke the same sub-skill: `commit-or-amend`, short, sonnet-preferred, spawns nothing. Most of what we are inlining is also `commit-or-amend` or `pr`, which is the good case. The exception is `fix-bug` invoking `plan-implementation` (step 2), which is long and interactive.
4. **The existing test suites do not cover SKILL.md prose.** They test `task-start.sh`, `task-list.sh`, `fi-task-test.sh`, and the design-mock template. Running them proves this change broke nothing adjacent; the per-step `grep` assertions are the real check, and they verify text, not behavior.

---

## Step 1: `facto:implement` — inline the short hops, restate the long ones

**Goal:** `implement` invokes `commit-or-amend` and `pr` directly. Its two remaining wrappers keep their subagents but say why at the site, in terms of context isolation rather than a harness workaround.

PR #99 already deleted this skill's blanket-rule bullet, so there is no rule to remove here.

**Changes** — `plugins/facto/skills/implement/SKILL.md`:

- **Line 144 (Phase 2, e. Handle Failures):** replace
  `- Launch a subagent (\`model: "sonnet"\`) and tell it to run \`/facto:commit-or-amend\` via the Skill tool to fold the fix into the appropriate commit`
  with
  `- Run \`/facto:commit-or-amend\` via the Skill tool to fold the fix into the appropriate commit`.
  The preceding bullet (`Fix the issue (in a subagent, model: "sonnet", if the fix is non-trivial)`) is unchanged.
- **Line 171 (Phase 3, Test Plan):** replace
  `If any final validation fails, fix the issues and launch a subagent (\`model: "sonnet"\`) that runs \`/facto:commit-or-amend\` via the Skill tool to fold fixes into the appropriate existing commits.`
  with
  `If any final validation fails, fix the issues and run \`/facto:commit-or-amend\` via the Skill tool to fold fixes into the appropriate existing commits.`
- **Line 179 (Phase 3, Design Fidelity Verification):** keep the subagent, add its reason. Append to the existing first sentence so it reads:
  `Launch a **subagent** (Agent tool, \`model: "opus"\`) and tell it to run \`/facto:review-loop-design-impl\` via the Skill tool. Use a subagent so its capped render-compare-fix loop and the screenshots it works from stay out of this skill's context — it returns only its report.`
  The following two sentences (design-mock path pass-through, recording the report for the Phase 4 Summary) are unchanged.
- **Line 187 (Phase 3, Review Loop):** keep the subagent, add its reason:
  `Launch a **subagent** (Agent tool, \`model: "opus"\`) and tell it to run \`/facto:review-loop-code\` via the Skill tool. Use a subagent so its review cycles — each spawning a reviewer and its own fix agents — stay out of this skill's context, and it returns only the loop's report. Pass it:`
  The five-item bullet list beneath is unchanged.
- **Line 200 (Phase 3, Create PR):** replace
  `Unless the plan specified an existing PR to use, launch a **subagent** (Agent tool, \`model: "sonnet"\`) and tell it to run \`/facto:pr\` via the Skill tool. Pass it:`
  with
  `Unless the plan specified an existing PR to use, run \`/facto:pr\` via the Skill tool. Pass it:`.
  The bullet list beneath is unchanged. (`facto:pr` isolates its own screenshot work in its Phase 4 subagent.)
- **Lines 84, 117, 127 are unchanged** — PR #99's execution-mode fork and both of its `commit-or-amend` calls.
- **Core Rules needs no edit.**

**Validation:**

- [ ] `grep -c 'Never call the Skill tool' plugins/facto/skills/implement/SKILL.md` returns `0`
- [ ] `grep -n '/facto:pr' plugins/facto/skills/implement/SKILL.md` shows no `Launch a **subagent**` on that line
- [ ] `grep -n 'review-loop-code\|review-loop-design-impl' plugins/facto/skills/implement/SKILL.md` still shows a subagent on each, each followed by a stated reason
- [ ] `grep -n '^\*\*Inline:\*\*\|^\*\*Subagent:\*\*' plugins/facto/skills/implement/SKILL.md` still matches both — PR #99's fork survived
- [ ] Read Phase 3 top to bottom: no sentence explains what not to do

**Commit message:**
```
refactor: inline implement's short sub-skill calls, justify the rest

Context:
facto:implement wrapped four sub-skill invocations in Agent-tool
subagents, left over from a blanket rule guarding a harness quirk where a
nested Skill call could stop the parent skill. commit-or-amend and pr are
short and return little, so they are now direct Skill calls, matching what
this skill's own inline execution branch already does.

review-loop-code and review-loop-design-impl keep their subagents, but for
a real reason now stated at each site: both run multi-cycle loops that
spawn their own agents, and that context should not accumulate here.

PR #99's per-step execution-mode fork is untouched.

Resolves part of #98
```

---

## Step 2: `facto:fix-bug` — delete the rule, inline the short hops

**Goal:** `fix-bug` invokes `commit-or-amend`, `plan-implementation`, and `pr` directly; keeps wrappers on `repro-bug`, `implement`, `review-loop-code`, and `watch-and-fix-ci`, each with its reason stated.

Inlining `plan-implementation` also fixes a live bug: that skill interviews the developer and waits for answers at its Phase 3, and instructs itself to do so even when told to work without stopping. A subagent has no channel to the developer, so the escalated path could hang or the subagent could invent the answers.

**Changes** — `plugins/facto/skills/fix-bug/SKILL.md`:

- **Lines 28–32:** delete the entire `## Sub-skill Invocation Rule` section — heading, paragraph, and its trailing `---` separator. Leave surrounding separators intact.
- **Line 96 (Phase 2: Reproduce):** keep the subagent, restate the reason, drop the negative clause. Replace
  `- Launch a **subagent** (Agent tool, \`model: "opus"\`) and tell it to run \`/facto:repro-bug\` via the Skill tool, passing the issue number or description. Do not call the Skill tool directly from this skill.`
  with
  `- Launch a **subagent** (Agent tool, \`model: "opus"\`) and tell it to run \`/facto:repro-bug\` via the Skill tool, passing the issue number or description. Use a subagent so the browser snapshots, screenshots, and app output it collects stay out of this skill's context — it returns just the distilled repro steps and evidence.`
- **Line 127 (Phase 4, Direct path):** replace
  `- **Direct path:** launch a **subagent** (\`model: "sonnet"\`) to make the edits (plus a regression test where the project has tests), then a **subagent** (\`model: "sonnet"\`) to run \`/facto:commit-or-amend\` via the Skill tool with a clear message.`
  with
  `- **Direct path:** launch a **subagent** (\`model: "sonnet"\`) to make the edits (plus a regression test where the project has tests), then run \`/facto:commit-or-amend\` via the Skill tool with a clear message.`
- **Line 128 (Phase 4, Escalated path):** inline `plan-implementation`, keep the `implement` wrapper. Replace the bullet with
  `- **Escalated path:** run \`/facto:plan-implementation\` via the Skill tool — pass it the root cause, the logged repro steps, and the no-regression constraint (**do not remove or alter working functionality**). Run it in-context, not in a subagent: \`plan-implementation\` interviews the developer and waits for answers, which a subagent cannot do. Then launch a **subagent** (\`model: "opus"\`) to run \`/facto:implement\` via the Skill tool (it bundles the review loop and PR creation) — a subagent so the whole build's context stays out of this skill's.`
- **Line 141 (Phase 5, Direct path):** keep the wrapper, add the reason:
  `- **Direct path:** launch a **subagent** (\`model: "opus"\`) to run \`/facto:review-loop-code\` via the Skill tool over the fix commits (pass the root cause, repro steps, and validation). Use a subagent so its review cycles stay out of this skill's context.`
- **Line 153 (Phase 6, Otherwise):** replace
  `- **Otherwise** (direct path), launch a **subagent** (\`model: "sonnet"\`) to run \`/facto:pr\` via the Skill tool. Pass it …`
  with
  `- **Otherwise** (direct path), run \`/facto:pr\` via the Skill tool. Pass it …` — rest of the sentence unchanged.
- **Line 163 (Phase 7, Watch CI):** keep the wrapper, add the reason:
  `- Launch a **subagent** (\`model: "opus"\`) to run \`/facto:watch-and-fix-ci\` via the Skill tool. It watches the PR's checks, fixes failures, and loops until green (bounded by the max CI cycles) — a subagent so its polling cycles and CI logs stay out of this skill's context.`

**Validation:**

- [ ] `grep -c 'Never call the Skill tool\|Sub-skill Invocation Rule\|Do not call the Skill tool directly' plugins/facto/skills/fix-bug/SKILL.md` returns `0`
- [ ] `grep -n 'plan-implementation' plugins/facto/skills/fix-bug/SKILL.md` shows the in-context instruction and the interview rationale
- [ ] `grep -n 'repro-bug\|/facto:implement\|review-loop-code\|watch-and-fix-ci' plugins/facto/skills/fix-bug/SKILL.md` shows a subagent on each, each with a stated reason
- [ ] Read Phases 2–7 in sequence; confirm the deleted section left no orphaned heading or doubled `---`

**Commit message:**
```
refactor: inline fix-bug's short sub-skill calls, justify the rest

Context:
Removes the blanket sub-skill invocation rule and decides each site.
commit-or-amend and pr become direct Skill calls. repro-bug, implement,
review-loop-code and watch-and-fix-ci keep their subagents, each now
saying why at the site — browser snapshots and app output for repro-bug,
accumulated build/loop/CI context for the other three.

Inlining plan-implementation also fixes a real bug: that skill interviews
the developer and waits for answers, which a subagent has no channel to
do, so the escalated path could hang or the subagent could invent them.

Resolves part of #98
```

---

## Step 3: `facto:review-loop-code` — delete the rule, inline both hops

**Goal:** `review-loop-code` invokes `commit-or-amend` and `pr` directly; its read-only reviewer keeps its subagent with principle 1 stated at the site.

**Changes** — `plugins/facto/skills/review-loop-code/SKILL.md`:

- **Line 99 (Guardrails):** delete the entire `**Never call the Skill tool directly from within this skill.**` bullet. The other four Guardrails bullets stay.
- **Line 35 (Phase 1: Review):** append to the first sentence so it reads
  `Launch a \`model: "opus"\` subagent to review the full diff (\`git diff <base>..HEAD\`). The reviewer is a separate, read-only agent by design — it produces feedback, and this skill is the single agent that writes fixes.`
  The rest of the paragraph and the criteria beneath are unchanged.
- **Line 65 (Phase 3: Fix):** replace
  `For efficiency, launch subagents in parallel when fixes are independent (different files, no interactions). When fixes interact, sequence them. Use \`model: "sonnet"\` for all fix subagents.`
  with
  `When several fixes are independent (different files, no interactions), launch \`model: "sonnet"\` subagents in parallel — the parallelism is the point. When fixes interact, sequence them. For a single small fix, just make it here.`
- **Line 74 (Phase 4):** replace
  `After all fixes are applied, launch a \`model: "sonnet"\` **subagent** (Agent tool) and tell it to run \`/facto:commit-or-amend\` via the Skill tool, passing the base ref …`
  with
  `After all fixes are applied, run \`/facto:commit-or-amend\` via the Skill tool, passing the base ref …` — rest unchanged.
- **Line 107 (Done, item 1):** replace
  `If one exists, launch a \`model: "sonnet"\` **subagent** (Agent tool) and tell it to run \`/facto:pr\` via the Skill tool to update the PR.`
  with
  `If one exists, run \`/facto:pr\` via the Skill tool to update the PR.` — the `gh pr view` check and the trailing "If no PR exists, skip" clause are unchanged.

**Validation:**

- [ ] `grep -c 'Never call the Skill tool' plugins/facto/skills/review-loop-code/SKILL.md` returns `0`
- [ ] `grep -n 'subagent to review the full diff' plugins/facto/skills/review-loop-code/SKILL.md` still matches — the principle 1 reviewer is intact
- [ ] `grep -n 'commit-or-amend\|/facto:pr' plugins/facto/skills/review-loop-code/SKILL.md` shows no wrapper on either
- [ ] Read Phases 1–6: the reviewer's reason reads as a design statement, not a warning

**Commit message:**
```
refactor: run review-loop-code's sub-skills inline

Context:
Removes the blanket sub-skill invocation rule; commit-or-amend and pr are
now direct Skill calls. The Phase 1 review subagent stays and now states
its own reason at the site — it is the read-only reviewer feeding one
writer from DEVELOPMENT.md principle 1, not a workaround. Phase 3's fix
subagents stay for parallelism, with a note that a single small fix does
not need one.

Resolves part of #98
```

---

## Step 4: `facto:review-loop-design-impl` — delete the rule, inline app launch and commit

**Goal:** the app-launch and `commit-or-amend` sites run inline; the two screenshot-consuming subagents stay with their payload-isolation reason stated.

**Changes** — `plugins/facto/skills/review-loop-design-impl/SKILL.md`:

- **Line 87 (Guardrails):** delete the entire `**Never call the Skill tool directly from within this skill.**` bullet. The other three bullets stay.
- **Line 35 (Phase A3):** replace
  `Launch the app via a **subagent** using the Agent tool, telling it to use the project's documented launch method (from the plan, CLAUDE.md, or project docs) — **never call the Skill tool directly from within this skill** (see Guardrails).`
  with
  `Launch the app using the project's documented launch method (from the plan, CLAUDE.md, or project docs).`
  The following `manual-described` fallback sentence is unchanged.
- **Line 39 (Phase A4):** append the reason to the first sentence:
  `… and the relevant design-system tokens. Use subagents here so the screenshot image tokens stay out of this skill's context — each returns only its structured discrepancy list.`
  The dimension list and structured-return paragraph are unchanged.
- **Line 55 (Phase A5):** replace
  `- Have a subagent (\`model: "sonnet"\`) run \`/facto:commit-or-amend\` via the Skill tool, passing the base ref and the fixes' context.`
  with
  `- Run \`/facto:commit-or-amend\` via the Skill tool, passing the base ref and the fixes' context.`
  The preceding fix-subagent bullet is unchanged.
- **Line 77 (Phase B, item 2):** replace
  `**Launch the app and screenshot.** Launch the real app via a **subagent** (same as Phase A3).`
  with
  `**Launch the app and screenshot.** Launch the real app the same way as Phase A3.`
- **Line 79 (Phase B, item 3):** replace
  `**Inspect.** Launch a **subagent** (\`model: "opus"\`) with the screenshots.`
  with
  `**Inspect.** Launch a **subagent** (\`model: "opus"\`) with the screenshots, keeping the image tokens out of this skill's context.`
  The rest of the item is unchanged.

**Validation:**

- [ ] `grep -c 'Never call the Skill tool' plugins/facto/skills/review-loop-design-impl/SKILL.md` returns `0`
- [ ] `grep -c 'see Guardrails' plugins/facto/skills/review-loop-design-impl/SKILL.md` returns `0` — no dangling cross-reference
- [ ] Both image-consuming subagents (Phase A4, Phase B item 3) still present with stated reasons
- [ ] Read Phase A3 and Phase B item 2: the app-launch instruction still reads as a complete instruction

**Commit message:**
```
refactor: inline app launch and commit-or-amend in review-loop-design-impl

Context:
Removes the blanket sub-skill invocation rule. Launching the app was
wrapped in a subagent only because of that rule and is now done directly;
so is commit-or-amend in the fix loop. The two screenshot-consuming
subagents (Phase A4 comparison, Phase B inspection) stay, and now say at
the site why — they keep heavy image tokens out of this skill's context
and return only structured findings.

Resolves part of #98
```

---

## Step 5: `facto:iterate` — delete the rule, inline the PR hand-off

**Changes** — `plugins/facto/skills/iterate/SKILL.md`:

- **Lines 13–17:** delete the entire `## Sub-skill Invocation Rule` section — heading, paragraph, and its trailing `---` separator.
- **Line 43 (Phase 3):** unchanged. These subagents exist for parallelism across independent changes, and the Parallelism note at line 48 already says so.
- **Line 54 (Phase 4):** replace
  `Launch a **subagent** (Agent tool, \`model: "sonnet"\`) to run \`/facto:pr\`. Pass it the context of what changes were made and why, and the base ref.`
  with
  `Run \`/facto:pr\` via the Skill tool. Pass it the context of what changes were made and why, and the base ref.`
  The trailing sentence about not prescribing amend/fixup/new-commit is unchanged.

**Validation:**

- [ ] `grep -c 'Never call the Skill tool\|Sub-skill Invocation Rule' plugins/facto/skills/iterate/SKILL.md` returns `0`
- [ ] `grep -n 'Parallelism' plugins/facto/skills/iterate/SKILL.md` still matches
- [ ] Read the file start to finish; no orphaned or doubled `---`

**Commit message:**
```
refactor: run iterate's PR hand-off inline

Context:
Removes the blanket sub-skill invocation rule; iterate hands off to
facto:pr directly. Its per-change subagents stay — they exist for
parallelism across independent changes, which is real work, not a wrapper.

Resolves part of #98
```

---

## Step 6: `facto:watch-and-fix-ci` — delete the rule, inline the push hand-off

**Changes** — `plugins/facto/skills/watch-and-fix-ci/SKILL.md`:

- **Lines 25–29:** delete the entire `## Sub-skill Invocation Rule` section — heading, paragraph, and its trailing `---` separator.
- **Line 88 (Phase 4):** replace
  `- Push the update: launch a **subagent** (Agent tool, \`model: "sonnet"\`) and tell it to run \`/facto:iterate\` (or \`/facto:pr\`) via the Skill tool to commit and push the fix and update the PR. Do not call the Skill tool directly from this skill.`
  with
  `- Push the update: run \`/facto:iterate\` (or \`/facto:pr\`) via the Skill tool to commit and push the fix and update the PR.`

**Validation:**

- [ ] `grep -c 'Never call the Skill tool\|Sub-skill Invocation Rule\|Do not call the Skill tool directly' plugins/facto/skills/watch-and-fix-ci/SKILL.md` returns `0`
- [ ] Read the file start to finish; no orphaned or doubled `---`

**Commit message:**
```
refactor: run watch-and-fix-ci's push hand-off inline

Context:
Removes the blanket sub-skill invocation rule; each fix cycle now runs
facto:iterate (or facto:pr) directly to commit, push, and update the PR
instead of dispatching a subagent to do it.

Resolves part of #98
```

---

## Step 7: `facto:pr` — drop the defensive hedging

**Goal:** `facto:pr` already invoked `commit-or-amend` inline. It just carried apologetic framing that only made sense while the blanket rule existed.

**Changes** — `plugins/facto/skills/pr/SKILL.md`:

- **Line 49 (Phase 1):** replace
  `If the working tree is not clean (staged or unstaged changes exist), invoke \`/facto:commit-or-amend\` directly via the Skill tool (in-context) — not in a subagent — with the base ref (\`main\`) and any relevant context, then continue — do not stop. This preserves its full fixup/attribution behavior. (If a direct Skill call ever stops \`facto:pr\` mid-procedure, inline \`facto:commit-or-amend\`'s attribution logic here instead — never sacrifice fixup fidelity.)`
  with
  `If the working tree is not clean (staged or unstaged changes exist), run \`/facto:commit-or-amend\` via the Skill tool with the base ref (\`main\`) and any relevant context, then continue — do not stop. This preserves its full fixup/attribution behavior.`
- **Line 90 (Phase 4):** unchanged. The capture subagent already states its own reason.
- **Line 131 (4f):** replace
  `Still inside the capture subagent, commit the screenshots (it may invoke \`/facto:commit-or-amend\` via the Skill tool — that is safe here, since the call is contained within the subagent).`
  with
  `Still inside the capture subagent, commit the screenshots, invoking \`/facto:commit-or-amend\` via the Skill tool.`
  The `Stage only $SHOTS_DIR` sentence and the rest of the paragraph are unchanged.

**Validation:**

- [ ] `grep -c 'not in a subagent\|that is safe here' plugins/facto/skills/pr/SKILL.md` returns `0`
- [ ] `grep -n 'heavy image tokens' plugins/facto/skills/pr/SKILL.md` still matches — the capture subagent and its reason survived

**Commit message:**
```
refactor: drop facto:pr's hedging about direct Skill calls

Context:
facto:pr already invoked commit-or-amend inline; it carried a fallback
parenthetical and a "that is safe here" aside that existed only to justify
deviating from the blanket rule. With the rule gone, both are noise. The
Phase 4 screenshot-capture subagent stays — it keeps heavy image tokens
out of this skill's context, which it already says.

Resolves part of #98
```

---

## Step 8: `facto:setup-design` — inline the PR hand-off

**Changes** — `plugins/facto/skills/setup-design/SKILL.md`:

- **Line 109 (Phase 3):** unchanged. One subagent per surface is parallel fan-out.
- **Line 139 (Phase 5):** replace
  `Launch a **subagent** (Agent tool, \`model: "sonnet"\`) and tell it to run \`/facto:pr\` via the Skill tool.`
  with
  `Run \`/facto:pr\` via the Skill tool.`

**Validation:**

- [ ] `grep -n 'Create one subagent per surface' plugins/facto/skills/setup-design/SKILL.md` still matches — parallel fan-out survived
- [ ] `grep -rc 'Never call the Skill tool' plugins/` returns `0` across the whole tree

**Commit message:**
```
refactor: run setup-design's PR hand-off inline

Context:
Runs facto:pr directly instead of dispatching a subagent whose only job
was to invoke it. The per-surface subagents in Phase 3 stay — they are
parallel fan-out across independent design surfaces.

Resolves part of #98
```

---

## Test Plan

- [ ] All project tests pass:
      `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done`
      (Expect all `PASS`. These cover the shell scripts and the design-mock template, not SKILL.md prose.)
- [ ] No linter, type checker, or build exists in this repo — nothing to run.
- [ ] **The blanket rule is gone everywhere:** `grep -rn 'Never call the Skill tool\|Sub-skill Invocation Rule\|Do not call the Skill tool directly' plugins/` returns nothing.
- [ ] **No dangling references to it:** `grep -rn 'see Guardrails' plugins/facto/skills/review-loop-design-impl/SKILL.md` returns nothing.
- [ ] **Principle 1 reviewers survived:** `grep -n 'subagent to review the full diff' plugins/facto/skills/review-loop-code/SKILL.md` and `grep -n 'adversarial review' plugins/facto/skills/plan-design/SKILL.md` both match.
- [ ] **Parallel fan-outs survived:** `grep -n 'Create one subagent per surface' plugins/facto/skills/setup-design/SKILL.md`, `grep -n 'Parallelism' plugins/facto/skills/iterate/SKILL.md`, and `grep -n 'Spawn all subagents in parallel' plugins/facto/skills/research/SKILL.md` all match.
- [ ] **Every surviving wrapper states a reason.** Read each of these sites and confirm the reason is written there: `implement` 179 and 187; `fix-bug` 96, 128, 141, 163; `review-loop-code` 35 and 65; `review-loop-design-impl` 39 and 79; `iterate` 43; `pr` 90; `setup-design` 109.
- [ ] **Structure is intact:** every edited SKILL.md reads with no orphaned headings and no doubled `---` separators. Check by reading each of the eight edited files start to finish.
- [ ] Manual verification — read the diff as a whole and confirm no edited instruction tells the agent what *not* to do.
- [ ] Manual verification (post-merge, not gating) — the harness-quirk risk surfaces only on a real run. Watch the first `/facto:implement` and `/facto:fix-bug` runs after this lands for a mid-procedure stop. If one occurs, revert that skill's commit rather than reinstating a blanket rule.

---

## Summary of what changes

| Step | File | Rule deleted | Inlined | Subagents kept (reason restated) |
|---|---|---|---|---|
| 1 | `implement/SKILL.md` | already gone (PR #99) | 144, 171, 200 | 179, 187; per-step fork untouched |
| 2 | `fix-bug/SKILL.md` | lines 28–32 | 127, 128 (`plan-implementation`), 153 | 96, 128 (`implement`), 141, 163 |
| 3 | `review-loop-code/SKILL.md` | line 99 | 74, 107 | 35 (reviewer), 65 (parallel fixers) |
| 4 | `review-loop-design-impl/SKILL.md` | line 87 | 35, 55, 77 | 39, 79 |
| 5 | `iterate/SKILL.md` | lines 13–17 | 54 | 43 |
| 6 | `watch-and-fix-ci/SKILL.md` | lines 25–29 | 88 | — |
| 7 | `pr/SKILL.md` | hedging at 49, 131 | already inline | 90 |
| 8 | `setup-design/SKILL.md` | — | 139 | 109 |

**Net: 5 blanket-rule blocks deleted, 2 hedging clauses dropped, 14 sites converted to inline Skill calls, 13 subagents kept — each with a real reason written at the site.** (A sixth rule block was removed by PR #99 before this work started.)
