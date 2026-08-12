# Implementation Plan: Keep `facto:implement` going after a commit

**Created:** 2026-08-11
**Task:** `114-bug-commit-or-amend-skill-finishing-keep`
**Based on:** GitHub Issue [#114](https://github.com/carllelandtaylor/facto/issues/114) — *BUG: /commit-or-amend skill finishing keeps causing whole session to stop*. No PRD or design docs exist; the Issue body, the session-log evidence below, and the developer's decisions are the requirements.
**Base:** `origin/main` at `262f43a`. (Local `main` in this worktree is stale, so every command below uses `origin/main`.)

---

## The bug

`/facto:implement` runs `/facto:commit-or-amend` inline via the Skill tool. When
commit-or-amend finishes, the session ends its turn and waits for the developer,
even though `implement` has more steps to run. The developer has to type
"continue" once per step.

### Evidence

From the log the Issue names,
`~/.claude/projects/-home-carltaylor-git-facto--facto-worktrees-113-feature-support-linear-task-tracking/05e32cab-6cf9-4567-a966-eea4b943a30e.jsonl`.
It happened twice in the one session:

| Log index | Event |
|---|---|
| 584 | `implement` calls `Skill(facto:commit-or-amend)` inline |
| 589 | Phase 1 sees a **dirty** tree — the clean-tree early-exit branch is not taken |
| 602–603 | Phases 2–4 stage and commit `270eabb` |
| 604 | Phase 5 emits its report as user-facing assistant text — **turn ends** |
| 610 | Developer types `um continue`; `implement` resumes correctly |
| 766–787 | Same stall after the Step 2 commit, with the skill-cache re-invocation banner — a warm cache does not help |
| 792 | Developer: *"stop getting stuck for no reason, the commit skill seems to be triggering you to stop when you still have work to do"* |

Two facts beyond the Issue report. `implement`'s step (d) Validate was **skipped
both times** — after the nudge it went straight to the next step — so a stall costs
verification, not just a keystroke. And this is the failure mode Issue #98's plan
predicted as its Risk 1 and left explicitly out of scope.

### Root cause

Invoking the Skill tool does three things, visible in the log: it emits the
`tool_use`, returns `Launching skill: facto:commit-or-amend`, and then injects the
sub-skill's entire SKILL.md as a **new user-role message** with `ARGUMENTS:`
appended. The sub-skill's instructions do not arrive as data the agent fetched —
they arrive as a fresh instruction turn, and they are the most recent thing in
context.

So when commit-or-amend's procedure runs out, the model has finished what reads as
*the* task, and **nothing in context says anything follows**. `implement`'s
remaining phases are an older instruction block, far back, and never reassert
themselves.

The cause is an *absent* instruction, not a present one — which is why the fix has
to add something, and why it has to sit as close to the injected block as possible.

## Approach, and the one we rejected

**Fix the caller, at the call site.** Each place `implement` invokes a sub-skill
inline, the sentence immediately after the call says the turn continues. This is
the only place that can carry the information, because only the caller knows there
is more to do — and it has to sit next to the call, since by the time the sub-skill
returns, anything stated at the top of the skill is as far away as the phases the
model just forgot about.

There is in-repo precedent: `pr/SKILL.md:49` already does exactly this
("then continue — do not stop") at its own commit-or-amend call, and that
construction has not been observed to stall.

### Rejected: making the callee stay silent

The first attempt edited `commit-or-amend`, `pr` and `iterate` to state a result and
then say nothing — replacing `Report what was done:` with `Return:`, `Phase 5:
Report` with `Phase 5: Result`, and stripping `and stop` / `stop and tell the user`
from the early-exit paths. It was abandoned before merge, for two reasons:

1. **It missed the failure path.** Every genuinely stop-flavored phrase it removed
   sat on a *"nothing to do"* early-exit branch. The observed bug fires on the
   *success* path, where the only change was the `Report:` → `Return:` synonym swap.
2. **Silence cannot carry the fix.** The information that has to reach the model is
   "your caller has four more steps". A callee saying less can never convey that.
   The approach forbade exactly the kind of instruction the bug requires.

## Scope

One file: `plugins/facto/skills/implement/SKILL.md`.

`commit-or-amend`, `pr` and `iterate` are **not** touched — they are byte-identical
to `origin/main`.

## Explicitly out of scope

- **The other inline callers.** `review-loop-code`, `review-loop-design-impl`,
  `fix-bug`, `watch-and-fix-ci` and `setup-design` all invoke sub-skills inline and
  have the same exposure. `implement` is where the bug was observed and is the
  highest-traffic caller; the rest follow once this is shown to work.
- **A `Stop` hook.** The deterministic fix, and what `DEVELOPMENT.md` principle 2
  ("hooks enforce, prompts guide") points at. Deferred: Facto skills legitimately
  stop mid-procedure with tasks in progress, so a naive hook would trap the
  developer in a loop. Needs its own design, and subsumes Issue #98's question 3.

---

## Verification Coverage

| Domain | Expertise | Issue #114 criterion | Verification |
|---|---|---|---|
| Claude Code harness: inline Skill-tool control flow and turn termination | **low** | `implement` continues past a `commit-or-amend` call with no developer nudge | **manual-described** — `fi-task-test.sh` then a real multi-step `/facto:implement` |
| Facto skill-prompt authoring | high | The instruction is present at each inline call site | **automated** — `grep` |
| Bash structural test suites | high | Change breaks nothing existing | **automated** — the five suites |

**Risks:**

1. **The harness row is `low` expertise and `manual-described`.** Nested Skill-call
   turn semantics are undocumented internal behavior. Only a real run tests this,
   and one passing run proves it worked once, not that it is fixed.
2. **This is a prompt fix, not a hook.** It will work most of the time and can fail
   the rest. Unlike the rejected approach it at least addresses the failure path,
   and it copies the one construction in the repo that has not stalled — but the
   deterministic fix is still the hook.
3. **Only `implement` is fixed.** The same stall can still occur from the five other
   inline callers listed above.

---

## Step 1: Tell `implement` that a returning sub-skill is not the end of the turn

**Goal:** at every point where `implement` invokes a sub-skill inline in its own
context, the next instruction is unambiguous that the turn continues.

**Changes:** `plugins/facto/skills/implement/SKILL.md`

The fix lives entirely at the call sites — there is no new Core Rule and no
general statement of the principle anywhere in the skill. An instruction placed
next to the call is read at the moment it is needed; a rule stated once at the top
is far up the context by the time the sub-skill returns, which is the same
distance problem that causes the bug.

- **Phase 2c, `**Inline:**`** — the site of both observed stalls. Extend the call
  instruction so it carries the message into the sub-skill's own arguments, then
  add the return pointer:

  > …passing it the step's commit message and context, and telling it that committing does not end the turn — when it is finished it returns to this point in this skill, which then carries on. When it's done, continue in your instructions here.

  Two placements, deliberately. **In the args**, because of how the Skill tool
  works: invoking it injects the sub-skill's whole SKILL.md as a *new user-role
  message*, with `ARGUMENTS:` appended, positioned as the most recent instruction in
  context. Anything in the args therefore arrives inside that same block, alongside
  the instructions the model is about to follow — the only placement that is as
  recent as the sub-skill itself. **And after the call**, so `implement`'s own
  procedure states where control lands. "Here" is the point of the call, which
  avoids naming a phase and stays correct if the phases are renumbered.

- **Phase 2e, the failure-fix bullet** — same treatment, shorter:
  `…fold the fix into the appropriate commit, telling it that committing does not
  end the turn — it returns here and you carry on down this list`.

- **Phase 3 Test Plan** — likewise: `…fold fixes into the appropriate existing
  commits, telling it that committing does not end the turn — it returns here and
  you work through the rest of the Test Plan`.

All three inline sites say the same thing, because all three are the same hazard —
a commit lands, the sub-skill's procedure ends, and the turn ends with it. Only the
trailing half varies, naming where control actually resumes at that particular
site.

- **Leave the subagent branch (line 128) alone.** That bullet is an instruction to
  the *subagent*, whose turn ending after the commit is exactly how it returns to
  `implement`. Telling it to continue would be wrong.

**Validation:**

- [ ] `grep -n "When it's done, continue in your instructions here" plugins/facto/skills/implement/SKILL.md` → matches the Phase 2c Inline paragraph
- [ ] `git diff origin/main -- plugins/facto/skills/implement/SKILL.md | grep -c '^[-+].*Core Rule'` → `0` (the Core Rules list is untouched)
- [ ] `grep -c 'does not end the turn' plugins/facto/skills/implement/SKILL.md` → `3` (all three inline call sites carry it)
- [ ] `grep -n 'you carry on down this list' plugins/facto/skills/implement/SKILL.md` → matches the Phase 2e bullet
- [ ] `grep -n 'you work through the rest of the Test Plan' plugins/facto/skills/implement/SKILL.md` → matches Phase 3
- [ ] `git diff origin/main --stat -- plugins/` lists **only** `implement/SKILL.md`
- [ ] The subagent bullet is unchanged: `git diff origin/main -- plugins/facto/skills/implement/SKILL.md | grep -c '^[-+].*to commit the changes, passing'` → `0`

**Commit message:**

```
fix: keep implement going after an inline sub-skill returns

Context:
implement calls commit-or-amend inline, so the sub-skill's instructions
load into implement's own turn. When commit-or-amend's procedure ran
out, nothing in context said anything followed and the turn ended,
stranding the build until the developer typed "continue" — twice in one
session on task 113, and step (d) Validate was skipped both times.
The cause is an absent instruction, so the fix is at the caller: one
clause after each inline call site saying the turn continues. Mirrors
pr/SKILL.md:49, which already does this and has not stalled.

Verification:
Automated:
  grep -c 'not the end of your turn' plugins/facto/skills/implement/SKILL.md
Manual:
  1. Point the global install at this worktree: fi-task-test.sh
  2. Run /facto:implement on a plan with three or more steps.
  3. Expected: each step's commit is followed immediately by that step's
     validation and then the next step, with no developer input.

Resolves #114
```

---

## Test Plan

- [ ] All five test suites pass:
      `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done`
      (None of them read `implement/SKILL.md`, so this only confirms nothing
      adjacent broke.)
- [ ] No linter, type checker or build exists in this repo — nothing to run.
- [ ] `implement/SKILL.md` is the only skill file changed:
      `git diff origin/main --name-only` → `implement/SKILL.md` plus this plan.
- [ ] The three skills touched by the abandoned approach are byte-identical to base:
      `git diff origin/main --stat -- plugins/facto/skills/commit-or-amend plugins/facto/skills/pr plugins/facto/skills/iterate`
      → empty.
- [ ] Frontmatter and type tag intact: `head -5 plugins/facto/skills/implement/SKILL.md`
- [ ] **Manual — the real check, and the only one that tests the actual bug.**
      This is the developer's to run; per their decision it does not gate the PR.
  - [ ] `fi-task-test.sh` from this worktree to point the global install here.
  - [ ] Run `/facto:implement` on a plan with three or more steps.
  - [ ] Expected: every step's commit is followed immediately by that step's
        validation and then the next step, with no developer input between them.
  - [ ] Expected: step (d) Validate actually runs — the stall was swallowing it.
  - [ ] From the main checkout, `fi-task-test.sh` again to restore the install.
  - [ ] If it still stalls, the next rung is the `Stop` hook, not more prompt
        wording.
