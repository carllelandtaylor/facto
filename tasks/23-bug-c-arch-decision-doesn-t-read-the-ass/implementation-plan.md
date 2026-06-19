# Implementation Plan — Fix #23: `plan-architecture` Phase 1 doesn't read the associated Issue

**Based on:** GitHub Issue carllelandtaylor/facto#23 (body + 2026-06-18 recurrence comment).
**Created:** 2026-06-18.
**Author:** Facto `/facto:plan-implementation`.

## Context

`/facto:plan-architecture` (formerly `c-arch-decision`), when invoked in a task worktree whose branch
encodes an Issue number (e.g. `fix/23-…`), opens Phase 1 with the unconditional brain-dump prompt
without first deriving and reading the associated Issue. The developer must manually say "look at the
issue," re-supplying context the factory already has — degrading the `independence` OKR. A recurrence
shows the same prompt even when the Issue body was already read earlier in the conversation.

**Chosen behavior (developer decision: option b — pre-populate silently):** Phase 1 resolves the
associated Issue via `facto-helper.sh current-issue`, reads its body (and comments), treats that as the
brain dump, emits a brief **non-blocking** notice of what it booted from, and proceeds directly to
Phase 2 — no confirmation question. When no Issue resolves (or no tracker / no conversational context),
Phase 1 falls back to today's generic brain-dump prompt verbatim and waits as before.

**Scope notes:**
- The fix is **prose-only** in `plugins/facto/skills/plan-architecture/SKILL.md`, Phase 1.
- The `current-issue` regex concern referenced by #23 (tracked in #21) is **not a blocker here**:
  `facto-helper.sh current-issue` already returns `23` on this `fix/23-…` branch — the repo's
  `branch_issue_pattern` matches `<type>/<issue#>-<slug>`. No bin-script change is needed for #23.
- Reuse the `tracker.exists` → `current-issue` → `gh issue view` idiom already used by
  `plan-implementation/SKILL.md` (its "Optional: Active Issue context" block) for consistency.

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Claude Code skill-prose authoring (markdown procedure) | high | Phase 1 reads the branch-associated Issue before brain-dumping | manual-described |
| `facto-helper.sh current-issue` branch→issue resolution | high | Issue number resolves on task-worktree branches | automated (verified: returns `23`) |
| Agent runtime interpretation of the prose | medium | Skill actually bootstraps from the Issue / conversational context at run time | blocked-no-tooling |

---

## Step 1: Rewrite Phase 1 of `plan-architecture` to bootstrap from the associated Issue

**Goal:** Phase 1 silently pre-populates the brain dump from the branch-associated Issue (or
already-available conversational context) and proceeds to Phase 2, falling back to the generic prompt
only when no Issue can be resolved.

**Changes:**

- File: `plugins/facto/skills/plan-architecture/SKILL.md`, the `## Phase 1: Get Brain Dump` section
  (currently lines ~44–50).
- Replace the section body so it reads (level of detail like the existing prose; mirror the
  `plan-implementation` idiom):

  1. **First, try to bootstrap from the associated Issue (no developer prompt yet).**
     - If the Issue body is **already present in the current conversation** (e.g. it was read earlier in
       the session), use that as the brain dump — do not re-fetch.
     - Otherwise, attempt to resolve and read it. Provide the exact guarded snippet so the agent runs it
       reliably and it degrades silently on any failure:
       ```bash
       if facto-helper.sh tracker.exists 2>/dev/null; then
         ISSUE_NUMBER="$(facto-helper.sh current-issue 2>/dev/null)" || ISSUE_NUMBER=""
         if [[ -n "$ISSUE_NUMBER" ]]; then
           REPO_SLUG="$(facto-helper.sh tracker.field repo)"
           gh issue view "$ISSUE_NUMBER" --repo "$REPO_SLUG" --json title,body,comments
         fi
       fi
       ```
  2. **If an Issue was resolved (or its context was already in the conversation):** treat the Issue's
     title + body (and any relevant comments) as the brain dump. Emit a **brief, non-blocking** notice
     of what was booted from — a statement, not a question — and proceed **directly to Phase 2** without
     waiting. Suggested wording for the notice:
     > "Booting this architecture session from Issue #<N>: *<title>*. I'll work from the Issue's
     > description; correct me at any point if the scope is different."
  3. **If no Issue resolves** (no tracker, `current-issue` empty/non-zero, `gh` unreachable, and nothing
     in the conversation): fall back to today's behavior verbatim — ask the generic open-ended prompt and
     wait for the developer's brain dump before Phase 2:
     > "To start: give me a quick summary on what you're thinking about building or changing. We'll go
     > into more detail soon."
  4. Preserve the existing Phase 1 constraints: don't introduce yourself, don't explain the process,
     don't start exploring the codebase in Phase 1 — just establish the brain dump, then continue to
     Phase 2.

