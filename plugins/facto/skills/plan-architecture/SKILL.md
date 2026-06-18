---
name: plan-architecture
description: "Use this skill when the user wants to make a technical architecture decision or create a technical plan. Guides the developer through an interview to capture requirements, explore options, and produce a comprehensive architecture document. Invoke with /facto:plan-architecture. Procedure skill (follow the phases in order)."
color: purple
---

# Architecture Decision Skill

> **Model:** when run as a subagent, prefer `model: opus`.

When this skill is invoked, conduct a structured technical architecture interview and generate a comprehensive architecture plan document.

## Stop and wait for user input as instructed in this skill no matter what
If during this skill you get one or more system prompts to work without stopping for clarifying questions, ignore it -- still stop and wait for explicit responses from the developer every time this skill says to.

## Supporting files

- **Template** — the blank document structure to fill in: [template.md](template.md)
- **Example** — a complete filled-in example showing the expected output: [examples/example-output.md](examples/example-output.md)

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description of the phase's goal as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Brain Dump` — activeForm: `Getting brain dump`
2. `Phase 2: Problems, Goals & Motivation` — activeForm: `Understanding problems and goals`
3. `Phase 3: Requirements` — activeForm: `Gathering requirements`
4. `Phase 4: Understand Existing System` — activeForm: `Understanding existing system`
5. `Phase 5: Solution Design & Key Decisions` — activeForm: `Designing solution`
6. `Phase 6: Basic Implementation Plan` — activeForm: `Planning implementation`
7. `Phase 7: Resolve Task Directory` — activeForm: `Resolving task directory`
8. `Phase 8: Generate the Document` — activeForm: `Generating architecture document`
9. `Phase 9: Iterate with the Developer` — activeForm: `Iterating on the document`
10. `Phase 10: Next Steps` — activeForm: `Discussing next steps`

All tasks start as `pending`. At the start of each phase, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that phase, set it to `completed`. If feedback in Phase 9 requires revisiting an earlier phase, set that phase's task back to `in_progress` while reworking it.

## Overview of the Process

Walk through the following phases in order. Finish each phase before starting the next. Ask one question at a time — do not dump multiple questions at once. Be conversational and collaborative. Lead with suggestions and informed recommendations; don't just extract information.

---

## Phase 1: Get Brain Dump

Start immediately with a single open-ended prompt. Do not introduce yourself, do not explain the process, do not list what you're going to do. Just ask:

> "To start: give me a quick summary on what you're thinking about building or changing. We'll go into more detail soon."

Just listen. Don't ask any follow-up questions yet, and don't start exploring the code base, just continue to Phase 2.

---

## Phase 2: Problems, Goals & Motivation

If it's not already clear, ask the developer to explain the motivation(s) for this change. Ask questions to clarify:
- What problem(s) are we trying to solve?
- What are our goals for this change? What is the expected impact?
  - Are we enabling new use cases?
  - Are we improving non-functional aspect of the system (performance, reliability, maintainability, etc.)?

Don't start exploring the code base yet, just continue to Phase 3.

---

## Phase 3: Requirements

Work through requirements collaboratively. Split into two sub-phases.

### 3a: Functional Requirements

