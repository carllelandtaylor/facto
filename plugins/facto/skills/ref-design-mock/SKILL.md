---
name: ref-design-mock
description: "Covers the mechanics of producing a Figma-style design-mock HTML file from this skill's template: how to create a per-feature working copy, fill in its tokens / frames / bands, and serve and inspect it. This skill covers the HOW; the design work itself — deciding what to draw and iterating with the developer — belongs to the skill that calls this one. Invoke with /facto:ref-design-mock. Reference skill (independent how-tos — use what you need, in any order)."
color: purple
---

# Design Mock — Template Toolkit

> **Model:** when run as a subagent, prefer `model: opus`.

How to turn the design-mock template into a filled-in, viewable design file.

**This is a reference, not a procedure.** There's no required order — go to the section for whatever you're trying to do. It covers only the mechanics (copying the template, filling it in, serving and inspecting it). The *design* work — choosing what each screen looks like, and any review/iteration loop with the developer — is owned by the calling skill, not this one. Headers starting with "How to …" describe an action.

## Supporting files

- **Canvas template** — `[facto] claude/skills/ref-design-mock/template-task-spec.html`: a self-contained HTML canvas (inlined pan/zoom CSS+JS, a device-frame kit, the canonical bands, and a `:root` token-placeholder block) for designing a new feature in a task directory. [template-task-spec.html](template-task-spec.html)

## What you're working with

The template is one self-contained HTML file: a pan/zoom canvas of device **frames** grouped into labeled **bands**. You don't edit the template — you copy it per feature and fill the copy in.

The template fixes the *structure* (the bands, the frame kit, the token vocabulary) so every mock reads as the same product. What goes *inside* the frames — the actual screen design — is the caller's decision, not something this skill prescribes.

---

## How to create a working copy

The calling skill supplies the destination directory `<dest-dir>` — treat it as an opaque location; how that directory is chosen is the caller's concern, not this skill's.

1. Copy `[facto] claude/skills/ref-design-mock/template-task-spec.html` → `<dest-dir>/design-mock.html`. (Fixed filename — no date in the name.)
2. Put any fonts or images the design references in `<dest-dir>/assets/`, and reference them relatively (`assets/...`) so they resolve when served from `<dest-dir>`. CDN-hosted webfonts don't need bundling (Facto is online-only).
3. From here on, edit **only the copy**. The Facto template is read-only.

---

## How to fill in the design tokens

The copy's `<style>` has a `:root` token-placeholder block, a set of `.type-*` utility classes, and a `.t-dark` override block. Replace the placeholder values with the product's real tokens from `[product] docs/design/<surface>/design-system.md` — colors, type scale, spacing, radius — and fill in the dark-theme overrides.

Build every frame from these token vars (`var(--color-…)`, `.type-…`) rather than raw hex or arbitrary px. That's what keeps the mock consistent and faithful to what the target platform will actually implement.

If the design system has no structured token section, derive values from its style-guide prose and note which ones you inferred.

---

## How to fill in the frames and bands

The board is a vertical stack of **bands** (rows of **frames**); inside each frame, the dashed **`.design-slot`** is the region you replace with real design — replace its *contents*, never the device chrome.

