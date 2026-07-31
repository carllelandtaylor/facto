# Implementation Plan: Design mocks render every flow end-to-end

**Requirements and specs:** [Issue #45 — "BUG: design mocks render flows as isolated components, not end-to-end step-by-step screen sequences"](https://github.com/carllelandtaylor/facto/issues/45). No PRD or design docs exist for this task; the Issue body (What's happening / Expected Result / Root causes) is the requirements input.
**Created:** 2026-07-30

---

## Requirements Summary

- A design mock currently shows only **one** flow end-to-end — the happy path in the template's single "Flow / Overview" band. Every other user workflow appears only as isolated component frames.
- The observed failure: the add-video popover was drawn as a bare frame in "Components in Isolation" — no surrounding screen, no step ordering, no sequence showing the screen before the click, with the popover open, with the URL pasted, and after the add.
- **Expected:** every user workflow named in the PRD is viewable end-to-end — one band per flow, each step a full-screen frame showing the entire screen at that step, with labeled connectors naming the triggering action. A reader walks any flow entry→completion without assembling it mentally.
- Root cause 1 (template): `template-task-spec.html` hardcodes exactly one flow band, sublabeled "happy path". Flows are structurally singular in the canonical band list, so extra workflows have no designated home.
- Root cause 2 (skill): `plan-design` Phase 5 delegates all content decisions to the designer with no completeness requirement tying mock bands back to the PRD's enumerated user workflows.
- Root cause 3 (template): the components band invites drawing overlays "no device chrome", which satisfies the letter of covering a popover while dropping screen context and step ordering.
- Found during analysis, not in the Issue: the connector's trigger label is written as an **HTML comment** (`template-task-spec.html:642-644`), so nothing renders but a bare arrow. "Labeled connectors" is not merely under-instructed — it is structurally unsupported by the template.
- Downstream impact: `plan-implementation` / `implement` inherit the gap and invent undrawn steps at build time.
- OKR tie: `ui-ux-design` KR "all screens + states viewable side-by-side, navigable".

## Key Decisions

| Decision | Options Considered | Chosen | Rationale |
|---|---|---|---|
| Source of the flow list | (a) `plan-design` Phase 3 emits a numbered **Flow inventory**, Phase 5 renders one band per entry; (b) bands tie directly to the PRD's "User Workflows" headings | (a) | Structured artifact between phases (DEVELOPMENT.md principle 3). Works when there is no PRD, and when one PRD workflow maps to several view sequences. Phase 3 already produces a flow map — this makes it enumerable and gives Phase 5 something to check against. |
| Template shape for N flows | (a) rename band 1 to "Flow — `<flow name>`" and mark it duplicable, keeping one worked example; (b) ship two flow bands as a live demonstration | (a) | ~70 lines of near-duplicate scaffolding in an already 1251-line file buys nothing; the per-screen states band already establishes "repeat this band per screen" with a single instance. |
| Connector trigger labels | (a) make `.connector` a flex column with a rendered `.connector-label` caption; (b) leave CSS alone, put the trigger in the next frame's title | (a) | (b) conflates "what I did" with "where I am" and reads worse. The label is currently an HTML comment that renders nothing — the expected behavior is unbuildable without the CSS change. |
| Guarding against flow-band explosion | (a) step-granularity rule, no cap; (b) hard cap on flows; (c) allow cross-references ("see step 2 of Flow A") | (a) | (b) and (c) reintroduce exactly the mental assembly the Issue is about. Instead: a step exists where the screen visibly changes; consecutive identical-looking states collapse into one. Every flow still runs entry→completion. |
| Automated regression test for the template | (a) add a homemade bash structure test under `plugins/facto/skills/ref-design-mock/tests/`; (b) rely on review | (a) | Nothing today stops a future edit from silently collapsing the per-flow scaffolding back to one band — which is precisely this Issue. Costs widening the DEVELOPMENT.md §4.2 run-all glob to pick up skill tests. |

**Out of scope (agreed):** the evergreen view-spec template (`ref-design-system/template-evergreen-view-spec.html`) and `facto:setup-design` — those are per-*view* specs with a states band, not flow storyboards. `facto:review-loop-design-impl` reads bands generically and needs no change.

## Notable Technical Choices

- **Homemade bash structure test** — the repo's existing convention (DEVELOPMENT.md §4.2: three self-contained `*.test.sh` files, no framework, `PASS`/`FAIL` per case, non-zero exit on failure). Reused rather than introducing a test framework or an HTML parser: the assertions are grep-level structural invariants on a static template, and zero-dependency bash runs in any checkout.
- **New test location `plugins/facto/skills/<skill>/tests/`** — the existing suites all live under `plugins/*/bin/tests/`, which is for shell scripts. A template test does not belong there. This adds a second tests root, so the DEVELOPMENT.md run-all glob widens from `plugins/*/bin/tests/*.test.sh` to cover both.
- **No new libraries, services, or APIs.** Everything is prose, HTML/CSS in a self-contained template, and bash.

---

## Commits

1. `fix: render connector trigger labels in the design-mock template` — makes the connector caption a real rendered element instead of an HTML comment, and stands up the template structure test suite.
2. `fix: give every flow its own band in the design-mock template` — converts the singular happy-path flow band into a per-flow duplicable band, and closes the components-band escape hatch for overlays.
3. `docs: document per-flow band mechanics in facto:ref-design-mock` — teaches the mechanics skill how to fill in one band per flow.
4. `docs: require an end-to-end band per flow in facto:plan-design` — adds the flow inventory to Phase 3, the completeness check to Phase 4's review, and the mock self-check to Phase 5.

---

## Steps

### Step 1: Render connector trigger labels

**Goal:** A connector between two flow frames can display the action that triggers the transition, and a bash suite exists that fails if that capability is removed.

**Changes:**

- `plugins/facto/skills/ref-design-mock/template-task-spec.html`
  - `.connector` rule (lines 286-295): add `flex-direction: column;` and `gap: 0.25rem;` to the existing flex box. `align-items:center`, `align-self:center`, `margin-top:2rem` and `flex-shrink:0` all stay — the `margin-top` still visually centers the connector against the frame title plus device chrome.
  - Add a `.connector-label` rule immediately after `.connector`: small caption type (`font-size: 0.7rem`), muted color matching the band sublabel (`#888`), `white-space: nowrap`, `max-width` unset. Comment it as the rendered trigger action.
  - Flow-band connector markup (lines 640-644): replace the comment-only label with a real element —
    ```html
    <!-- Connector: the action that moves the user from the previous step to the next. -->
    <div class="connector">
      &#x2192;
      <!-- TODO: replace with the triggering action, e.g. "Tap 'Add video'" -->
      <span class="connector-label">Trigger action</span>
    </div>
    ```
  - Before/after band connector (line 868) stays `<div class="connector">&#x21E8;</div>` with no caption — with column direction and a single child it renders identically to today.
- `plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` (new)
  - Follow the shape of `plugins/facto/bin/tests/task-start.test.sh`: `set -u`, a `pass`/`fail` counter pair, one function per case printing `PASS: <case>` / `FAIL: <case>`, non-zero exit if any case failed. Self-contained and safe to run from anywhere — it reads the template by path relative to the script's own location, creates nothing, and leaves nothing behind.
  - Cases in this step:
    1. `.connector-label` is defined in the `<style>` block.
    2. `.connector` sets `flex-direction: column`.
    3. At least one `<span class="connector-label">` exists in the board markup.
    4. The template has no product token values baked in — reassert the existing project-agnostic invariant by checking the `:root` and `.t-dark` blocks still contain their placeholder markers *and* a sample of their neutral default values (guards the warning at lines 29-32 that this suite now sits next to). The markers alone are group-header comments, so they survive a brand palette pasted in underneath them; pinning values is what catches that.
- `DEVELOPMENT.md` §4.2
  - Add a row to the suite table: `plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` | "design-mock task-spec template structure — per-flow bands, connector labels, project-agnostic tokens".
  - Widen the run-all snippet so both tests roots are picked up:
    ```bash
    for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
    ```
  - Adjust the surrounding prose that says "three self-contained `*.test.sh` files" to match the new count.

**Validation:**
- [ ] `bash plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` — every case prints `PASS`, exit 0.
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines. Confirms the widened glob actually matches the new suite and does not break the existing three.
- [ ] Serve and inspect per `/facto:ref-design-mock` ("How to serve and inspect the file"): `python3 -m http.server` from `plugins/facto/skills/ref-design-mock/`, Playwright to `template-task-spec.html`, screenshot after the 250 ms `fit()` fires. Expected: the flow band shows arrow-over-caption between the two screens; the caption is legible; frames still lay out **horizontally** (the `.canvas-board` `flex-wrap:nowrap` invariant) and the board is not fit to near-0%.
- [ ] Confirm the before/after band's captionless connector still renders as a bare arrow at the same vertical position as before.

**Commit message:**
```
fix: render connector trigger labels in the design-mock template

Context:
The design-mock template wrote each connector's trigger action as an HTML
comment, so a mock could only ever show a bare arrow between flow steps —
"labeled connectors" was unbuildable as the template stood. Makes .connector
a flex column with a rendered .connector-label caption. Also stands up a
homemade bash structure test for the template, following the existing
plugins/*/bin/tests convention, so this capability cannot be silently removed.

Verification:
Automated:
  bash plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
Manual:
  1. python3 -m http.server 8765 from plugins/facto/skills/ref-design-mock/
  2. Open http://localhost:8765/template-task-spec.html, wait ~1s for fit()
  3. Flow band shows an arrow with a legible caption beneath it
  4. Frames still lay out horizontally; before/after arrow unchanged
```

---

### Step 2: Give every flow its own band

**Goal:** The template offers a flow band that is explicitly duplicated once per flow, with the rules for full-screen steps and overlay steps stated where the filler reads them — and the components band no longer invites overlays to be drawn there instead.

**Changes:**

- `plugins/facto/skills/ref-design-mock/template-task-spec.html`
  - **Band 1 header comment** (lines 604-608): replace the "Shows the happy-path journey from entry to goal" framing. New comment states:
    - Duplicate this entire band once per flow the caller supplies — there is no primary or happy-path flow; every flow gets its own band.
    - Every step is a **full-screen frame** showing the whole screen at that moment, not a cropped component.
    - An overlay step (popover, dialog, sheet, menu) is drawn as the full screen **with the overlay over it** — never as a bare frame.
    - Step granularity: a step exists where the screen visibly changes. Consecutive states that look identical collapse into one step; every flow still runs from entry to completion with no gaps.
  - **Band label/sublabel** (lines 610-613): `<span class="band-label">Flow — <!-- TODO: flow name --></span>` and `<span class="band-sublabel">Screens in order — <!-- TODO: entry point --> to <!-- TODO: completion --></span>`. Drops the "happy path" wording.
  - **Trailing TODO** (line 670): extend to name both axes of duplication — "add more frame + connector pairs for additional steps in *this* flow; duplicate the whole band for each additional flow".
  - **Frame titles** (lines 618, 648): `<!-- TODO: Step 1 — screen name -->` / `<!-- TODO: Step 2 — screen name -->`, so the frame reads as a step in a sequence rather than a standalone screen.
  - **Top-of-file HOW TO USE comment** (lines 9-12): the canonical band list currently reads "the five canonical bands: flow, states, components, before/after, tokens". Restate it so flow is plural — "one flow band per flow, then states, components, before/after, tokens" — and keep the existing "each band's header comment says what it's for and when to duplicate or remove it" sentence, which now carries real weight for this band.
  - **Band 3 components comment** (lines 788-795): add a scope boundary to the existing grouping rules — this band is for component **variants** (default / disabled / selected …). A popover, dialog, sheet, or menu that appears as part of a flow belongs in that flow's band, drawn over its screen; it goes here only if the point is to show its variants side by side.
  - **Band 3 sublabel** (line 799): keep "no device chrome" (it is accurate for variants) — the boundary is now stated in the header comment where the filler reads it.
- `plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` — add cases:
  5. The band-1 header comment contains the per-flow duplication instruction (grep for the "once per flow" marker phrase).
  6. The band label is the `Flow — <flow name>` form, and no band is framed as the happy path. Band 1 keeps one deliberate mention — "there is no primary or happy-path flow" — so the assertion allows that one and fails on any other, rather than banning the phrase outright.
  7. The band-1 comment states the overlay rule (grep for the overlay marker phrase).
  8. The components band comment states the flow-overlay boundary.

  Pin each assertion to a short, stable marker phrase and note in a comment at the top of the test that these phrases are load-bearing, so a future prose edit either keeps them or updates the test deliberately.

**Validation:**
- [ ] `bash plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` — all eight cases `PASS`, exit 0.
- [ ] The only `happy[ -]path` mention left in `plugins/facto/skills/ref-design-mock/template-task-spec.html` is the band-1 instruction "there is no primary or happy-path flow"; no band is framed as the happy path.
- [ ] Serve and inspect as in Step 1. Expected: the flow band header reads `FLOW — <flow name>`; the band still renders two phone frames with a labeled connector between them; nothing else on the board shifted.
- [ ] Manually duplicate the flow band once in a scratch copy (not committed) and re-serve: two flow bands stack vertically with correct headers and no layout breakage. Delete the scratch copy.

**Commit message:**
```
fix: give every flow its own band in the design-mock template

Context:
The template hardcoded exactly one "Flow / Overview" band described as the
happy path, so additional user workflows had no designated home and drifted
into the components band as isolated popover frames with no screen context or
step order (issue #45). Band 1 is now "Flow — <name>", explicitly duplicated
once per flow, with the full-screen-step and overlay-over-screen rules stated
in its header comment. The components band is scoped to variants only.

Verification:
Automated:
  bash plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh
Manual:
  1. Serve the template over HTTP and open it, wait ~1s for fit()
  2. Band header reads "FLOW — <flow name>", no "happy path" wording
  3. In a scratch copy, duplicate the flow band — two bands stack cleanly
```

---

### Step 3: Document per-flow band mechanics in `facto:ref-design-mock`

**Goal:** The mechanics skill tells a filler how to produce one end-to-end band per flow, so the instruction survives even when the template's inline comments are skimmed.

**Changes:**

- `plugins/facto/skills/ref-design-mock/SKILL.md`, "How to fill in the frames and bands" (lines 47-59):
  - Add a short subsection covering flow bands. It states: the calling skill supplies the list of flows (as it already supplies `<dest-dir>`); each flow gets its own band; each step is a full-screen frame; an overlay step is the full screen with the overlay over it; each connector carries the action that triggers the transition. Keep it to a few sentences — the template's header comments carry the detail, and this file already says "the template documents itself at the point where you fill it".
  - Extend the existing two whole-file rules (Scope, Implementability) with a third: **Completeness** — every flow the caller supplies has a band that runs entry to completion; a flow with no band is a gap, not a simplification.
  - Do **not** describe where the flow list comes from, how it is derived from a PRD, or anything about `plan-design`'s phases — per `facto-dev:ref-skill-writing` guideline 1, the caller's contract is "supplies a list of flows", and how the caller builds that list stays hidden.
  - Per guideline 3, replace the superseded wording rather than negating it — no "don't draw overlays in isolation any more" sentences describing what the skill used to say.
- No template or test change in this step.

**Validation:**
- [ ] `bash plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` — still exit 0 (nothing touched, confirms no accidental edits).
- [ ] Read the diff against `facto-dev:ref-skill-writing`: plain direct language; no restatement of `plan-design` content; superseded instructions replaced, not negated; the reference-skill "How to …" heading convention preserved.
- [ ] Confirm the skill's `description:` frontmatter still ends with the `Reference skill (independent how-tos — use what you need, in any order).` type tag, character-for-character.

**Commit message:**
```
docs: document per-flow band mechanics in facto:ref-design-mock

Context:
The mechanics reference described bands generically, leaving "one band per
flow" to the template's inline comments alone. Adds a flow-band subsection
(caller supplies the flow list; full-screen steps; overlays drawn over their
screen; labeled connectors) and a Completeness rule alongside the existing
Scope and Implementability rules. Part of issue #45.
```

---

### Step 4: Require an end-to-end band per flow in `facto:plan-design`

**Goal:** The design skill enumerates flows as a named artifact, has its reviewer check that enumeration for completeness, and verifies the produced mock covers every entry — so a missing flow is caught before the developer has to ask for rework.

**Changes:**

- `plugins/facto/skills/plan-design/SKILL.md`, **Phase 3** (lines 76-89):
  - Rename output item 2 from "Flow map" to "**Flow inventory and flow map**". The inventory is a numbered list of every distinct user flow the feature involves, each with a name, an entry point, and a completion condition. Source it from the PRD's "User Workflows" section plus any flow the PRD implies but does not name (e.g. an error-recovery or first-run path).
  - State that the flow map (the existing flowchart of views and transitions) covers the same set — every inventory entry is traceable through it.
  - Keep the existing instruction to hold this phase to high-level flow and navigation, no per-screen detail.
- **Phase 4** (lines 91-96): add one item to what the adversarial reviewer is asked to attack — whether the flow inventory is **complete** against the PRD's user workflows, including flows the PRD implies but does not name. Fold it into the existing "find any flaw, gap, inefficiency, or non-obvious edge case" instruction rather than adding a separate paragraph.
- **Phase 5** (lines 98-103):
  - State that the flow inventory from Phase 3 is what gets passed to the mechanics reference as the list of flows (matching the contract Step 3 wrote on the other side of the boundary).
  - Add a self-check before the phase ends: serve and inspect the mock, and confirm it has one end-to-end band per flow-inventory entry, each running entry point to completion. If an entry has no band, add it and re-inspect. Point at `/facto:ref-design-mock` for the serve-and-inspect mechanics rather than restating them.
- **Phase 6** (lines 105-116): the developer summary already covers big decisions and reviewer feedback. Add the flow inventory to what gets summarized — name the flows covered — so the developer can spot a missing workflow from the message without opening the mock.
- No changes to Phase 1, 2, or 7.

**Validation:**
- [ ] `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines.
- [ ] Read the diff against `facto-dev:ref-skill-writing`: Phase 5 references `/facto:ref-design-mock` for mechanics without restating them; no leaked template details (band class names, CSS) in `plan-design`.
- [ ] Confirm the phase list at the top of the file (lines 22-32) still matches the phases — phase names are unchanged by this step, so the `TaskCreate` block needs no edit; verify that is actually true after editing.
- [ ] Confirm the `description:` frontmatter still ends with `Procedure skill (follow the phases in order).`
- [ ] End-to-end run per the Test Plan below.

**Commit message:**
```
docs: require an end-to-end band per flow in facto:plan-design

Context:
Phase 5 delegated all mock content decisions to the designer with no
completeness requirement, so only the primary happy path got an end-to-end
sequence and other workflows appeared as isolated components (issue #45).
Phase 3 now emits a numbered flow inventory, Phase 4's reviewer attacks it for
completeness against the PRD's user workflows, and Phase 5 verifies the mock
has one end-to-end band per entry before the phase ends.

Verification:
Automated:
  for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
Manual:
  1. fi-task-test.sh from this worktree to point the global install here
  2. In a scratch repo with a multi-workflow PRD, run /facto:plan-design
  3. The design doc has a numbered flow inventory
  4. design-mock.html has one end-to-end band per entry, full-screen steps,
     labeled connectors; no flow-step overlay sits in the components band
  5. fi-task-test.sh from the main checkout to restore
```

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Self-contained HTML/CSS canvas templating (flex bands, device frames, pan/zoom) | high | Connectors render a visible label naming the triggering action | automated — test cases 1-3, plus manual render |
| Self-contained HTML/CSS canvas templating | high | The template offers one duplicable band per flow, not a singular happy-path band | automated — test cases 5-7 |
| Claude Code skill-prompt authoring | high | The components band no longer absorbs flow overlays | automated — test case 8 (template side); manual read (skill side) |
| Design information architecture (flow storyboarding) | medium | Every user workflow named in the PRD is viewable end-to-end, one band per flow | **manual-described** — Test Plan E2E run: `/facto:plan-design` against a multi-workflow PRD, then count bands against the flow inventory |
| Agent behavior under revised instructions | medium | Each flow step is a full-screen frame showing the entire screen state | **manual-described** — inspect the produced mock in the E2E run |
| Subjective design readability | medium | A reader can walk any flow from entry to completion without assembling it mentally | **manual-described** — developer judgment on the rendered mock |

## Risks

- **Every behavioral criterion is `manual-described`.** The automated tests pin the template's *structure* only. Nothing in this repo can prove that a future `/facto:plan-design` run actually draws all flows — that is model behavior under revised prompts. The E2E run is a single observation, not a regression gate.
- **No host repo was confirmed.** The Issue names `moodmaker-mythos-test` / `ambiance-player-ui` as where this was observed. This plan assumes that repo is **not** available and the E2E check runs against a throwaway scratch repo with a hand-written multi-workflow PRD. If the real host repo is available, run against it instead — reproducing the original failing case is stronger evidence than a synthetic one.
- **Marker-phrase assertions are brittle by construction.** Test cases 5-8 grep for prose in the template's comments. A future prose rewrite will fail them. This is intentional (the failure forces a deliberate decision) but it will read as a false alarm to whoever hits it — hence the load-bearing note at the top of the test file.
- **Prose changes in Steps 3 and 4 have no automated verification at all.** They are validated by diff review against `facto-dev:ref-skill-writing` and by the E2E run.
- **Flow-band count could grow large** on a PRD with many workflows. The step-granularity rule is the only guard, and it is a prompt-level instruction, not an enforced limit. Watch the first few real mocks for canvas bloat; if it becomes a problem, that is a follow-up Issue, not a change to this plan.

## Test Plan

- [ ] All project tests pass: `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done` — no `FAILED:` lines
- [ ] Linter passes: *no linter in this repo*
- [ ] Type checker passes: *no type checker in this repo*
- [ ] Build succeeds: *no build step in this repo — plugins are skill directories, not compiled artifacts*
- [ ] Manual verification:
  - [ ] Serve `template-task-spec.html` over HTTP and screenshot after `fit()` settles: the flow band renders labeled connectors; frames lay out horizontally; the board is not fit to near-0%; no band is visually broken.
  - [ ] `grep -rniE "happy[ -]path" plugins/facto/skills/ref-design-mock/` returns only the band-1 "there is no primary or happy-path flow" instruction and the test suite's own references to it.
  - [ ] **End-to-end:** `fi-task-test.sh` from this worktree to point the global install at these in-progress skills. In a scratch repo, write a PRD with at least three distinct user workflows (mirroring the Issue's shape: a daily-use path, a create/build path, and a library-growth path with an overlay step). Run `/facto:plan-design`.
    - [ ] `design-decisions.html` contains a numbered flow inventory naming all three workflows.
    - [ ] `design-mock.html` has one band per inventory entry, each labeled `Flow — <name>`.
    - [ ] Each band's steps are full-screen device frames, in order, entry point to completion.
    - [ ] The overlay step is drawn as the full screen with the overlay over it — **not** as a bare frame in the components band.
    - [ ] Each connector shows a legible action label.
    - [ ] The components band contains only component variants.
    - [ ] Phase 6's summary message names the flows covered.
    - [ ] `fi-task-test.sh` from the main checkout to restore the install symlinks.
  - [ ] Re-read the Issue's Expected Result and confirm each clause is satisfied by the produced mock.

## Flags

- [ ] **Confirm the host repo for the E2E check.** The plan assumes a synthetic scratch PRD. If `moodmaker-mythos-test` / `ambiance-player-ui` is available, running against it reproduces the original failing case directly and is materially better evidence.
- [ ] **This repo has no CI.** The new test suite will only ever run when someone runs it by hand. A CI workflow running the four suites on PR would make the regression guard real; that is outside this Issue's scope but worth an Issue of its own.
- [ ] **Prompt changes are unverifiable by test.** Steps 3 and 4 change model instructions; only the one-shot E2E run observes their effect. Per DEVELOPMENT.md §3.2 principle 5, this change should carry a verifiable prediction — proposed: *the next `/facto:plan-design` run on a multi-workflow PRD produces one end-to-end band per workflow with no developer-initiated rework request.* Worth recording as a comment on Issue #45 when the PR goes up.
- [ ] **Evergreen view specs untouched.** `facto:setup-design` and `ref-design-system`'s per-view template still have no flow representation. If a reader expects to follow flows from the evergreen docs too, that is a separate Issue.