- Add a one-line note that this Issue-bootstrap mirrors `plan-implementation`'s "Optional: Active Issue
  context" so the two skills stay consistent (helps future maintainers).
- Do **not** change the Progress Tracking labels (Phase 1 stays "Brain Dump" / "Getting brain dump"),
  the template, the example, or any other phase.

**Validation:**
- [ ] `facto-helper.sh current-issue` returns `23` in this worktree (mechanism the new prose depends on):
      `facto-helper.sh current-issue` → prints `23`, exit 0.
- [ ] The guarded snippet runs clean end-to-end and prints the Issue JSON:
      `bash -c 'if facto-helper.sh tracker.exists; then n=$(facto-helper.sh current-issue); gh issue view "$n" --repo "$(facto-helper.sh tracker.field repo)" --json title,body,comments >/dev/null && echo OK; fi'` → prints `OK`.
- [ ] Markdown review: Phase 1 now (a) attempts Issue bootstrap first, (b) uses the Issue as the brain
      dump and proceeds without a confirmation question when one is found, (c) falls back to the exact
      generic prompt when none is found, (d) preserves the "don't explore the codebase yet" constraint.
- [ ] No other phase, the template, or the example was modified (`git diff --stat` shows only
      `plugins/facto/skills/plan-architecture/SKILL.md`).
- [ ] Manual (blocked-no-tooling, documented): re-running `/facto:plan-architecture` in a task worktree
      would now open by booting from the Issue rather than asking the generic prompt — confirmable only
      by manual re-run, not by automated test.

**Commit message:**
```
fix: bootstrap plan-architecture Phase 1 from the associated Issue

Context:
Phase 1 of /facto:plan-architecture opened with the unconditional
brain-dump prompt, ignoring the Issue number encoded in the task
worktree's branch name — so the developer had to manually point the
skill at the Issue (Resolves #23). Phase 1 now resolves the Issue via
facto-helper.sh current-issue (or reuses Issue context already in the
conversation), treats its body as the brain dump, and proceeds straight
to Phase 2; it falls back to the generic prompt only when no Issue
resolves. Mirrors plan-implementation's "Optional: Active Issue context"
idiom for consistency.

Verification:
Automated:
  facto-helper.sh current-issue   # prints 23 on this branch
Manual:
  1. Read Phase 1 of plan-architecture/SKILL.md.
  2. Confirm it tries Issue bootstrap first, uses the Issue as the brain
     dump without a confirmation question, and falls back to the generic
     prompt when no Issue resolves.
```

---

## Test Plan

This repo has **no automated test framework for skill prose** (bash bin scripts have tests under
`plugins/*/bin/tests/`, but skills do not), and **no CI workflows**. Validation is therefore the
mechanism check plus prose review:

- [ ] `facto-helper.sh current-issue` resolves `23` on the current branch.
- [ ] The guarded `tracker.exists` / `current-issue` / `gh issue view` snippet runs clean and returns
      the Issue JSON.
- [ ] `git diff --stat` shows only `plugins/facto/skills/plan-architecture/SKILL.md` changed.
- [ ] Prose review confirms the four Phase 1 behaviors (bootstrap-first, Issue-as-brain-dump with no
      confirmation, exact generic fallback, "don't explore codebase yet" preserved).
- [ ] Manual end-to-end (documented as blocked-no-tooling): re-run `/facto:plan-architecture` in a task
      worktree and confirm Phase 1 boots from the Issue.

## Risks

- **Runtime behavior is not automatable (blocked-no-tooling).** The fix is prose interpreted by an agent;
  no harness can assert "Phase 1 read the Issue." Mitigated by verifying the underlying mechanism
  (`current-issue`) and keeping the prose unambiguous — but final confirmation requires a manual re-run.
- **Silent pre-populate (option b) can start the interview on a wrong premise** if the worktree's Issue
  isn't exactly what the developer wants to architect (sub-scope or pivot). Mitigated by the non-blocking
  notice ("correct me at any point if the scope is different") so the developer can redirect immediately.
