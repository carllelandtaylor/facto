# Implementation Plan: plan-design enumerates environmental edge cases

**Requirements and specs:** [Issue #93 — "FEATURE: plan-design enumerates environmental conditions (viewport, zoom, content volume) with explicit dispositions"](https://github.com/carllelandtaylor/facto/issues/93). No PRD or design docs exist for this task; the Issue body (What's missing / Why it would help / Sketch / Open questions) is the requirements input.
**Created:** 2026-07-31

---

## Requirements Summary

- `facto:plan-design` covers views, flows, and application states (loading / loaded / empty / error / first-run), but never asks about the **environment** the app runs in. Nothing in the skill enumerates environmental conditions.
- Observed failure (`moodmaker-mythos-test` three-build comparison, ambiance-player, 2026-07-30/31): the design mock's fixed 1280×800 reference frame silently became a load-bearing assumption. All three builds shipped broken layouts at wide-short window sizes — facto's stage didn't shrink and pushed the entire bottom UI off-screen; fable's add-video button was cut off and its popover squished the layout. None of the three verification processes caught it. The developer did, within seconds of manually resizing.
- **Expected:** the design names the environmental conditions the app will run under and states, in writing, how the design handles each — or that it doesn't.
- **Churn valve, stated explicitly in the Issue:** one sentence per item is enough; "unsupported — out of scope" is an acceptable answer as long as it's written down; the example list (resizing, dark/light mode, zoom, long text, large data, slow network, keyboard-only) is illustrative, not a checklist to satisfy.
- **Downstream payoff:** because the handling is declared in the design artifact, `facto:review-loop-design-impl` gains something concrete to verify — viewport testing happens without any viewport being hard-coded into a skill, and the same mechanism covers dark mode, zoom, and the rest.
- OKR tie: `ui-ux-design` — "UI output is intuitive, appealing, and **functionally correct on the user's tasks**". The worst user-facing bug in the flagship build was in this category.

## Terminology

The Issue says "environmental conditions" with "dispositions". This plan uses **environmental edge cases**, and **handling** for the per-item answer ("unsupported — out of scope" is a valid handling). Decided with the developer in planning.

Known mild collision: `facto:ref-design-system` already uses "edge-cases" for *states* ("default/loaded, loading, empty, error, and edge-cases"). That is a different axis (a state the view can be in, vs. a condition the environment imposes). Accepted as-is; rename later if it causes confusion in practice.

## Key Decisions

| Decision | Options Considered | Chosen | Rationale |
|---|---|---|---|
| Where the requirement lands in `plan-design` (the Issue's open question) | (a) Phase 3 drafting only; (b) Phase 3 + Phase 4 reviewer charter; (c) a new dedicated phase | **(b)** | Phase 3 already emits inventories (view, flow) — a third fits the established shape and is pre-visual, so it constrains what Phase 5 draws. Phase 4's reviewer already attacks Phase 3's output; its charter *names* the inventories it reviews, so a new inventory that isn't named there falls outside its stated scope. (c) adds a phase for what is one list. |
| Does the mock draw anything for these edge cases? | (a) prose only; (b) a duplicable band, used only where the handling materially changes the layout; (c) a mandatory band covering every enumerated edge case | **(b)** | The failure was not that nobody thought about resizing — it's that the mock offered exactly one 1280×800 frame, so that was the only thing anyone could build or verify against. `review-loop-design-impl`'s whole comparison phase is screenshot-vs-screenshot; prose alone gives it nothing to compare. (c) is the churn explosion the Issue's valve exists to prevent. |
| Extend `facto:review-loop-design-impl` to verify the handling? | (a) no change; (b) add clauses to Phases A1 / A3 / A4 | **(a)** | Verified against the current skill text: Phase A1 already enumerates from "`design-mock.html` (its labeled frames/bands)", so a new band is picked up generically; Phase A3 already captures "at a viewport matching the corresponding mock frame", so a narrow- or short-viewport frame is already handled. Adding clauses would restate what the design artifact already says — the reviewer executes the design well and should use its own judgment. Decision 2's band is what makes the downstream verification work, at zero duplication. |
| Do the evergreen docs (`ref-design-system`, view specs, `setup-design`) learn about edge cases? | (a) out of scope; (b) add a fourth axis alongside Surface / View / State with per-edge-case harnesses | **(a)** | (b) multiplies harness count per view (states × edge cases) and pulls in `setup-design`. The observed failure happened on the per-task path; prove the mechanism there first. Deferred, not dropped. |
| Test strategy | (a) grep-level structural markers in `template-task-spec.test.sh` for the new band, per the task-#45 precedent; (b) no new tests | **(b)** | Developer's call. A grep asserting a sentence exists in a template is not evidence an agent does anything with it, and the behavioral criteria here are all `manual-described` regardless. The existing suite still must pass unchanged. |

**Out of scope (agreed):** `facto:review-loop-design-impl`, `facto:ref-design-system`, `template-evergreen-view-spec.html`, `facto:setup-design`, and any new or modified test cases.

## Notable Technical Choices

- **No new libraries, services, or APIs.** Everything is prose and HTML/CSS inside a self-contained, project-agnostic template.
- **`--frame-height` on `.browser-page`** — Step 1 adds one CSS variable. Today `.browser` width is variable-driven (`width: var(--frame-width, 720px)`) but `.browser-page` height is a hard `min-height: 440px`. A **wide-short viewport is therefore not expressible in the template at all** — the exact failure case from the Issue could not be drawn. This mirrors the `.connector-label` fix in task #45, where the expected behavior was structurally unbuildable before the CSS change.
- **Band placement and renumbering** — the new band is inserted after BAND 2 (per-screen states), because it is the other cross-cutting per-screen variation band. Bands 3/4/5 shift to 4/5/6. The existing test suite pins header-comment *phrases* (`once per flow`, `belongs in that flow's band`, …), not band numbers, so renumbering does not touch it.

---

## Commits

1. `feat: add an environmental edge cases band to the design-mock template` — makes a short viewport expressible, and gives edge-case frames a designated home in the canvas.
2. `docs: document environmental edge case bands in facto:ref-design-mock` — teaches the mechanics skill how to fill the new band, and that the caller supplies the edge-case list.
3. `feat: enumerate environmental edge cases in facto:plan-design` — adds the inventory to Phase 3, names it in Phase 4's reviewer charter, passes it to the mock in Phase 5, and reports it in Phase 6.

---

## Steps

### Step 1: Add an environmental edge cases band to the design-mock template

**Goal:** A short or narrow viewport is expressible in the template, and a filler drawing a mock has a designated, self-documenting band for the environmental edge cases whose handling changes the layout — so the single reference frame stops being the only thing anyone can build or verify against.

**Changes:**

`plugins/facto/skills/ref-design-mock/template-task-spec.html`

- **`.browser-page` rule (~line 555).** Change `min-height: 440px` to `min-height: var(--frame-height, 440px)`. Backward-compatible: every existing frame that sets no variable renders identically. Add a short comment alongside the existing `--frame-width` comment on `.browser` (~lines 540–545) noting that height is variable-driven the same way, so a short viewport can be drawn.
- **New band, inserted immediately after `</div><!-- /band 2 per-screen states -->` (~line 806) and before the `BAND 3 — COMPONENTS IN ISOLATION` header comment.** Follow the existing band shape exactly: an `<!-- ═══ ... ═══ -->` header comment, then `<div class="band">` → `.band-header` (`.band-label` + `.band-sublabel`) → `.band-frames` → frames → `</div><!-- /band 3 environmental edge cases -->`.

  Header comment content (this is the load-bearing part — it is what a filler reads at the point of filling):
  - What the band is for: one frame per environmental edge case whose handling **materially changes the layout**.
  - What does *not* get a frame: an edge case whose handling is "no visual change" or "unsupported — out of scope" is recorded in the design doc only. A frame here is not a substitute for writing the handling down.
  - **Remove the entire band** if no edge case changes the layout. It is not a band every mock must carry.
  - The frame is the variable: for a size edge case, set `--frame-width` and/or `--frame-height` on the frame to the edge-case size rather than redeclaring the class — the same rule the `.browser` comment already states.
  - Not every edge case is a size. Theme, text scale, and content volume are drawn at the reference size with the condition applied.

  Band header:
  ```html
  <span class="band-label">Environmental Edge Cases</span>
  <span class="band-sublabel">Conditions whose handling changes the layout — see the design doc for the full list</span>
  ```

  Two stub frames, so the band teaches both shapes rather than implying every edge case is a viewport:
  1. **A size edge case** — a `.browser` frame with both variables set inline, e.g. `<div class="browser" style="--frame-width:900px;--frame-height:420px">`, `.browser-page` inside, `frame-title` `<!-- TODO: e.g. Narrow / short viewport — 900×420 -->`, and a `.design-slot` stub reading `Layout at this size`. This is the frame that would have caught the reported bug.
  2. **A non-size edge case** — a `.phone.android` frame reusing the band-2 frame markup verbatim (status bar, `screen-body`, `bottom-indicator`) but with `class="phone-screen t-dark"`, `frame-title` `<!-- TODO: e.g. Dark mode -->`, and a `.design-slot` stub reading `Same layout, condition applied`.

  Close with a `<!-- TODO: add one frame per additional environmental edge case whose handling changes the layout; remove this band entirely if none do -->` comment, matching how the other bands close.
- **Renumber the following bands** in their header comments and closing comments: `BAND 3 — COMPONENTS IN ISOLATION` → `BAND 4`, `BAND 4 — BEFORE / AFTER` → `BAND 5`, `BAND 5 — TOKEN REFERENCE` → `BAND 6`; and `<!-- /band 3 components -->` → `/band 4 components`, `<!-- /band 4 before/after -->` → `/band 5 before/after`, and the token band's closing comment likewise. Header comment prose inside those bands is otherwise untouched — in particular, the components band's "belongs in that flow's band" sentence must survive verbatim (test case 8 pins it).
- **Top-of-file comment (lines 1–37).** Two edits:
  - Item 3's band list — `(cover, then one flow band per flow, then states, components, before/after, tokens)` becomes `(cover, then one flow band per flow, then states, environmental edge cases, components, before/after, tokens)`.
  - The LOAD-BEARING note currently reads "tests/template-task-spec.test.sh pins the BAND 1 and BAND 3 header-comment wording". After renumbering, "BAND 3" would point at the wrong band. Replace the numbers with the band names — "pins the flow band's and the components band's header-comment wording" — so the note stops being position-dependent and cannot go stale on the next insertion.

**Validation:**
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines. All 8 cases of the template suite still pass; this change adds no cases and must break none. Case 8 (`belongs in that flow's band`) and case 5 (`once per flow`) are the ones renumbering could plausibly disturb.
- [ ] Serve and inspect per `/facto:ref-design-mock` ("How to serve and inspect the file"): `python3 -m http.server 8765` from `plugins/facto/skills/ref-design-mock/`, Playwright to `http://localhost:8765/template-task-spec.html`, screenshot after the 250 ms `fit()` fires. Expected: the new band appears between per-screen states and components, with its header and two frames; the 900×420 browser frame renders visibly wider and shorter than the default browser frame in the Appendix band.
- [ ] Confirm the `.canvas-board` horizontal-row invariant still holds — frames within every band lay out in a row, the board is not fit to near-0%, and no band has collapsed into a column.
- [ ] Confirm every pre-existing frame is unchanged: the Appendix band's `.browser` (which sets no `--frame-height`) still renders at its previous height, proving the `min-height` change is backward-compatible.
- [ ] `grep -n 'BAND [0-9]' plugins/facto/skills/ref-design-mock/template-task-spec.html` — band numbers run 1..6 with no duplicates or gaps.

**Commit message:**
```
feat: add an environmental edge cases band to the design-mock template

Context:
A mock could only ever show one reference frame size, so that frame silently
became a load-bearing assumption and wide-short window layouts shipped broken
(issue #93). .browser-page's height was a hard min-height, so a short viewport
was not expressible in the template at all; it is now driven by --frame-height
the same way width is driven by --frame-width. Adds a band for the
environmental edge cases whose handling changes the layout, with one size stub
and one theme stub so the band does not read as viewports-only. Bands after it
renumber; the LOAD-BEARING test note now names bands instead of numbering them.

Verification:
Automated:
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
Manual:
  1. python3 -m http.server 8765 from plugins/facto/skills/ref-design-mock/
  2. Open http://localhost:8765/template-task-spec.html, wait ~1s for fit()
  3. New band sits between per-screen states and components, two frames shown
  4. The 900x420 browser frame is visibly wider and shorter than the Appendix
     browser frame, which is itself unchanged
  5. Frames still lay out horizontally within every band
```

---

### Step 2: Document environmental edge case bands in `facto:ref-design-mock`

**Goal:** The mechanics reference tells a caller how to fill the new band and states that the edge-case list is caller-supplied — so `plan-design` Phase 5 has a documented contract to call, rather than relying on the template's inline comments alone.

**Changes:**

`plugins/facto/skills/ref-design-mock/SKILL.md`

- Under **"How to fill in the frames and bands"**, add a subsection after the existing `### Flow bands` (~line 61), titled `### Environmental edge case bands`. Keep it to the same weight as `Flow bands` — a short paragraph, not a section. Content:
  - The calling skill supplies the list of environmental edge cases, the same way it supplies the flow list and `<dest-dir>` — treat the list as given. (Mirrors the existing sentence in `Flow bands`; the caller-supplies pattern is already established, so this is one clause, not a restatement of what an edge case is.)
  - Draw a frame only for an edge case whose handling **materially changes the layout**. One whose handling is "no visual change" or "unsupported" is recorded by the caller in its own doc and gets no frame here.
  - For a size edge case, set `--frame-width` / `--frame-height` on the frame to that size — never redeclare the frame class. Cross-reference the existing rule rather than restating it: the "How to match a real running app" section already explains why (the template's inlined frame rules win against a redeclared class).
  - Remove the band entirely if no edge case changes the layout.
- Extend the **Completeness** rule in the three "hold across the whole file" bullets (~line 59). It currently reads: *"every flow the caller supplies gets a band that runs from entry to completion. A flow with no band is a gap, not a simplification."* Add a second sentence in the same register: every environmental edge case whose handling changes the layout gets a frame; an edge case drawn only at the reference size is a gap. Per the skill-writing guidelines, extend the existing rule rather than adding a fourth bullet.
- Note the `--frame-height` variable where `--frame-width` is already documented, in "How to match a real running app (device-accurate)" (~line 89). That paragraph currently names `--frame-width` on a `.browser` as the way to size a web frame; it now needs to name `--frame-height` too, or a device-accurate web mock still can't set its measured viewport height.

**Validation:**
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines (prose-only step; this confirms nothing regressed).
- [ ] Read the new subsection against `facto-dev:ref-skill-writing` guideline 1: it must not restate *what* an environmental edge case is or *how to decide* the handling — that is `plan-design`'s content. This section covers only the mechanics of drawing one.
- [ ] Confirm the file still reads as a reference, not a procedure: the new subsection sits under a "How to …" header and introduces no ordering dependency.
- [ ] Confirm the `Completeness` bullet still reads as one rule, not two stacked rules.

**Commit message:**
```
docs: document environmental edge case bands in facto:ref-design-mock

Context:
The template now carries an environmental edge cases band, but the mechanics
reference described bands generically, leaving the fill rules to the template's
inline comments alone. Adds an edge-case band subsection (caller supplies the
list; a frame only where the handling changes the layout; size set via
--frame-width/--frame-height; remove the band if nothing changes) and extends
the existing Completeness rule to cover it. Also names --frame-height alongside
--frame-width in the device-accurate section. Part of issue #93.
```

---

### Step 3: Enumerate environmental edge cases in `facto:plan-design`

**Goal:** Every `plan-design` run produces a written environmental edge case inventory with one stated handling per item, the adversarial reviewer's charter covers it, and the mock draws the ones that change the layout — so the reference frame's assumptions are explicit instead of silent.

**Changes:**

`plugins/facto/skills/plan-design/SKILL.md`

- **Phase 3 scope sentence (line 81).** It currently opens *"Focus ONLY on the high-level user experience flow and UX navigation between screens."* — which directly contradicts the new item. Replace it (guideline 3: replace, don't accumulate a prohibition) so the phase's scope is the high-level flow, navigation, **and the environmental edge cases the design must hold up under**, while the existing exclusions stay intact: still no per-screen detail of how a screen works or looks, still no technical or engineering detail, still tuned to the feature's own complexity.
- **Phase 3 numbered list (lines 84–85).** Add item 3 after the flow inventory:

  > **Environmental edge case inventory** — List the environmental conditions this feature will run under and state how the design handles each — or state explicitly that it doesn't. Examples where relevant: window resizing and viewport sizes, dark/light mode, browser zoom, unusually long text or large data volumes, slow or missing network, keyboard-only use. Those examples are illustrative, not a checklist to satisfy — cover what actually applies to this surface and this feature. One sentence per item is enough, and "unsupported — out of scope" is an acceptable handling as long as it's written down. Mark which entries change the layout; those are the ones the mock draws in Phase 5.

  The final clause is what makes the inventory actionable downstream — without it, Phase 5 has no way to tell which entries need a frame.
- **Phase 3 decisions paragraph (line 87).** It currently constrains the "non-obvious decisions" list to *"decisions specific to the scope of navigation and information hierarchy"*. Widen it to include environmental-handling decisions (e.g. choosing to reflow versus scroll at a narrow width, or declaring a condition unsupported), so a real judgment call made here isn't excluded from the decision log by the phase's own filter.
- **Phase 4 reviewer charter (line 92).** The charter names the artifacts under review twice — *"an adversarial review of the flow inventory, flow map, and view inventory you created in Phase 3"* and *"find any possible flaw, gap, inefficiency, or non-obvious edge case in the flow inventory, flow map, and view inventory"*. Add the environmental edge case inventory to both enumerations. That is the whole edit: a reviewer that reviews a design well already knows an unhandled condition is a gap — what it cannot know is that a third inventory exists and is in scope, because the charter is an explicit list. Add no rules about *how* to review it.
- **Phase 5 (line 101).** The phase currently passes `$TASK_DIR` and "the flow inventory from Phase 3 as the list of flows" to the mechanics. Add the environmental edge case inventory as the list of edge cases, so `ref-design-mock`'s caller-supplies contract (Step 2) is actually satisfied.
- **Phase 5 end-of-phase check (line 103).** It currently confirms every flow inventory entry is covered end to end. Extend the same sentence to also confirm every edge-case entry marked as changing the layout has a frame — and, if none are so marked, that the band was removed rather than left as stubs. Keep it as one check, in the existing register.
- **Phase 6 summary item 3 (line 114).** It currently reports the flow inventory so the developer can spot a missing workflow without opening the mock. Extend it to report the environmental edge case inventory and each item's handling, for the same reason — this is the developer's one chance to say "you marked resizing out of scope and it isn't".

**Validation:**
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines.
- [ ] Read the whole of Phase 3 top to bottom and confirm the opening scope sentence and the new item 3 do not contradict each other.
- [ ] Confirm no instruction was added as a prohibition alongside the instruction it replaces (guideline 3) — the old "Focus ONLY on…" sentence is gone, not negated.
- [ ] Confirm the Phase 4 edit adds only the inventory's name to two existing enumerations, and adds no review rules.
- [ ] Confirm `plan-design` does not restate `ref-design-mock`'s band-filling mechanics (guideline 1) — it supplies the list and checks coverage; the drawing rules live in the mechanics reference.
- [ ] Manual end-to-end (`manual-described` — this is the only check that exercises actual agent behavior):
  1. `fi-task-test.sh` from this worktree to point the global install here.
  2. In a scratch repo with a web-surface PRD, run `/facto:plan-design`.
  3. `design-decisions.html` has an environmental edge case inventory: each entry one sentence, each with a stated handling, at least one marked as changing the layout or explicitly "unsupported — out of scope".
  4. The Phase 4 reviewer's feedback references the edge case inventory at least once.
  5. `design-mock.html` has an Environmental Edge Cases band with a frame per layout-changing entry — or no such band, if none change the layout.
  6. The Phase 6 summary lists the inventory and each handling.
  7. Re-run in a scratch repo with a **backend-only or trivially simple** PRD and confirm the churn valve holds: a short list or an explicit "nothing environmental applies", not a padded seven-item table.
  8. `fi-task-test.sh` from the main checkout to restore.

**Commit message:**
```
feat: enumerate environmental edge cases in facto:plan-design

Context:
The skill covered views, flows, and application states but never asked what
environment the app runs in, so the mock's fixed reference frame became a
silent assumption and wide-short layouts shipped broken (issue #93). Phase 3
now emits an environmental edge case inventory — one sentence of handling per
item, "unsupported - out of scope" allowed, layout-changing entries marked;
Phase 4's reviewer charter covers it; Phase 5 passes it to the mock and checks
the layout-changing entries were drawn; Phase 6 reports it to the developer.

Verification:
Automated:
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
Manual:
  1. fi-task-test.sh from this worktree to point the global install here
  2. In a scratch repo with a web-surface PRD, run /facto:plan-design
  3. design-decisions.html has an environmental edge case inventory, one
     sentence of handling per entry, layout-changing entries marked
  4. The Phase 4 reviewer references that inventory in its feedback
  5. design-mock.html has an Environmental Edge Cases band with a frame per
     layout-changing entry, or no band if none change the layout
  6. Re-run against a trivial PRD: the list stays short, not padded
  7. fi-task-test.sh from the main checkout to restore
```

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Claude Code skill-prompt authoring (SKILL.md phase prose that steers agent behavior) | medium | The design doc contains an environmental edge case inventory with one stated handling per item | manual-described (Step 3, manual check 3) |
| Claude Code skill-prompt authoring | medium | The churn valve holds: one sentence per item, "unsupported — out of scope" accepted, examples treated as illustrative rather than as a checklist | manual-described (Step 3, manual check 7) |
| Adversarial-review subagent charter design | medium | Phase 4's reviewer treats the edge case inventory as in scope | manual-described (Step 3, manual check 4) |
| Self-contained HTML/CSS mock template (pan/zoom canvas, device-frame kit, bands) | high | The mock no longer makes a single fixed reference frame silently load-bearing | manual-described (Step 1 serve-and-inspect; Step 3, manual check 5) |
| Zero-dependency bash structural tests (grep/awk marker pinning) | high | The existing template invariants (per-flow bands, connector labels, project-agnostic tokens) survive this change | automated (`template-task-spec.test.sh`, all 8 cases) |
| Responsive / adaptive UI design practice (viewport ranges, reflow, `prefers-color-scheme`, browser zoom, keyboard-only) | high | The edge cases an agent enumerates for a given project are the *right* ones, and its handlings are good design | **blocked-no-tooling** |
| Playwright-driven multi-condition capture in `review-loop-design-impl` | medium | Declared handlings are actually verified against the running app, with no viewport hard-coded into any skill | manual-described (out of scope this task — relies on the unchanged Phase A1/A3 behavior; see Risk 4) |

## Risks

1. **`blocked-no-tooling`: the quality of the enumeration cannot be verified.** Whether the edge cases an agent lists are the right ones for a given project, and whether its handlings are good design, is a judgment call Facto has no tooling to check. This change guarantees the question gets asked and answered *in writing*; it does not guarantee a good answer. The developer reading the Phase 6 summary is the only real check, which is why Step 3 extends that summary.
2. **No automated behavioral test exists for skill prose.** This repo has no harness that runs a skill and asserts on its output, and by decision this task adds none. Every criterion about agent behavior is `manual-described` via `fi-task-test.sh` plus a scratch-repo run. A future regression in Phase 3's or Phase 4's prose would be caught only by a human noticing a thin design doc.
3. **Churn is real, and only observable after the fact.** An enumeration instruction that lands badly makes every `plan-design` run longer and every design doc noisier for no gain. The one-sentence / "unsupported is fine" / examples-are-illustrative valve is the mitigation; Step 3's manual check 7 (a trivial PRD) is the closest thing to an up-front test. Watch the first few real runs and file an observation if the lists come back padded.
4. **The downstream payoff is inferred, not demonstrated.** The plan asserts that `review-loop-design-impl` picks up the new band with no edit, based on reading its Phase A1 ("from `design-mock.html` — its labeled frames/bands") and Phase A3 ("at a viewport matching the corresponding mock frame"). That is a reading of the prose, not an observed run. If a real run shows the reviewer skipping edge-case frames, the fix is a clause in A1 — file it as a follow-up rather than pre-emptively adding one now.
5. **Vocabulary collision with `ref-design-system`.** "edge-cases" there means a *state* a view can be in; here it means an environmental condition. Two different axes, one word. Low impact, but if a `plan-design` run starts conflating them, rename.
6. **Band renumbering touches four bands to add one.** Mechanical, and the test suite pins phrases rather than numbers, but it widens Step 1's diff and creates one more place a stale band number can hide. The top-of-file LOAD-BEARING note is being de-numbered in the same step specifically to stop that recurring.

---

## Test Plan

- [ ] All project tests pass: `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines, every suite prints `ALL PASS`.
- [ ] Linter: none in this repo.
- [ ] Type checker: none in this repo.
- [ ] Build: none in this repo.
- [ ] `grep -n 'BAND [0-9]' plugins/facto/skills/ref-design-mock/template-task-spec.html` — band numbers run 1..6, no duplicates, no gaps; closing `<!-- /band N ... -->` comments agree with their headers.
- [ ] Manual verification:
  - [ ] Serve `template-task-spec.html` over HTTP and screenshot after `fit()`: the Environmental Edge Cases band renders between per-screen states and components, with a wide-short browser frame and a dark-theme phone frame; all other bands are visually unchanged; frames still lay out horizontally.
  - [ ] `fi-task-test.sh` from this worktree; in a scratch repo with a web-surface PRD, run `/facto:plan-design` end to end.
  - [ ] `design-decisions.html` carries the environmental edge case inventory: one sentence of handling per entry, layout-changing entries marked, "unsupported — out of scope" used where it applies.
  - [ ] The Phase 4 adversarial reviewer references the edge case inventory in at least one round of feedback.
  - [ ] `design-mock.html` has an Environmental Edge Cases band with one frame per layout-changing entry — or no such band at all if none change the layout (not a band left full of stubs).
  - [ ] The Phase 6 developer summary lists the inventory and each item's handling.
  - [ ] Churn check: re-run against a trivial or backend-only PRD; the inventory stays short or is explicitly "nothing environmental applies", and the mock has no edge-case band.
  - [ ] `fi-task-test.sh` from the main checkout to restore the install symlinks.
