---
name: plan-design
description: "Designs a feature's UI/UX. It produces a design decisions document and a Figma-like design mock file. These cover all screens, transitions, states, interactions, copy, design-system references, and divergences from existing patterns for the given feature. Invoke with /facto:plan-design. In the broader workflow, this skill sits between /facto:plan-product and /facto:plan-implementation. Procedure skill (follow the phases in order)."
color: purple
---

# Inputs

> **Model:** when run as a subagent, prefer `model: opus`.

Any previously-created product requirements documents, design system documentation, existing designs within the codebase.

# Outputs
The two output files together form the complete design spec for the feature. They are:
1. A design document (HTML file) that includes notes on design decisions, alternatives considered, and the final design spec.
2. A design mock HTML file that visually represents the design spec for the feature.

---

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description of the phase's goal as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Create design document` — activeForm: `Creating design document`
2. `Phase 2: Absorb inputs` — activeForm: `Absorbing inputs`
3. `Phase 3: Information hierarchy and flows` — activeForm: `Mapping views and flows`
4. `Phase 4: Adversarial review` — activeForm: `Reviewing flows and hierarchy`
5. `Phase 5: Design mock` — activeForm: `Producing design mock`
6. `Phase 6: Summarize design decisions` — activeForm: `Summarizing design decisions`
7. `Phase 7: Update evergreen docs` — activeForm: `Updating evergreen docs`

All tasks start as `pending`. At the start of each phase below, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that phase, set it to `completed`.

---

## Phases

### Phase 1: Create empty design document
Set the Phase 1 task to `in_progress`.

All planning docs for one task live together in a single per-task directory: `facto-tasks/<task-slug>/`. Resolve it with the shared helper so every skill agrees on the same location:

```bash
TASK_DIR="$(facto-helper.sh task-dir)" || true
```

