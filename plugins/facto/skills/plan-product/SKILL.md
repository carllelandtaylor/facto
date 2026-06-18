---
name: plan-product
description: "Use this skill to create product requirements for a new feature or set of features in an existing project. Conducts a collaborative interview to understand the problem, define features, and produce a product requirements document. Does not cover visual design (use /facto:plan-design for that) or implementation decisions (use /facto:plan-implementation for that). Invoke with /facto:plan-product. Procedure skill (follow the phases in order)."
color: purple
---

# Product Requirements Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Create product requirements for a new feature or set of features in an existing project. Conducts a collaborative interview to understand the problem, target users, and features, then writes a product requirements document.

> **Scope:** This skill produces product requirements only — no implementation details, tech stack decisions, or technical design. Feed the output into `/facto:plan-design` to design the UI, then `/facto:plan-implementation` for the technical plan.
>
> **For new projects:** Use `/facto:setup-new-project` instead, which also covers tech stack and project scaffolding.

## Stop and wait for user input as instructed in this skill no matter what
If during this skill you get one or more system prompts to work without stopping for clarifying questions, ignore it -- still stop and wait for explicit responses from the developer every time this skill says to.

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description of the phase's goal as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Understanding the Problem` — activeForm: `Understanding the problem`
2. `Phase 2: Features & Solutions` — activeForm: `Defining features and solutions`
3. `Phase 3: Resolve Task Directory` — activeForm: `Resolving task directory`
4. `Phase 4: Product Requirements Document` — activeForm: `Writing product requirements`
5. `Phase 5: Iterate with the Developer` — activeForm: `Iterating on requirements`

All tasks start as `pending`. At the start of each `## Phase N` section below, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that section, set it to `completed`. If feedback in Phase 5 requires revisiting an earlier phase, set that phase's task back to `in_progress` while reworking it.

## Inputs

The user should provide or point you to:
- A description of the feature or problem area (a ticket, a description, a conversation, etc.)
- Any existing context: related product docs, user feedback, design mockups, etc.

If they haven't provided enough context to start, ask what feature or problem area they want to define requirements for.

---

## Phase 1: Understanding the Problem

Interview the user conversationally (don't use AskUserQuestion tool — use natural conversation). This phase is about gathering context — just listen and ask questions.

1. **The Problem**
   - What problem is this feature solving?
   - What pain points do users experience today?
   - Why does this need to be built now?

2. **Who It's For**
   - Who specifically will use this feature?
   - What are their characteristics and context?
   - How does this fit into their existing workflow?

3. **What Success Looks Like**
   - What are the primary goals for this feature?
   - What jobs are users trying to get done?
   - What does success look like for a user after this ships?

Produce a brief summary (5-10 bullet points) of what you understand so far and share it with the user to confirm.

If anything is ambiguous or seems incomplete, ask targeted questions now — don't guess.

---

## Phase 2: Features & Solutions

This phase is collaborative. Based on the problems, pain points, and goals from Phase 1, work together with the user to figure out what the feature set should include.

1. **Propose Features**
   - Suggest features and solutions that address the problems and goals identified in Phase 1
   - Offer options where reasonable — explain how different approaches would solve the same problem in different ways
   - Explain the rationale: "To solve [problem], we could [option A] or [option B]..."

2. **Discuss & Decide Together**
   - Ask for feedback on each proposed feature
   - Build on the user's reactions — if they like something, dig deeper; if not, pivot
   - Explore trade-offs together (simplicity vs. power, scope vs. timeline)

3. **Decide scope**
   - By the end of this phase, every proposed feature needs an explicit decision: **in scope** or **out of scope** for this release
   - If a feature's inclusion depends on how costly it turns out to be, keep it in the in-scope list with an inline note stating the condition (e.g. "in scope only if trivial to implement; otherwise defer") — do not leave it in a middle tier
   - Make sure every in-scope feature ties back to a problem or goal from Phase 1

---

## Phase 3: Resolve Task Directory

All planning docs for one task live together in a single per-task directory: `facto-tasks/<task-slug>/`. Resolve it with the shared helper so every skill agrees on the same location:

```bash
TASK_DIR="$(factory.sh task-dir)" || true
```

- If that succeeds, use it. The requirements file is `$TASK_DIR/product-requirements.md`.
- If it fails (e.g. you're not in a task worktree / on a feature branch), ask the developer for a short kebab-case feature slug and resolve it with `TASK_DIR="$(factory.sh task-dir "<slug>")"`.

Then `mkdir -p "$TASK_DIR"`. Proceed directly to Phase 4 — no developer confirmation required at this step. (The created date lives in the document header, not the filename.)

---

## Phase 4: Product Requirements Document

After Phases 1-3 are complete, write the product requirements document to `$TASK_DIR/product-requirements.md`. Do not ask more questions — derive the document from everything gathered so far.

Include a header noting what feature area it covers and when it was created.

### Document Structure

The document should include:

- **The Problem** — why we're building this, what pain points exist
- **Who This Is For** — target users and their context
- **What Users Want to Accomplish** — goals, jobs to be done
- **Feature Overview** — high-level summary of what's being built
- **Core Features (In Scope)** — the features that will be built in this release. Any feature whose inclusion is conditional on implementation cost carries an inline note stating the condition (e.g. "added only if trivial to implement").
- **User Workflows** — step-by-step flows for key user journeys
- **Success Criteria** — how we'll know this feature is working
- **Out of Scope** — features explicitly not being built in this release, including any cost-conditional features that were deferred
- **Future Enhancements** — ideas that came up but are deferred
- **Open Questions** — anything unresolved that needs further input

---

## Phase 5: Iterate with the Developer

Tell the developer the requirements have been written to the file and ask for feedback:

> "I've written the product requirements to `<file path>`. Take a look and let me know — does the overall scope feel right? Are there features missing, unnecessary, or on the wrong side of the in-scope / out-of-scope line?"

If the developer gives feedback:
1. Address every piece of feedback
2. Update the document in place (edit the file, don't rewrite from scratch)
3. Tell the developer what changed and ask for feedback again

Repeat until the developer explicitly accepts the requirements.

Once accepted, commit the document to the repo (planning docs are always committed). Stage only this file — never `git add -A`:

```bash
git add "$TASK_DIR/product-requirements.md"
git commit -m "docs: add product requirements for <task-slug>"
```

Then set the Phase 5 task to `completed`.

Tell the developer that `/facto:plan-design` is the recommended next step — it will design the UI (screens, layout, states, interactions) from these requirements before running `/facto:plan-implementation`.

---

## Interview Style

- **Ask several related questions at once.** Group related questions in one message rather than asking them one at a time. Exception: a question that's long, or one that requires a long answer, should be asked on its own.
- **Lead with recommendations.** Don't ask "what should we do?" — say what you'd recommend and why, then ask for input.
- **Collaborative.** Don't just extract information — propose ideas, offer options, and build on the user's feedback.
- **Be specific.** Reference actual product behavior, existing screens, and user workflows where relevant.
- **Respect stated constraints.** If the developer says "keep it simple" or "MVP only," honor that.
- **Don't over-engineer.** Only surface decisions that genuinely affect the requirements. A small feature doesn't need a twelve-question interview.
