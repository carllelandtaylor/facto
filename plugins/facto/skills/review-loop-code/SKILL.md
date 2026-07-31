---
name: review-loop-code
description: "Use this skill to iteratively review and improve a stack of commits. Runs a review/fix/validate cycle, continuing while findings are critical or important and stopping once only minor ones remain. Fixes in-scope feedback, amends fixes into the appropriate commits, and re-validates after each cycle. Invoke with /facto:review-loop-code. Procedure skill (follow the phases in order)."
color: green
---

# Review Loop Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Run an iterative review/fix/validate cycle on a stack of commits until the code meets quality standards.

## Input

You need:
- A stack of commits to review (the base ref and HEAD)
- The requirements or goals these changes are meant to achieve
- Validation steps (commands to run, manual checks)
- Project guidelines (from CLAUDE.md, etc.)
- Optionally: product requirements and/or design docs for product-level review

If any of these weren't provided, gather them:
- Commits: `git log <base>..HEAD --oneline`
- Guidelines: read `CLAUDE.md` files
- Validation: check `package.json` scripts, `Makefile`, CI config

---

## The Loop

Repeat the following cycle while in-scope findings warrant it. Phase 2 decides whether another cycle follows this one, whether the current cycle is the final one, or whether the loop is already done.

### Phase 1: Review

Launch a `model: "opus"` subagent to review the full diff (`git diff <base>..HEAD`). The subagent should read the diff and all changed files, then evaluate the changes against:

- **Correctness** — bugs, logic errors, off-by-one, null/undefined handling, race conditions
- **Requirements** — does the code actually achieve what the requirements/goals specify?
- **Project conventions** — naming, patterns, file organization, style consistency with the existing codebase
- **Error handling** — missing error cases, swallowed errors, unhelpful error messages
- **Edge cases** — empty inputs, boundary values, unexpected types, concurrent access
- **Security** — injection, auth gaps, secrets in code, OWASP top 10
- **Performance** — obvious inefficiencies (N+1 queries, unnecessary re-renders, unbounded loops)
- **Tests** — are new/changed behaviors covered? Are tests actually testing the right thing?

The subagent must scope its feedback to the changes under review. It should categorize every feedback item into one of two lists:

- **In-scope** — issues directly related to the changes being reviewed: bugs in new/modified code, requirements gaps in new/modified code, style issues in new/modified code.
- **Out-of-scope** — pre-existing problems, improvements to unchanged code, consistency issues in files that are not being modified. These should still be noted but will NOT be fixed.

Each feedback item (in either list) should include:
- **File and location** — where the issue is
- **Issue** — what's wrong
- **Suggestion** — how to fix it
- **Severity** — critical / important / minor

The subagent must assign severity deliberately, not as a formality: severity decides whether another review cycle runs.

### Phase 2: Decide Whether to Continue

Evaluate the **in-scope** list only. Out-of-scope findings never gate continuation — they are reported, never fixed (see Phase 1).

1. **No in-scope findings.** The loop is done. Proceed to the "Done" section below.
2. **One or more in-scope findings are critical or important.** Continue: Phase 3 fixes all in-scope items, and another full cycle follows — unless that would exceed the maximum-cycles guardrail, in which case this is the last cycle and the loop stops after it.
3. **In-scope findings exist, but every one is minor.** This cycle is the final cycle. Phase 3 runs in terminal mode; no further full cycle runs, whether or not anything gets fixed.

### Phase 3: Fix

Only fix items from the **in-scope** list. Do NOT fix **out-of-scope** items; they will be reported to the developer in the final summary.

- **Continuing cycle** (Phase 2 outcome 2): fix all in-scope items, including minors. Fixing minors here is safe — another full cycle follows and will catch any regression they introduce, at no extra cost. The exception is a cycle that hits the maximum-cycles guardrail: nothing follows it, so judge its minors the way a terminal cycle does.
- **Terminal cycle** (Phase 2 outcome 3): judge each minor on whether fixing it is worth the risk of a late, unreviewed change. Fix what's clearly worth fixing, skip what isn't. Anything skipped is reported (see "Done"). If the terminal cycle fixes nothing, the loop is already done — skip the remaining phases and proceed to the "Done" section, since there is nothing to commit or re-validate.

For efficiency, launch subagents in parallel when fixes are independent (different files, no interactions). When fixes interact, sequence them. Use `model: "sonnet"` for all fix subagents.

Each subagent should:
- Make the fix
- Stage the changed files
- NOT commit (the orchestrator handles commit management)

### Phase 4: Commit Fixes into the Right Place

After all fixes are applied, launch a `model: "sonnet"` **subagent** (Agent tool) and tell it to run `/facto:commit-or-amend` via the Skill tool, passing the base ref to fold changes into the appropriate existing commits (or create new commits for net-new work).

### Phase 5: Re-validate

Run all validation steps:
- Test suite
- Linter
- Type checker
- Build
- Any other validation specified

If validation fails, fix the failure and amend into the appropriate commit. Do not proceed past this phase until validation passes.

### Phase 6: Repeat

If Phase 2 selected outcome 2 (continuing cycle), go back to Phase 1 — unless the maximum-cycles guardrail has been reached, in which case stop and report. If Phase 2 selected outcome 3 (terminal cycle), the loop is done — proceed to the "Done" section below instead of repeating.

---

## Guardrails

- **Maximum cycles.** The caller may specify a maximum number of cycles (default: 5). If you've hit the limit while critical or important in-scope findings are still appearing, stop and report the remaining items to the user. Something may need human judgment. This is a backstop over the severity gate in Phase 2 — hitting it means critical or important findings kept appearing every cycle, a signal of fix-churn or a genuinely hard problem that wants human judgment.
- **Don't expand scope.** Only fix issues within the scope of the changes being reviewed. If you notice pre-existing problems, note them but don't fix them.
- **Don't fight the project.** If the codebase has a pattern you disagree with, follow it anyway. The review is about the new changes, not refactoring the project.
- **Preserve commit structure.** The point of amending is to keep the commit history matching the logical steps of the plan. Don't squash everything into one commit.
- **Never call the Skill tool directly from within this skill.** Nested Skill tool calls can cause the parent skill's execution to stop prematurely when the sub-skill completes. Instead, when this skill needs to run another skill (e.g., `/facto:commit-or-amend`, `/facto:pr`), launch a **subagent** using the Agent tool and tell the subagent to invoke the sub-skill via the Skill tool. This way the Skill tool's completion boundary is contained within the subagent, and this skill naturally continues when the subagent returns.

---

## Done

When the loop completes — on a clean cycle, an all-minor terminal cycle, or the cycle cap:

1. If any fixes were made during the loop, check if a PR already exists for the current branch (`gh pr view --json number 2>/dev/null`). If one exists, launch a `model: "sonnet"` **subagent** (Agent tool) and tell it to run `/facto:pr` via the Skill tool to update the PR. If no PR exists, skip — don't create a new PR.
2. Report:
   - How many cycles were run
   - A brief list of what was addressed in each cycle
   - Anything left unaddressed or committed without review, and why — minors skipped on a terminal cycle (Phase 2 outcome 3)
   - Whether the loop ended on a clean cycle (no in-scope findings), an all-minor terminal cycle, or the cycle cap
   - **Out-of-scope observations** — any issues the review noticed that are outside the scope of the current changes, so the developer can address them separately if they choose
   - Whether an existing PR was updated (with URL) or no PR existed to update