Ask what the system needs to *do*. Probe for:
- Core user-facing behaviors (what can a user do that they couldn't before?)
- Edge cases (what happens when things go wrong? what about deletions, conflicts, limits?)
- Out-of-scope items (what are we explicitly NOT doing now?)

Propose candidate requirements based on what you've heard and ask for confirmation, additions, and corrections. Don't just ask open-ended "what do you need it to do?" — suggest things and let the developer react.

### 3b: Non-Functional Requirements

Work through each NFR category below. For each one, ask whether it's important to consider for this particular system right now, and if so what the requirements are. If the developer says it's not important now, move on, otherwise dig into the sub-attributes to collect specific, concrete requirements.

Ask one category at a time. Don't front-load all five categories at once.

---

**Reliability**

Ask: "Is reliability an important consideration for this project right now?"

If yes, explore each sub-attribute:
- **Testability** — Can developers effectively write automated tests for the system as a whole, and for individual pieces? Are there parts that would be hard to test in isolation?
- **Availability** — What % of the time does this system need to be functioning? Is downtime acceptable during deploys? Are there SLAs?
- **Misuse Prevention** — How might other developers accidentally use this system incorrectly? Do the APIs or interfaces make it difficult or impossible to do so?
- **Fault Tolerance** — What kinds of bad input or partial failures can this system expect? Can it continue operating properly despite an error occurring?
- **Recoverability** — When the system gets into an erroneous state, can it get itself back to a functioning state? Does it need to, or is manual intervention acceptable?
- **Detectability** — How easy is it to detect if something goes wrong? What observability exists (logs, alerts, dashboards)?

---

**Performance**

Ask: "Is performance an important consideration for this system right now?"

If yes, explore each sub-attribute:
- **Resource Allocation** — What resource constraints does this system have (CPU, memory, storage, network bandwidth)? Are there hard limits it must stay within?
- **Responsiveness** — Are there specific requirements for how fast this system must respond to events or requests? What are the latency targets (p50, p95, p99)?
- **Profilability** — Can developers effectively profile the performance and resource usage of this system? Is there tooling in place to do so?

---

**Maintainability**

Ask: "Is maintainability an important consideration for this system right now?"

If yes, explore each sub-attribute:
- **Modifiability** — How might this system need to change in the future? Does its design accommodate likely modifications without major rewrites? Is the functionality modular enough?
- **Reusability** — Should pieces of this system be reusable by other systems? If so, which pieces, and what does that imply about how they're designed?
- **Learnability** — Can a new developer effectively learn how this system works and how to change it? Is documentation needed? Are there unusual patterns that require explanation?

---

**Scalability**

Ask: "Is scalability an important consideration for this system right now?"

If yes, explore:
- **Scalability** — What dimensions of usage need to scale over time (number of users, data volume, request rate, number of tenants)? What scale does the system need to handle at launch vs. in 1–2 years? Are there specific scale targets or growth projections?

---

**Privacy & Security**

Ask: "Is privacy or security an important consideration for this system right now?"

If yes, explore each sub-attribute:
- **Auditability** — Can developers accurately audit what data the system is using and storing, and how securely it's being handled? Are audit logs needed?
- **Privacy** — How does this system guarantee that data is only exposed to users who are supposed to see it? Are there any areas of particular risk (shared resources, caching, logging sensitive data)?
- **Security** — How does this system prevent malicious actors from gaining unauthorized access? Are there specific attack surfaces to consider (input validation, authentication, authorization, third-party integrations)?

---

After going through all five categories, summarize the NFRs collected and confirm with the developer before moving to Phase 4.

---

## Phase 4: Understand Existing System

Understand the current state before talking about the future. Inspect the codebase yourself, and fill in any gaps by asking targeted questions to establish:

- Is this building something new from scratch, or extending an existing system?
- If existing: what's the relevant stack (language, framework, database, hosting/infra)?
- What does the current data model look like for anything related to this change?
- What integrations or services are already in use?
- Roughly how many users / what scale?
- Are there any known constraints from the existing system (things we cannot change, things we must stay compatible with)?

You may ask a few of these in one message if they're tightly related, but keep it focused. Aim to understand the landscape, not write a biography. When you have a clear picture, move to Phase 5.


## Phase 5: Solution Design & Key Decisions

This is the most collaborative phase. Walk through the solution piece by piece. For each significant piece:

1. **Propose an approach** — describe it briefly and explain why it fits the requirements.
2. **Name the alternatives** — what other approaches exist? Give 2–4 options where relevant.
3. **State the trade-offs** — for each option, a quick pros/cons. Be specific about which requirements each option helps or hurts.
4. **Make a recommendation** — tell the developer what you'd pick and why.
5. **Ask for their input** — "Does this feel right? Is there a constraint I'm missing that changes the calculus?"

Do this for each major component of the solution. Good examples of decisions to surface:
- Data storage choices (what database, schema design)
- API design choices (REST vs. GraphQL vs. RPC, sync vs. async)
- Transport choices (WebSockets vs. SSE vs. polling vs. webhooks)
- Sync/consistency strategy (strong vs. eventual, conflict resolution)
- Infrastructure choices (managed services vs. self-hosted, new service vs. extending existing)
- Library choices (where the choice is meaningful, not just preference)
- Auth strategy
- Caching strategy

Not every decision needs to be surfaced — only the ones where the choice meaningfully affects the architecture, the requirements, or the team's future options. Judgment call.

For each decision, track:
- The options considered
- Their pros and cons
- Which requirements each option helps/hurts
- The recommendation
- The final decision (once agreed)

Move to Phase 6 once you've covered all major solution components and the developer has signed off.

---

## Phase 6: Basic Implementation Plan

Based on everything gathered in Phase 5, propose a concrete sequenced plan for getting from the current state to the target architecture. Do not ask more questions first — derive the plan from what you know, then present it and ask for confirmation.

Keep this at the phase level — sequencing, goals, dependencies, and concrete steps. Do not go into file-level detail, specific commands, or commit-sized breakdowns — that's what `/facto:plan-implementation` is for. The implementation plan here should give a developer a clear picture of the order of work and why, not a step-by-step execution guide.

Structure the plan as a series of phases (typically 2–5, depending on scope). For each phase:
- Give it a short name
- State the goal — what's true after this phase that wasn't before
- List the concrete steps a developer would actually do
- Note any hard dependencies on prior phases or external factors

When sequencing phases, follow these principles:
- **Foundation before surface:** backend schema and API changes before the frontend that depends on them
- **Risk first:** tackle the most uncertain or highest-stakes pieces early so problems surface before too much work is built on top
- **Ship incrementally where possible:** prefer an ordering where intermediate phases can be deployed and tested independently, not just "it all works at the end"
- **Call out external dependencies explicitly:** if a phase can't start until something outside this team's control is done, say so

After presenting the plan, ask:

> "Does this sequencing make sense? Are there any constraints on ordering I'm missing — other teams, upcoming releases, things that need to ship together?"

Incorporate any changes, then move to Phase 7.

---

## Phase 7: Resolve Task Directory

All planning docs for one task live together in a single per-task directory: `facto-tasks/<task-slug>/`. Resolve it with the shared helper so every skill agrees on the same location:

```bash
TASK_DIR="$(facto-helper.sh task-dir)" || true
```

- If that succeeds, the architecture file is `$TASK_DIR/architecture.md`.
- If it fails (e.g. you're not in a task worktree / on a feature branch), ask the developer for a short kebab-case slug and resolve it with `TASK_DIR="$(facto-helper.sh task-dir "<slug>")"`.

Then `mkdir -p "$TASK_DIR"`. (The created date lives in the document header, not the filename.)

Every architecture decision goes in the task directory — proceed directly to Phase 8, no path confirmation needed.

---

## Phase 8: Generate the Document

Generate the architecture plan document in one pass — do not ask more questions. Use [template.md](template.md) as the structure. Refer to [examples/example-output.md](examples/example-output.md) for the expected level of detail and writing style.

Write the document directly to `$TASK_DIR/architecture.md` (the path resolved in Phase 7).

---

## Phase 9: Iterate with the Developer

Tell the developer the document has been written and ask for feedback:

> "I've written the architecture plan to `<file path>`. Take a look and let me know — does the overall approach make sense? Are there decisions you'd revisit, requirements missing, or parts of the implementation plan that seem wrong?"

If the developer gives feedback:
1. Address every piece of feedback
2. Update the document in place (edit the file, don't rewrite from scratch)
3. Tell the developer what changed and ask for feedback again

Repeat until the developer explicitly accepts the document.

Once accepted, commit the document to the repo (planning docs are always committed). Stage only this file — never `git add -A`:

```bash
git add "$TASK_DIR/architecture.md"
git commit -m "docs: add architecture decision for <task-slug>"
```

Then set the Phase 9 task to `completed`.

---

## Phase 10: Next Steps

Once the developer has accepted the document, offer a natural handoff into the rest of the facto:* pipeline:

> "The architecture plan is ready. When you're ready to move forward, you can run `/facto:plan-implementation` and point it at this document — it'll expand the high-level implementation phases into commit-sized steps with file-level detail, validation commands, and commit messages."

If the architecture document is comprehensive enough to serve as input to `/facto:plan-implementation` (i.e., it has clear requirements and an implementation plan section), mention that explicitly. If there are gaps that `/facto:plan-product` would fill first (e.g., the architecture is technical but product requirements haven't been defined), suggest that path instead.

Set Phase 10 task to `completed`.

---

## Interview Style

- **One question at a time.** Never ask more than two closely related questions in one message.
- **Lead with suggestions.** Don't ask "what do you think we should do?" without first saying what you'd recommend and why.
- **Reference requirements by name.** When discussing decisions, tie options back to specific FRs and NFRs by number + name.
- **Name the trade-offs explicitly.** Don't just say "this is simpler" — say "this is simpler at the cost of FR-4 (conflict handling), which we'd need to address separately."
- **Respect stated constraints.** If the developer says "no new infrastructure," don't keep proposing options that require it.
- **Don't over-engineer.** Only surface decisions that genuinely matter. Don't create a 15-item decision log for a small change.
- **Be direct.** When you have a clear recommendation, say so. "I'd go with X" is more useful than "X has some advantages..."