If `facto-helper.sh task-dir` fails (e.g. you're not in a task worktree / on a feature branch), ask the developer for a short kebab-case slug and resolve it with `TASK_DIR="$(facto-helper.sh task-dir "<slug>")"`. Then `mkdir -p "$TASK_DIR"`.

Create a new HTML document at `$TASK_DIR/design-decisions.html`. This will hold notes you make about options you consider and decisions you make in the following phases, as well as the final design spec you produce.

For now, just create the document and give it a title.

Set it to `completed`. **End of phase:** continue immediately to Phase 2.

### Phase 2: Absorb and summarize inputs
Set the Phase 2 task to `in_progress`.

Locate and read the following inputs:
1. **Upstream planning docs** — typically the product requirements document produced by `/facto:plan-product`. May include other planning docs the developer points to.
2. **The design system and design documentation for the relevant surface only.** A repo may have multiple surfaces (e.g. backend, web frontend, mobile frontend). If the feature lives in one surface, only read that surface's design system — don't pull in others.
3. **Evergreen design docs for the relevant surface** — the project-wide view specs that persist across tasks. Start from `docs/design/index.md` to discover what exists, then read the `docs/design/<surface>/views/*.html` specs relevant to the feature. See `/facto:ref-design-system` for the layout and view model. Read these for inventory and reuse (what already exists, which patterns to match); if you need to judge how an existing view actually *looks*, render it per `/facto:ref-design-system`'s "Reading vs Rendering" rather than reading the markup. If these docs don't exist yet for the surface, note that and continue.
4. **Existing design in the codebase** — design specs for prior features, or the live UI code itself. Used as a reference for consistency.

Add a new section to the design document. Write a concise summary of the key points you learned from the inputs.

#### Guiding rules for inputs
As you use these inputs later, keep these rules in mind:
- **The design system is the highest authority.** Follow it.
- **Reuse existing components and patterns before designing new ones.** Check the relevant view specs and the surface's design system for an existing component or pattern that fits the need, and reuse it. Only introduce a new one when nothing existing is close enough.
- **Default to matching existing feature design** for consistency across the product.
- **Diverge only when it's genuinely better** for what we're building.
- **Flag every divergence and inconsistency** to the developer — both from the design system and from existing features — so they can be reviewed explicitly.

Set Phase 2 task to `completed`. **End of phase:** continue immediately to Phase 3.

### Phase 3: Draft information hierarchy, flows, taxonomies
Set the Phase 3 task to `in_progress`.

In this phase, our goal is to draft the very high-level user experience flow, navigation, and the environmental conditions the design must hold up under.

Focus on the high-level user experience flow, UX navigation between screens, and the environmental edge cases the design must hold up under. Do NOT go into details of how a specific screen works or looks, or any technical/engineering details. Tune the complexity or simplicity of your output to match the complexity or simplicity of the feature itself and don't add additional details beyond what is instructed here.

Based on the inputs, determine information hierarchy and navigation for the new feature. If the PRD has any omissions or deferred decisions, make your best determination. Add the following to the design doc in a new section:
1. View inventory — List every view (screen, region, or overlay — using the `/facto:ref-design-system` view model as inclusive examples) that needs to be added or changed to implement this feature. This maps directly onto the evergreen view specs (`docs/design/<surface>/views/`) that will be created or updated later.
2. Flow inventory and flow map — First, list every distinct user flow the feature involves as a numbered inventory; each entry names the flow, its entry point, and its completion condition. Source it from the PRD's "User Workflows" section, plus any flow the PRD implies but does not name (for example an error-recovery path or a first-run path). Then create the flow map: a flowchart where each node is one view involved in this feature, and each edge represents a possible transition between views. For each transition, note the trigger (user action, API response, timer, etc.). The flow map covers the same set as the inventory — every inventory entry is traceable through it.
3. Environmental edge case inventory — List the environmental conditions this feature will run under and state how the design handles each, or state explicitly that it doesn't. Examples where relevant: window resizing and viewport sizes, dark/light mode, browser zoom, unusually long text or large data volumes, slow or missing network, keyboard-only use. Those examples are illustrative, not a checklist to satisfy — cover what actually applies to this surface and this feature, and if nothing environmental applies, say that and move on. One sentence per item is enough, and "unsupported — out of scope" is an acceptable handling as long as it's written down. Mark which entries change the layout; those are the ones the mock draws in Phase 5.

Then list any important, non-obvious navigation and environmental-handling decisions you made when choosing that view inventory, flow map, and edge case handling. For example, if you had to choose between two different ways to navigate between views, choose between adding more to an existing view versus creating a new one, choose to reflow versus scroll at a narrow width, or declare a condition unsupported. For each decision, list any alternatives you considered, pros and cons, and your reasoning. ONLY include decisions specific to the scope of navigation, information hierarchy, and environmental handling, not decisions about specific view design, technical implementations, or anything else. Only list decisions that fit this criteria — if there are none, list none.

Set Phase 3 task to `completed`. **End of phase:** continue immediately to Phase 4.

### Phase 4: Adversarial review on flows and hierarchy
Create a subagent. Give it the same inputs you have, plus what you created in the previous phase. Instruct the subagent to do an adversarial review of the flow inventory, flow map, view inventory, and environmental edge case inventory you created in Phase 3. The subagent's goal is to find any possible flaw, gap, inefficiency, or non-obvious problem in the flow inventory, flow map, view inventory, and environmental edge case inventory — including whether the flow inventory is complete against the PRD's user workflows, covering flows the PRD implies but does not name. The subagent should be critical and try to break the flow or find problems for users. Scope its review to the feature set the requirements ask for: it judges how well the design delivers those features, and must not propose new features or capabilities beyond them.

Consider each piece of feedback the reviewer gives you. Address points that are objectively valid and within the feature set the requirements ask for. Ignore feedback you still don't think is correct. If a point is valid but the only way to resolve it is to add a feature or capability the requirements don't ask for, leave the design as it is and note the point for the developer in Phase 6 — never resolve a finding by adding a capability. Then send the plan back to the reviewer for another round of review. Repeat until the reviewer has no more valid feedback, up to 3 rounds maximum.

Set Phase 4 task to `completed`. **End of phase:** continue immediately to Phase 5.

### Phase 5: Design mock
Set the Phase 5 task to `in_progress`.

Read /facto:ref-design-mock to understand the mechanics of creating and editing the design mock file. Using those instructions, produce a design mock file at `$TASK_DIR/design-mock.html` (with any assets in `$TASK_DIR/assets/`) — pass `$TASK_DIR` to the mechanics as the destination directory, the flow inventory from Phase 3 as the list of flows, and the environmental edge case inventory from Phase 3 as the list of edge cases. Use `/facto:ref-design-mock` as the mechanics reference — it defines how to copy the template, fill in tokens/frames/bands, and serve and inspect the output; the design decisions themselves (what to show, how to lay it out, which components to use) are yours to make based on the inputs and decisions from the phases above. If any open questions arise, use your best judgment to resolve them.

Before ending the phase, serve and inspect the mock using the mechanics in `/facto:ref-design-mock`, and confirm every entry in the flow inventory is covered end to end — from its entry point to its completion condition — and every edge-case entry marked as changing the layout has a frame, with the band removed rather than left as stubs if none are so marked. If anything is missing, stops short, or is still a template stub, fix it and re-inspect.

Set Phase 5 task to `completed`. **End of phase:** continue immediately to Phase 6.

### Phase 6: Summarize design decisions and open questions

Set the Phase 6 task to `in_progress`.

Summarize everything to the developer:
1. Big decisions you made in the phases above, especially any that diverge from the design system or existing patterns in the codebase. For each decision, list any alternatives you considered, pros and cons, and your reasoning.
2. Important feedback you received from your reviewer(s), plus whether and how you addressed it.
3. The flow inventory from Phase 3, naming every flow covered, so the developer can spot a missing workflow without opening the mock.
4. The environmental edge case inventory from Phase 3, naming every item and its handling, so the developer can catch a wrong handling — e.g. "you marked resizing out of scope and it isn't" — without opening the mock.
5. The URLs for the two output files you created.

Do not commit yet — the commit happens after Phase 7 so that the per-task design files and the evergreen updates land in a single changeset.

Set Phase 6 task to `completed`. **End of phase:** continue immediately to Phase 7.

### Phase 7: Update evergreen docs

Set the Phase 7 task to `in_progress`.

**Visual surfaces only.** If the feature has no visual surface (e.g. it is backend-only or purely an API change with no UI), skip the upsert steps and go straight to the commit below.

For **each surface the feature touches**, run the upsert mechanics in `/facto:ref-design-system` ("How to Upsert") against this task's view inventory: add, update, or remove/rename the view specs and update the index so they reflect exactly what this task changed. `/facto:ref-design-system` is the single source of truth for that routine — follow it there rather than restating the steps here.

**Commit — per-task design files and evergreen updates together in one commit.** Stage only the specific paths touched — never `git add -A`:

```bash
# Per-task design files (always staged)
git add "$TASK_DIR/design-decisions.html" "$TASK_DIR/design-mock.html"
[ -d "$TASK_DIR/assets" ] && git add "$TASK_DIR/assets"

# Evergreen paths touched (visual surfaces only; repeat per surface; omit if backend-only)
git add docs/design/<surface>/views/<view>/            # the view folder (spec + harnesses); repeat per view
git add docs/design/<surface>/views/assets             # if fonts/assets were added
git add docs/design/index.md                           # if views were added, removed, or renamed

git commit -m "docs: add design for <task-slug>"
```

Recommend running /facto:plan-implementation next.

Set Phase 7 task to `completed`. **End of skill:** Stop here.
