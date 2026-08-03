---
name: setup-design
description: "Stands up evergreen design documentation for an existing app from its current state: collects project-wide design docs, and generates design specs/mocks for each discoverable view, then indexes it all together. Invoke with /facto:setup-design. Procedure skill (follow the phases in order)."
color: cyan
---

# Design Bootstrap Skill

> **Model:** when run as a subagent, prefer `model: opus`.

Bootstrap the project-wide evergreen design docs for an existing app that has no or incomplete design docs/specs yet. See `/facto:ref-design-system` for nomenclature and directory structure.

---

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description of the phase's goal as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Discover surfaces` — activeForm: `Discovering surfaces, commands, etc.`
2. `Phase 2: Discover views` — activeForm: `Discovering views`
3. `Phase 3: Create design mocks` — activeForm: `Creating design mocks`
4. `Phase 4: Write the index` — activeForm: `Writing the index`
5. `Phase 5: Create PR` — activeForm: `Creating PR`

All tasks start as `pending`. At the start of each phase, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that phase, set it to `completed`.

---

## Phase 1: Discover surfaces

Set the `Phase 1` task to `in_progress`.

Autonomously determine everything needed to proceed — do not ask the developer. Inspect the repo and running environment directly:

**1. Repo root**

```bash
git rev-parse --show-toplevel
```

**2. Visual surfaces**

A surface is a distinct rendering target with its own UI code (e.g. `web`, `ios`, `android`). Discover them by inspecting the repo structure:

- Look for top-level directories or workspace packages whose names or contents suggest a UI rendering target (`web/`, `mobile/`, `ios/`, `android/`, `app/`, `frontend/`, `client/`, etc.).
- Within each candidate, check for UI framework indicators: `package.json` with React/Vue/Angular/Svelte dependencies, `*.swift` files (SwiftUI), `*.kt` files with Compose imports, `*.dart` (Flutter), etc.

Record each confirmed surface and its top-level source directory.

**3. Commands to run, interact with and screenshot the app(s)**

For each surface, determine how to:
1. Launch the app
2. Interact with its UI like a real user
3. Take screenshots **at the device's native resolution**

The repo may specify this in documentation. Verify your findings by trying them all out.

Also capture the surface's **device profile** and how to read its element geometry, as defined in `/facto:ref-design-mock` "How to match a real running app". Phase 3 needs both to build device-accurate mocks.

**4. Existing design assets**
Find any existing repo-wide and/or surface-wide design documentation or assets that can inform the inventory and evergreen docs. Some common but non-exclusive places to check:
- `docs/design/<surface>/design-system.md`
- `facto-tasks/*/design-*`

**5. Create inventory file and write findings**

Create the inventory file in the task directory from the template:

```bash
INVENTORY="$(facto-helper.sh task-dir)/design-inventory.md"
mkdir -p "$(dirname "$INVENTORY")"
cp "[facto] plugins/facto/skills/setup-design/template-inventory.md" "$INVENTORY"
```

Into the inventory file, write the info you've collected so far.

Set the `Phase 1` task to `completed`. **End of phase:** continue immediately to Phase 2.

---

## Phase 2: Discover views

Set the `Phase 2` task to `in_progress`.

For each surface, run steps 2a-2c.

### 2a. Launch surface
Launch the surface's app using the launch instructions discovered previously.

### 2b. Discover views via source code
Look through the surface's source code to find all views (screens, regions, overlays) that you can identify. For each view found in code, try to navigate to it in the live app to verify its existence, behavior and appearance. From the source, also enumerate **every state** each view can be in (default/loaded, loading, empty, error, edge-cases) — Phase 3 must spec all of them, not just the happy path.

You are allowed and encouraged to take app actions that make back end changes if needed to access a view or a state (ex: create a new user, delete an existing record, cut the network to force an error). If you still can't figure out how to navigate to or trigger a view or one of its states in the live app, note it.

For each view, screenshot **every state you can drive the app into** (one screenshot per state, at native resolution) and, while you are on each one, capture the element geometry per `/facto:ref-design-mock` "How to match a real running app". Note all the information you'll need to fill in the inventory file. Save each screenshot like `<task dir>/inventory/<view-slug>--<state>.png`. List the states you could not reach.

### 2c. Fill in inventory file
Fill in all info you find for each view into the appropriate section of the inventory file.

Set the `Phase 2` task to `completed`. **End of phase:** continue immediately to Phase 3.

<!-- In the future if gaps are found in view discovery, add an adversarial review here -->

## Phase 3: Create design mocks

Set the `Phase 3` task to `in_progress`.

Create one subagent per surface. Give them the inventory file, and ask them to follow the following Phase 3a to create the design mocks for their surface:

### Phase 3a. Create design mocks for a surface
For each view discovered, create a design-mock spec file using `/facto:ref-design-system` "How to Write a View Spec" and `/facto:ref-design-mock`. These views already exist in a running app, so build each one device-accurate and prove it against the live app, per `/facto:ref-design-mock` "How to match a real running app" and "How to render at device scale and diff against the app".

Bootstrap-specific orchestration on top of those mechanics:

1. Spec every state captured in Phase 2, proving each against its own screenshot. For a state you could not reach live, build it from source and the design system and mark it unverified.
2. Adversarially review each state on two axes — one reviewer compares the rendered mock against the live screenshot, one checks that its values trace to source — and loop until both pass.
3. The full build-render-diff-review loop is expensive per state. Run it complete on one calibration view per surface first to settle the device profile, token mapping, and fonts, then reuse those for the remaining views.

**End of phase 3a:** subagent reports back to the main agent. Subagent's work is done.

Set the `Phase 3` task to `completed`. **End of phase:** continue immediately to Phase 4.

## Phase 4: Write the index

Set the `Phase 4` task to `in_progress`.

Create `docs/design/index.md` from the template and fill it in so it lists every surface, its overall design docs, and every view spec you produced:

```bash
cp "[facto] plugins/facto/skills/setup-design/template-index.md" docs/design/index.md
```

Follow the template's instructions and `/facto:ref-design-system` "The Index" for the format.

Set the `Phase 4` task to `completed`. **End of phase:** continue immediately to Phase 5.

## Phase 5: Create PR
Run `/facto:pr` via the Skill tool.

Set the `Phase 5` task to `completed`. **End of skill:** Stop here.
