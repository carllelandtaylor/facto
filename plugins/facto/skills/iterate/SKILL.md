---
name: iterate
description: "TRIGGER when: the user gives feedback or requests changes on a branch with an open PR — e.g. 'remove that file', 'change the approach here', 'add error handling to X'. Makes the change, commits via facto:commit-or-amend, pushes, and updates the PR. Procedure skill (follow the phases in order)."
color: green
---

# Iterate on PR Skill

> **Model:** when run as a subagent, prefer `model: sonnet`.

Apply feedback to an in-progress PR: make the code change, commit it cleanly, push, and update the PR description if the change is meaningful enough to affect it.

---

## Phase 1: Confirm PR Context

Run in parallel:
- `git branch --show-current`
- `gh pr view --json number,url,title,body,state 2>/dev/null`
- `git status`

If no open PR exists for this branch, stop and tell the user:
> "No open PR on this branch. Want me to create one? (/facto:pr)"

Save the PR number, URL, title, and body — you'll need them in Phase 4.

---

## Phase 2: Parse Feedback

Break the user's message into discrete changes. Each change should be a self-contained edit that can be described in one sentence (e.g., "remove plan.md from the repo", "rename `fetchData` to `loadData`", "add error handling to the webhook endpoint").

If any feedback is unclear or ambiguous, ask the user before proceeding.

---

## Phase 3: Execute Changes in Subagents

Spawn a subagent for each change. Each subagent should:
- Receive a clear description of the single change to make
- Read the relevant files, make the edit, and verify it looks correct
- NOT commit — just make the code change

**Parallelism:** If the changes touch different files and are independent of each other, launch the subagents in parallel. If changes touch the same files or one change depends on another's result, run them serially in dependency order.

---

## Phase 4: Hand Off to /facto:pr

Run `/facto:pr` via the Skill tool. Pass it the context of what changes were made and why, and the base ref. Do not prescribe whether to amend, fixup, or create a new commit — that's `/facto:commit-or-amend`'s job, and prescribing it overrides the decision.

---

## Phase 5: Report

One short message:
- What was changed (one line per change)
- How it was committed (amended into X / new commit "Y")
- Whether the PR was updated
- The PR URL
