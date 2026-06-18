---
name: ref-design-system
description: "Documents the contract for project-wide evergreen design docs: the docs/design/ layout and index, the view model, and the upsert routine. Reference skill (independent how-tos — use what you need, in any order)."
color: purple
---

# Evergreen Design Docs — Contract Reference

> **Model:** when run as a subagent, prefer `model: opus`.

How the project-wide evergreen design documentation works: what goes where, how views are modelled, how they are discovered, and how to keep it all in sync.

**This is a reference, not a procedure.** There's no required order — go to the section for whatever you're trying to do. Headers starting with "How to …" describe an action.

---

## Nomenclature

* **Surface:** A distinct target that has UI — e.g. `web`, `ios`, `android`. Backend-only targets with no visual output do not get evergreen docs.
* **View:** An addressable UI surface — a place the user can be, or a layer that appears over a place. Every view gets its own spec and per-state harnesses. Every view is specific to one surface. Types include:
  * `screen` — a destination or route; the user navigates *to* it (e.g. Home, Settings, Detail).
  * `region` — persistent chrome composed into many screens (e.g. nav bar, tab bar, side panel, header). A region appears across contexts but is documented *once*.
  * `overlay` — a transient surface that appears *over* a host view (e.g. modal, bottom sheet, popover, toast, menu). An overlay is documented *once*.
* **State:** A view can be in different states — e.g. default/loaded, loading, empty, error, and edge-cases. Every state gets its own entry in the view spec.

---

## Directory Structure

Evergreen design files in a repo are organized like so:

```
<repo root>/docs/design/
  index.md                              # index of every design doc (see "The Index")
  <surface>/                            # one per visual surface (e.g. android, admin)
    design-system.md                    # surface-wide "overall" docs live at the surface root
    <other surface-wide docs>           # any other surface-wide docs
    views/
      assets/                           # assets shared by multiple views (fonts, icons, …)
        fonts/<font>.ttf                # fonts shared by multiple views on this surface
      <view>/                           # one folder per view; slug = the view's role name
        <view>.html                     # the view spec (canvas: meta-card + states band)
        _<state>.html                   # one render harness per state (default, loading, …)
```

**Relative paths** — the docs are committed in-repo, so links are relative:

| From → to | Path |
|-----------|------|
| `<view>.html` → harness | `src="_<state>.html"` (same folder) |
| `<view>.html` → source file | `href="../../../../../<repo-path>"` (5×`../` to repo root) |
| `_<state>.html` → fonts | `url('../assets/fonts/<font>.ttf')` (1×`../`) |
| `index.md` → spec | `<surface>/views/<view>/<view>.html` |
| `index.md` → surface-wide doc | `<surface>/<doc>` |

---

## The Index

`docs/design/index.md` is the entry point for discovering design docs. It has one section per surface; each section links that surface's overall design docs (its `design-system.md` and any whole-surface files such as `light-mode.html`) and every view spec under `views/`. An agent or developer looking for what already exists starts here.

Keep it current: whenever a view or surface is added, removed, or renamed, update `index.md` to match (see "How to Upsert").

---

## How to Write a View Spec

The spec is a canvas shell that embeds one per-state render harness; build the harnesses per `/facto:ref-design-mock`'s "How to structure a device-accurate spec: shell + per-state harnesses".

1. The view's folder is `docs/design/<surface>/views/<view>/`. Copy `[facto] plugins/facto/skills/ref-design-system/template-evergreen-view-spec.html` → `<view>.html` there and fill in its header, meta-card, and one frame per state. Each state's harness is `_<state>.html` in the same folder; shared fonts live at `docs/design/<surface>/views/assets/fonts/`. Wire the `src`, source, and font links per "Relative paths" above.
2. At the top of the spec, declare the view's type tag (`screen`, `region`, `overlay`, or best-fit label) and — for overlays and regions — the "invoked from" / "appears in" list.
3. Draw **every** state the view can be in (default/loaded, loading, empty, error, and edge-cases) — one harness and one frame per state. The spec is not complete until all states are drawn, not just the happy path.
4. **When the view already exists in a running app** (bootstrapping from current reality, or auditing drift), build each harness device-accurately and prove it against the live app per `/facto:ref-design-mock`'s "How to match a real running app" and "How to render at device scale and diff against the app". Save the live screenshots you diff against in the task's `inventory/` directory (`<task-dir>/inventory/<view-slug>--<state>.png`) — they are the per-state verification diff targets. Prove each state you can drive the app into; for states you cannot reach live, build them from source and the design system and note that they were not verified against a live capture.

---

## How to Upsert (the Sync Contract)

Given a task's view inventory, apply these steps. Both `facto:plan-design` and `facto:setup-design` call this routine; it is the single source of truth for keeping evergreen docs current.

**For each view in the task's scope:**

1. If the view has no folder at `docs/design/<surface>/views/<view>/`, create one (following "How to Write a View Spec" above).
2. If the view already has a folder, update its spec and harnesses to reflect the changes this task introduces.
3. If this task **removed** the view, delete its folder; if it **renamed** it, rename the folder and the `<view>.html` inside, keeping the slug otherwise stable.

**Update the index:**

For every view or surface added, removed, or renamed, update `docs/design/index.md` to match (see "The Index").

Commit the modified evergreen files together with the task's design work.

---

## Reading vs Rendering a Spec

View specs are HTML *mock* files. To pull **structured facts** — a view's type, its states — reading the file is enough. To judge **appearance or fidelity**, you must **render** it: serve the view's folder over HTTP — the spec embeds its sibling `_<state>.html` harnesses — and screenshot via Playwright (`/facto:ref-design-mock`'s "How to serve and inspect"), then compare that render against a render of the running app, proving the match per `/facto:ref-design-mock`'s "How to render at device scale and diff against the app". Never judge appearance from raw markup.
