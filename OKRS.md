# Facto OKRs

This file lists Facto's current Objectives and Key Results. The `fi-*` skills read it on every invocation to know what success looks like for Facto. Improvements link back to OKRs by slug in their `okrs:` frontmatter field. `fi-think` updates the per-OKR status on its periodic pass; `fi-status` reads them.

OKRs are a structured, measurable subset of Facto's durable mission stated in `DEVELOPMENT.md` §1.2. Key Results are concrete, measurable targets — either ship-goal capabilities or per-PR / per-session outcome surveys.

**Status legend:**
- 🟢 — meeting the goal, with positive evidence.
- 🟡 — partial: some signal, some gaps, unknown, or working but lightly exercised.
- 🔴 — clearly not meeting, or so unmeasured that we cannot claim to be meeting it.
- ❓ — KRs not yet defined for this objective.

Objective-level Status is the lowest (worst) of its KR-level statuses.

**Measuring ship-goal KRs.** Many KRs can't be measured against production usage yet (no shipped projects with real users). For those, the measurement proxy is a two-step procedure: (1) ship the capability into Facto, then (2) after each subsequent use, collect a yes/no developer satisfaction survey. The KR passes once 10 surveys have been collected with ≥8/10 positive responses. Survey-measured KRs are flagged with 📋.

A review cadence (when OKRs themselves are rewritten) is not yet defined.

---

_The software produced by Facto_

## product-direction 🔴

**Description:** Facto's choices serve the user well, solving the right problems in effective ways.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Facto is able to generate product research, including user personas and competitive context. 📋 (satisfaction survey) | 🟡 `c-research` covers competitive context via web research. Formal persona output not supported. |
| Facto is able to generate a product spec for a new feature in an existing project. 📋 (satisfaction survey) | 🟡 `c-product-req` handles this. Not yet survey-validated. |
| Facto is able to generate a product spec for a wholly new product. 📋 (satisfaction survey) | 🟡 `c-new-project-setup-plan` handles this. Not yet survey-validated. |
| Facto is able to store and retrieve product ideas / future projects. | 🔴 No capability today. |
| Facto is able to choose a next feature to work on from the stored set. 📋 (satisfaction survey) | 🔴 No capability today. |

## ui-ux-design 🔴

**Description:** UI output is intuitive, appealing, and functionally correct on the user's tasks.

**Last updated:** 2026-05-28

| Target (KR) | Current status |
|---|---|
| Facto is able to produce a reviewable visual design artifact (multi-screen mockup, all screens + states viewable side-by-side, navigable) from a product spec, before any application code is written. | 🟢 `c-design` + `c-design-mock` produce a Figma-like pan/zoom mock from the product spec, positioned between `/c-product-req` and `/c-impl-plan`. |
| Facto is able to iterate collaboratively with the developer on the design artifact — applying feedback, revising specific screens or states, comparing variants — before any application code is written. | 🟡 `c-design` runs an adversarial-review loop and summarizes decisions for the developer; an explicit developer-feedback / variant-comparison loop on the artifact is not yet specified. |
| Facto's design artifact includes empty / loading / error states alongside the happy-path screens by default, not only on explicit request. | 🟡 `c-design` covers screen "states" generally but does not mandate empty / loading / error states by default. |
| Facto's design artifact meets accessibility basics by default (semantic HTML, ARIA labels, keyboard navigation, color contrast); the artifact is gated on passing these checks before it's considered done. | 🔴 No accessibility checks or gate in `c-design` today. |

## code-correctness 🔴

**Description:** Code works correctly and reliably; it does what it's supposed to do.

**Last updated:** 2026-06-05