**The template documents itself at the point where you fill it** — open the copy and follow the inline comments:
- each band's header comment says what it's for and when to duplicate or remove it,
- the top-of-file comment lists which frame type goes with which platform,
- the Appendix band shows every frame type (delete that band when you're done).

Three things to hold across the whole file:
- **Scope** — design only the screens the feature touches, never the whole app.
- **Implementability** — don't use presentation the target platform can't build (e.g. a CSS effect Jetpack Compose can't reproduce); the mock must be buildable as shown.
- **Completeness** — every flow the caller supplies gets a band that runs from entry to completion. A flow with no band is a gap, not a simplification.

### Flow bands

The calling skill supplies the list of flows, the same way it supplies `<dest-dir>` (see "How to create a working copy") — treat the list as given. Give each flow its own band: every step is a full-screen frame, an overlay step is that same full screen with the overlay drawn over it, and each connector between steps carries the action that triggers the transition. The band's header comment in the template has the full detail on step granularity and duplication.

---

## How to serve and inspect the file

`file://` won't work (it blocks bundled assets and breaks the browser tools) — serve over HTTP:

1. `python3 -m http.server <free port>` from `<dest-dir>` (so `assets/` resolves under the server root).
2. Playwright `browser_navigate` to `http://localhost:<port>/design-mock.html`.
3. `browser_take_screenshot` of the canvas; `browser_evaluate` to read the board transform or check layout.
4. Confirm it actually rendered — frames visible, not a blank/error page, not fit to near-0%. Stop the server when done.

The canvas runs a second `fit()` 250 ms after load to catch fonts/images that settle late — take the screenshot after that fires, or the board can look near-invisible.

---

## How to match a real running app (device-accurate)

When the mock must match an app that **already exists** — e.g. `/facto:setup-design` standing up specs from current reality, or `/facto:review-loop-design-impl` checking drift — measure values from the running app rather than estimating them, so the mock matches it rather than approximates it.

**Device profile.** Capture the surface's pixel resolution and density, derive the logical size and device scale factor (dsf), set the frame to that logical size, and adopt **1 CSS px == 1 dp/pt** so measured positions map directly into the mock. This replaces the template's default frame dimensions and its generic status bar.
- Android: `adb shell wm size` (px) and `adb shell wm density` (dpi); `dsf = dpi/160`; `logical = px / dsf`.
- iOS: point size × scale (@2x/@3x); `dsf = scale`.
- Web: CSS px directly; `dsf = 1` (or the device-pixel-ratio you target).

Size the frame by setting its CSS variable to the measured logical viewport — `--screen-width`/`--screen-height` on a `.phone-screen`, `--frame-width` on a `.browser` (e.g. `<div class="browser" style="--frame-width:1280px">`). `.phone-screen`, `.browser`, and `.browser-page` are template-owned class names: set the variable, never redeclare the class in a separate stylesheet — the template's frame rules are inlined after any linked CSS, so a redeclared width silently loses and the frame can clip the page.

**Geometry.** Read element bounds from the live accessibility/DOM tree, not from the screenshot:
- Android `adb shell uiautomator dump` (Compose exposes semantics bounds, in px → ÷ dsf = dp).
- iOS the view/accessibility hierarchy; Web `getBoundingClientRect()`.

**Colors.** Take the surface's tokens from source — `design-system.md` if it has one, otherwise the theme file the code actually uses (e.g. `globals.css`, a platform theme) — and sample the screenshot at known points to confirm. Sampling catches what reading source misses — elevation tints and alpha composites: a 50 %-alpha foreground over a variant surface renders as neither token's hex. When the surface has no token reference at all, the sampled values are the source of truth (the `design-system.md` cross-check is optional when absent).

**Fonts.** Copy the app's actual bundled font files into `assets/` and `@font-face` them. A substitute webfont changes glyph metrics and shifts alignment.

**OS chrome is not the app.** The status bar and gesture/home indicator belong to the platform. Reproduce them approximately and treat them as out of scope when judging fidelity.

---

## How to structure a device-accurate spec: shell + per-state harnesses

Build a device-accurate spec as two layers, so the pixels a human reviews are the exact pixels proven against the app:

- **Per-state harness** — one standalone page per state. Size it to the logical viewport (`html,body{width:<logicalW>px;height:<logicalH>px}`, 1 CSS px = 1 dp/pt) and draw *only the app's own screen content*: the surface's tokens in `:root` (from its design system or theme source, or the sampled values when it has none), the app's bundled fonts via `@font-face`, every element absolutely positioned from the measured geometry above. No OS chrome. This page is both what you screenshot for the diff **and** what the shell embeds, so the two can never drift.
- **Spec shell** — a canvas with a meta-card plus a states band (the caller supplies it). Each state is a device frame whose screen embeds its harness with an `<iframe>`; draw the platform's status bar and home indicator cosmetically on top (`pointer-events:none`) and keep them out of the diff.

The caller fixes the harness filenames, the iframe `src`, and where fonts live; this skill owns the rest.

---

## How to render at device scale and diff against the app

A close-looking mock is not proof. Render the mock at the device's exact pixel resolution and diff it against the live screenshot.

1. **Render at dsf.** Headless Chrome: `google-chrome --headless=new --force-device-scale-factor=<dsf> --window-size=<logicalW>,<logicalH> --virtual-time-budget=4000 --screenshot=mock.png <url>` (or a Playwright context with a matching `deviceScaleFactor`). Screenshot the **bare harness page** for the state — not the spec shell — so the diff covers only the design, then crop to the device resolution. Because the shell embeds that same harness, the reviewed pixels and the proven pixels stay identical.
2. **Diff.** Compare the two same-size PNGs overall and per region/band; PIL `ImageChops.difference` + `histogram()` works with no numpy. Also measure key elements' left and right edges and widths — sub-pixel drift accumulates across a row and is hard to catch by eye.
3. **Iterate** on the mock until the diff is under your bar.

**Acceptance bar:** a designer and engineer looking at both agree they match — no visible structural, color, or type mismatch in the app's own content; the remaining diff is anti-aliasing and OS chrome.

**Record accepted divergences** rather than implying the whole screen matches perfectly: OS chrome; data differences (the mock's item count vs the live database's); and text-rasterization differences between the browser and the native toolkit even with identical fonts.

---

## How to revise the file

The output file is self-contained, so editing it never breaks anything to build. Make changes in place with `Edit` (no need to regenerate from the template), then re-serve to re-inspect.

*(Rules for editing the shared `[facto] template-task-spec.html` itself — keeping it project-agnostic, the load-bearing CSS, the `fit()` timing — live in that file's top-of-file comment, where a maintainer editing it will see them.)*
