---
name: implement
description: "Use this skill to execute a detailed technical plan. Chooses per step whether to implement inline or in a subagent, validates after each step, runs a review loop, creates a PR, and summarizes the results. Designed to run autonomously without asking questions. Invoke with /facto:implement. Procedure skill (follow the phases in order)."
color: blue
---

# Implementation Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Execute a detailed technical plan, producing working, clean code in a PR that follows the plan's instructions, achieves the objectives, and satisfies the project's standards.

## Progress Tracking

Use `TaskCreate` and `TaskUpdate` to track progress through each phase. Create these tasks at the start (all `pending`):

1. `Before Starting` — activeForm: `Reading guidelines and checking state`
2. One task per plan step — subject: `Step N: <step title from plan>`, activeForm: `Implementing step N`
3. `Test Plan` — activeForm: `Running final validation`
4. `Design Fidelity Verification` — activeForm: `Verifying UI matches the design`
5. `Review Loop` — activeForm: `Running review loop`
6. `Create PR` — activeForm: `Creating PR`
7. `Summary` — activeForm: `Summarizing`

Create the per-step tasks after reading the plan (once you know how many steps there are and what they're called). Set each task to `in_progress` when you start it and `completed` when you finish it. If a step fails validation and you cannot fix it, set it to `completed` but note the failure in the summary.

---

## Input

The user should provide or point you to a detailed technical plan (from `/facto:plan-implementation` or equivalent). The plan should contain:
- Ordered steps with specific changes and validation instructions
- Final validation steps
- Commit messages for each step

If the plan is in a file, read it. If it's in the conversation, use it directly. If no plan is provided, ask for one.

**Optional:** The user may specify a maximum number of review loop cycles (e.g., `/facto:implement 3`). Default is 5.

## Phase 1: Before Starting

Set the `Before Starting` task to `in_progress`.

1. **Check for manual prerequisites.** Open the plan file and read it top-to-bottom. Scan for any developer-action, manual, or prerequisite markers (e.g., 'Developer actions:', '[manual]', 'no commit', 'blocked on developer'). If any exist, list them and confirm with the developer that they are complete before proceeding. If the developer says they are not done, stop and wait — do not begin automated work that cannot complete autonomously.

2. **Read project guidelines.** Find and read:
   - `CLAUDE.md` files (root and subdirectories)
   - `CONTRIBUTING.md` if it exists
   - Any relevant technical documentation referenced by the plan

3. **Confirm the starting state.** Run `git status` to verify the working tree is clean and you're on the right branch.

4. **Status fallback (optional).** If `facto-helper.sh tracker.exists` succeeds and `facto-helper.sh current-issue` prints an issue number, check the Issue's current Project Status. If it equals the configured `status_values.backlog` name, set Status → `status_values.in_progress` using the same inline `gh project item-edit` mechanics as facto-dev:observe's `set_issue_status` helper. If Status is anything else (or read fails), do nothing. A failed Status write **warns and continues** — the implementation is the deliverable, not the bookkeeping.

   ```bash
   if facto-helper.sh tracker.exists 2>/dev/null; then
     ISSUE_NUMBER="$(facto-helper.sh current-issue 2>/dev/null)" || ISSUE_NUMBER=""
     if [[ -n "$ISSUE_NUMBER" ]]; then
       PROJECT_OWNER="$(facto-helper.sh tracker.field project.owner)"
       PROJECT_NUMBER="$(facto-helper.sh tracker.field project.number)"
       STATUS_FIELD_NAME="$(facto-helper.sh tracker.field status_field)"
       BACKLOG_NAME="$(facto-helper.sh tracker.field status_values.backlog)"
       IN_PROGRESS_NAME="$(facto-helper.sh tracker.field status_values.in_progress)"
       REPO_SLUG="$(facto-helper.sh tracker.field repo)"
       CURRENT_STATUS="$(gh issue view "$ISSUE_NUMBER" --repo "$REPO_SLUG" --json projectItems \
         | jq -r --arg n "$(facto-helper.sh tracker.field project.name)" \
           '[.projectItems[]? | select(.title == $n) | .status.name] | first // ""')"
       if [[ "$CURRENT_STATUS" == "$BACKLOG_NAME" ]]; then
         PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json | jq -r .id)"
         FIELD_JSON="$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json \
           | jq --arg name "$STATUS_FIELD_NAME" '.fields[] | select(.name == $name)')"
         FIELD_ID="$(echo "$FIELD_JSON" | jq -r .id)"
         OPTION_ID="$(echo "$FIELD_JSON" | jq -r --arg n "$IN_PROGRESS_NAME" '.options[] | select(.name == $n) | .id')"
         ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 200 \
           | jq -r --argjson num "$ISSUE_NUMBER" '.items[] | select(.content.type == "Issue" and .content.number == $num) | .id')"
         gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
           --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID" \
           >/dev/null 2>&1 || echo "Warning: could not set Issue #$ISSUE_NUMBER Status -> $IN_PROGRESS_NAME"
       fi
     fi
   fi
   ```

5. **Choose the execution mode.** For each step, decide whether to implement it inline in this context or hand it to a subagent, and record the choice. A subagent isolates that step's context and survives a long build; inline avoids the per-step cold start and the overhead of dispatching to another agent and re-checking its work. Repo size and how long the build is expected to run are examples of what might tip the decision, not a checklist. Steps run in order either way, so a subagent will not make the build finish sooner.

6. **Create per-step tasks.** Read the plan and create one task per step (subject: `Step N: <title>`, activeForm: `Implementing step N`).

Set the `Before Starting` task to `completed`.

---

## Core Rules

- **Follow the plan.** Do not change the requirements, designs, or plan scope. Implement what it says.
- **Don't ask questions.** Work autonomously from start to finish. If you hit a problem, ambiguity, or contradiction, use your best judgment to unblock yourself and take note of it to report later.
- **Follow project guidelines.** Code style, naming conventions, patterns, test conventions — match what the codebase already does.
- **Don't change unrelated code.** Stay within the scope of the plan.

---

## Phase 2: Execution

Implement the plan step by step, in order. **Repeat the following for each step in the plan:**

#### a. Re-read the plan step

Before implementing step N, re-read step N's changes description and validation instructions from the plan verbatim (however those sections are labeled — `**Changes:**`, `### Changes`, `**Validation:**`, etc.). Do not summarize or paraphrase. Use the literal text as the spec for what to change and what to validate.

#### b. Start

Set the step's task to `in_progress`.

#### c. Implement

Re-evaluate this step's mode before implementing it, and switch from the Phase 1 choice if the build has changed — the step reads larger than planned, or the context is long enough that compaction is a risk.

**Inline:** Make the code changes described in the step directly in this context, and nothing outside the step's scope. When they're done, run `/facto:commit-or-amend` via the Skill tool, passing it the step's commit message and context.

**Subagent:** Launch a subagent (Agent tool, `model: "sonnet"`) to implement the step. Give the subagent:
- The step's full description (goal, changes, implementation details)
- Relevant project guidelines and conventions
- Context about what prior steps have already done (if needed)
- The commit message to use

The subagent should:
- Make the code changes described in the step
- Run `/facto:commit-or-amend` via the Skill tool to commit the changes, passing the step's commit message and context
- Not modify anything outside the step's scope

#### d. Validate

After the step's changes are committed, run the step's validation instructions yourself — identically in either mode:
- Execute all specified commands (tests, lint, type check, etc.)
- Perform any manual checks described
- Confirm everything passes

#### e. Handle Failures

Before pausing for developer input on a failure, search the plan for documented fallback paths for the failing area. Use `grep -i -E 'fallback|if this fails|alternative|in case of failure' <path-to-plan-file>` (substituting the actual plan file path provided at invocation) and check for Fallback sub-sections co-located with the failing step's Validation. If a specific fallback is documented, attempt it first and report results. Only pause for developer input if no documented fallback exists or the fallback also fails.

If validation fails:
- Read the error output carefully
- Fix the issue (in a subagent, `model: "sonnet"`, if the fix is non-trivial)
- Launch a subagent (`model: "sonnet"`) and tell it to run `/facto:commit-or-amend` via the Skill tool to fold the fix into the appropriate commit
- Re-run validation
- If you cannot resolve the failure after two attempts, note it and proceed to the next step

#### f. Proceed

Set the step's task to `completed`. Move to the next step. Do not proceed if validation is failing unless you've exhausted your options.

---

## Phase 3: After All Plan Steps

### Test Plan

Set the `Test Plan` task to `in_progress`.

Locate the plan's Verification or Test Plan section. Re-read it verbatim. Execute every checkbox in order. Do not substitute a different test plan derived from memory or summary — the plan's text is authoritative.

Run all final validation steps from the plan:
- Full test suite
- Linter
- Type checker
- Build
- Any end-to-end or manual verification steps

Before pausing for developer input on a failure, search the plan for documented fallback paths for the failing area. Use `grep -i -E 'fallback|if this fails|alternative|in case of failure' <path-to-plan-file>` (substituting the actual plan file path provided at invocation) and check for Fallback sub-sections co-located with the failing step's Validation. If a specific fallback is documented, attempt it first and report results. Only pause for developer input if no documented fallback exists or the fallback also fails.

If any final validation fails, fix the issues and launch a subagent (`model: "sonnet"`) that runs `/facto:commit-or-amend` via the Skill tool to fold fixes into the appropriate existing commits.

Set the `Test Plan` task to `completed`.

### Design Fidelity Verification

Set the `Design Fidelity Verification` task to `in_progress`.

Launch a **subagent** (Agent tool, `model: "opus"`) and tell it to run `/facto:review-loop-design-impl` via the Skill tool. If the plan references a design-mock path outside the task dir, pass it along. When it returns, record its report for the Phase 4 Summary.

Set the `Design Fidelity Verification` task to `completed`.

### Review Loop

Set the `Review Loop` task to `in_progress`.

Launch a **subagent** (Agent tool, `model: "opus"`) and tell it to run `/facto:review-loop-code` via the Skill tool. Pass it:
- The stack of commits (from the plan's base to HEAD)
- The requirements/goals from the plan
- The final validation steps
- Any product requirements or design docs that were provided
- The maximum number of review cycles (from user input, or 5 if not specified)

Set the `Review Loop` task to `completed`.

### Create PR

Set the `Create PR` task to `in_progress`.

Unless the plan specified an existing PR to use, launch a **subagent** (Agent tool, `model: "sonnet"`) and tell it to run `/facto:pr` via the Skill tool. Pass it:
- The stack of commits
- The requirements/goals
- Any product requirements or design docs
- Context on technical choices made during implementation (new libraries, APIs, services, patterns — what was chosen, what alternatives were considered, and why)

Set the `Create PR` task to `completed`.

---

## Phase 4: Summary

Set the `Summary` task to `in_progress`.

When everything is done, report to the developer:

1. **PR URL** — link to the created (or updated) PR
2. **Review cycles** — how many review loop iterations were needed, and a brief list of what was addressed
3. **Verification outcomes** — Enumerate every verification step from the plan's Test Plan section and report explicit outcome for each: ran+passed / ran+failed / skipped / deferred-with-reason. Silent omission is not allowed — every plan verification step must appear in the summary with one of these four labels.
4. **Design fidelity** — How verification ran (full comparison against a mock / sanity check with no mock / manual checklist if the UI wasn't launchable) and why. Per-screen result, and every infeasible divergence (screen, what couldn't be matched, why, closest approximation shipped) — never drop these silently. Link any manual checklist produced.
5. **Execution mode** — which steps ran inline vs in a subagent, and any mid-build switches
6. **Decisions and problems** — any ambiguities, contradictions, or judgment calls you made, so the developer can review them and make changes if needed

Keep the summary concise. Don't rehash the plan — just highlight what the developer needs to know.

Set the `Summary` task to `completed`.