| Target (KR) | Current status |
|---|---|
| Facto always creates tests for its changes, and the tests are appropriate to the change. 📋 (measured via per-PR developer yes/no survey) | 🟡 `c-implement` can generate tests but doesn't always. Not yet survey-validated. |
| Facto runs tests, lints, type checks, and other validation checks automatically and independently, iterating on failures until they all pass. | 🟢 `c-review-loop` and `c-ci-make-green` handle this. |
| Facto runs static security checks (dependency audit, SAST, secret scanning) on every change. | 🔴 No capability today. |
| Facto self-reviews its own diff for correctness issues before opening a PR for human review or merging. | 🟢 `c-review-loop` handles this. |
| Facto verifies that the project's CI is configured to run tests and block merge on failure; sets up the CI gate (via a skill or hook) if it isn't already in place. | 🔴 No capability today. |
| Across the most recent 10 Facto-built PRs, ≥8 had no bugs found by the developer that Facto missed — 📋 surveyed both during pre-merge developer review and any post-merge use. (Developer-found bugs are the signal that this objective is not being met.) | 🔴 No survey in place; developer-found bugs not tracked. |

## code-maintainability 🔴

**Description:** Code is clear, idiomatic, and easy for humans and agents to read and maintain.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Across the 10 most recent Facto-built PRs, ≥8 had developer survey responses of "yes" to: the code is easy enough to read and understand. 📋 (per-PR developer survey) | 🔴 No survey in place; not tracked. |
| Facto consistently follows the project's existing coding style, naming conventions, and formatting in new code. 📋 (satisfaction survey) | 🟡 Not enforced or tracked. Not yet survey-validated. |
| Facto matches the project's documented architecture for new features; matches the existing/observed architecture when no documented architecture exists. 📋 (satisfaction survey) | 🟡 `c-arch-decision` can document architectural decisions; matching not enforced or tracked. Not yet survey-validated. |

## reviewability 🔴

**Description:** Humans can easily inspect and understand changes.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Facto produces well-structured PRs: each PR is small enough to review easily; has a clear description covering what changed, why, and how to verify; has descriptive commit messages with logical commit splits; and includes explicit test plan / verification steps. 📋 (satisfaction survey) | 🟡 `c-commit-or-amend` and `c-pr` handle this; PR description quality is variable and PR size is not enforced. Not yet survey-validated. |
| Facto references the relevant issue, ticket, or design doc in every PR. | 🟡 `c-pr` does this when context is provided; not enforced. |
| Facto avoids mixing unrelated changes in a single PR. 📋 (satisfaction survey) | 🟡 `c-impl-plan` scopes changes per plan step; cross-step mixing happens occasionally. Not yet survey-validated. |
| Each PR includes a risk annotation (e.g., high / medium / low) summarizing the change's overall risk profile. | 🔴 No capability today. |
| Each PR's summary surfaces specific files, sections, or lines the reviewer should look at first as a priority. | 🔴 No capability today. |
| Across the 10 most recent Facto-built PRs, ≥8 had developer survey responses of "yes" to: the PR (description + diff) is easy enough to review. 📋 (per-PR developer survey) | 🔴 No survey in place; not tracked. |

---

_How Facto operates_

## independence 🔴

**Description:** Facto makes a lot of progress autonomously without frequent mid-task questions (up-front and end-of-task questions are fine). KRs are framed as end-to-end chunks of work Facto can complete without mid-task developer intervention. Risk tiers (low / medium / high) defined as: *low* = bounded file scope, no new dependencies, no architectural change; *medium* = moderate scope, possibly a small dependency change; *high* = architectural / multi-component / breaking-change-shaped.

**Last updated:** 2026-06-05

| Target (KR) | Current status |
|---|---|
| Facto can independently take an issue from a task tracker (e.g. GitHub Issues, Linear, Jira), debug it, create a fix, and open a PR — with no developer intervention from issue pickup through PR open. | 🟡 `c-bug-fix` handles this when given a GitHub Issue number, running autonomously through PR open and CI monitoring. |
| Facto can independently take a product spec or impl plan and ship a PR for it — with no developer intervention from kick-off through PR open. | 🟡 `c-implement` handles this when invoked; `c-impl-plan` does not interrupt mid-task for decisions, but overall task reliability can still vary. |
| Facto can independently iterate on PR feedback (developer comments or external reviewer comments) through to an updated PR — with no developer intervention from feedback receipt through update pushed. | 🟡 `c-iterate` handles this when invoked; same reliability caveats. |
| Facto can independently review and merge its own *low-risk* changes — no developer review or merge action required. | 🔴 No capability today. |
| Facto can independently review and merge its own *medium-risk* changes. | 🔴 No capability today. |
| Facto can independently review and merge its own *high-risk* changes. | 🔴 No capability today. This is the most aspirational tier; treat as a stretch goal. |

## reliability 🟡

**Description:** Facto runs end-to-end without breaking, stalling, or unexpectedly stopping mid-task; when something goes wrong, it recovers rather than waiting for the developer to nudge it.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Facto saves progress incrementally during a task (commits during work, not at end) so partial work survives a session failure. | 🟢 `c-commit-or-amend` and `c-impl-plan` handle this. |
| Facto surfaces clear error messages with diagnostic info when something fails (what went wrong, what was tried, where the agent stopped). | 🟡 Skills usually report failures; quality and consistency vary. |
| Facto gracefully reports blockers (with a summary of what was tried) rather than silently exiting. | 🟡 `c-pr` and `c-implement` have known silent-exit issues. |
| Facto verifies completion criteria are met before declaring a task done. | 🟡 `c-review-loop` verifies via project commands but skills can still declare done without going through it. |

## throughput 🔴

**Description:** Facto ships a high volume of work per unit time across all in-flight tasks.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Facto is capable of running 8 unrelated tasks in parallel without observed interference. (Parallelism used as a proxy for throughput — not the outcome, but a measurable enabler.) | 🟡 Worktree mechanism (`task-start`/`task-list`/`task-end`) supports this; not yet exercised at 8 concurrent. |
| Facto processes a queue of pending tasks autonomously, picking the next one to work on without explicit developer kickoff. | 🔴 No capability today. |

## single-task-speed 🔴

**Description:** Facto completes individual tasks quickly. Important for critical bug fixes, production-incident fixes, and any time-sensitive single piece of work.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Facto has one or more repeatable benchmark tasks defined that can be used to measure single-task wall-clock speed consistently over time. | 🔴 No benchmark tasks defined today. |

## cost-effective 🔴

**Description:** Runnable at an economic cost.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Total Facto operating cost ≤ $225 / month (subscriptions + per-token / API charges + any supporting infrastructure). | 🟡 Cost not formally tracked; likely within budget on current Claude Code tiers. |
| Facto tracks per-session, per-PR, and/or per-skill token spend so cost is measurable, not invisible. | 🔴 No Facto-side cost tracking today. |

## project-agnostic 🟢

**Description:** Facto is in its own repo and has no knowledge of the projects it builds.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Facto repo contains zero project-specific code or content, and new projects can be onboarded without any Facto-code changes. (Binary — yes or no.) | 🟢 Verified; hook system supports onboarding new projects without Facto-code changes. |

## project-customizable 🟢

**Description:** Projects can customize Facto's behavior via configuration in their own repo.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Common project customizations (test runner, deploy command, secret handling, service lifecycle) are all supported via project-side configuration without Facto-code changes. (Binary per customization — does each one work or not.) | 🟢 All common customizations supported via project-side hooks; no Facto-code changes required. |

## automatically-self-improving 🔴

**Description:** Facto reflects on its own work and improves itself over time.

**Last updated:** 2026-05-22

| Target (KR) | Current status |
|---|---|
| Developer can manually capture failure and success observations and trigger processing into improvement creation. | 🟢 `fi-observe`, `fi-mine-logs`, `fi-mine-web`, and `fi-think` support this today. |
| Facto automatically captures failure and success observations as it runs, without developer kickoff. | 🔴 Requires developer invocation of `fi-observe`, `fi-mine-logs`, or `fi-mine-web`. |
| Facto automatically processes captured observations into improvement ideas (no developer kickoff). | 🔴 `fi-think` requires developer invocation; not scheduled. |
| Facto automatically implements improvement ideas (moving them through the testing → accepted lifecycle without developer kickoff). | 🔴 No capability today. |

---

_Additional criteria (not yet codified in §1.2)_

## switching-cost-portability ❓

**Description:** Skills, memory, plans, and improvement loop can move to a different harness without rewriting them.

**Last updated:** _n/a_

_KRs to be defined._

## vendor-risk ❓

**Description:** Limited exposure to pricing/policy shifts at any single vendor.

**Last updated:** _n/a_

_KRs to be defined._
