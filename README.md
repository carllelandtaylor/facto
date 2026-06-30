# Facto

This is the user guide for Facto, an experimental agentic software development setup that aspires to become a "software factory."

Facto is a set of composable Claude Code skills and shell scripts that guide agents through development. The goal is to learn how far customizing a harness like Claude Code can be pushed to build high-quality software with minimal human intervention.

*Working on Facto itself, not just using it? See [DEVELOPMENT.md](DEVELOPMENT.md).*

### Contents

1. [Who is Facto for?](#1---who-is-facto-for)
1. [Features](#2---features)
1. [What does usage look like?](#3---what-does-usage-look-like)
1. [Setup](#4---setup)
1. [Full reference](#5---full-reference)

## 1 - Who is Facto for?

Mainly, me, [Carl](https://www.linkedin.com/in/carl-taylor-high-fives/) :). This is the personal Claude Code setup I've been building and using. I'm making it public to share with friends, get feedback and suggestions, and have discussions as we all learn what works well.

But if anyone else wants to use or fork it, go ahead! This setup is best for people who:
1. are working on an ongoing project, not trying to one-shot something
1. want agents to do as much as possible independently, while still having the ability to make important calls and verify code quality, and
1. prefer organization, consistency and thoroughness in their workflow.

Just note...

### THIS IS AN EXPERIMENTAL WORK IN PROGRESS!

Many aspects are working well for me, but there's a lot that can be improved still. Many aspects are unpolished or could be optimized better, and several bits are experiments I'm just playing around with.

## 2 - Features
1. **Agent-driven product, design and engineering planning, including Figma-like design mocks** - to let you dial in what you want up-front and reduce expensive iteration time later
1. **Implementation loops that build and verify before completing** - so you don't need to babysit execution
1. **Clear, consistent, reviewable PRs** - so you can verify code quality and actually understand what your agents are building
1. **Worktree management with customizable setup/teardown** - for parallelizing local agents with isolated databases, servers, ports, etc.
1. **GitHub Issues & Projects integration** - to let you file rich, actionable issues with just a few words, and to empower agents to automatically pick up work and track their progress
1. **Built as composable skills to be used within Claude Code** - so you can pick and choose what to use when, and integrate with other systems
1. ... and more

## 3 - What does usage look like?
Facto is built around a simple high-level workflow fairly common to skill development libraries:

1. **Create GitHub issue(s)** — optional, but can help your organization and enable agents automatically grabbing work to do.
1. **Start a task** — in a terminal, run `task-start` to create a git worktree and branch. This is also optional, but helps isolate the work so multiple tasks can run in parallel.
1. **Build** — open Claude Code and run one or more `/facto:*` skills to go from requirements to a merged PR. The skills handle planning, implementation, and validation. They do the vast majority of work independently, but will ask the developer questions in batches at some key points in the process.
1. **Review** — review the PR on GitHub and merge when happy.
1. **End the task** — run `task-end` to clean up the worktree and (if merged) delete the branch.

Some example workflows:

**Creating a new worktree for a GitHub Issue:**
1. `task-start --issue 123` - create a new worktree with isolated server, database, etc
2. Run `/facto:` commands -- they'll automatically pull context from the issue
3. `task-end` - clean up worktree and resources

**Creating a bug report with automatically-added repro steps and context:**
1. `/facto:observe The image processing is timing out when I try to save a new profile image`

**Fixing a bug (works 100% independently from repro to PR with green CI):**
1. `/facto:fix-bug`

**Building a new feature:**

This one will be getting wrapped in a single skill soon :)
1. `/facto:plan-product`
1. `/facto:plan-design`
1. `/facto:plan-implementation`
1. `/facto:implement`
1. `/facto:watch-and-fix-ci`

## 4 - Setup

Facto is packaged as a Claude Code plugin in this repo, but isn't yet distributed on any marketplaces, so you'll need to clone this repo to try it out.

**Prerequisites**
- Linux, OSX, or WSL
- [Claude Code](https://code.claude.com), installed and authenticated
- `git`, and the [`gh` CLI](https://cli.github.com) (authenticated via `gh auth login`) — used by the PR and Issues skills

**1. Clone the Facto repo**

```bash
git clone https://github.com/carllelandtaylor/facto.git
```

**2. Install `facto` as a local plugin via symlink**

Create a symlink from your personal Claude `skills` directory to the Facto plugin in the repo you checked out. (It's weird that you put local plugins in the `skills` dir but [that's how it works](https://code.claude.com/docs/en/plugins#develop-a-plugin-in-your-skills-directory).)
```bash
cd facto    # the directory the clone created
mkdir -p ~/.claude/skills
ln -s "$(pwd)/plugins/facto" ~/.claude/skills/facto
```
Because it's a symlink, edits in the repo go live everywhere immediately. Start a new Claude Code session (or run `/reload-plugins`) to pick it up.

**3. Configure Facto in your project with `/facto:setup-facto`**

Open Claude Code in the project you're building and run `/facto:setup-facto`. This will:
1. add worktree management commands (`task-start`, `task-list`, `task-end`) to your shell profile
1. optionally set up integration with any GitHub Issues + Project tracking you use, and
1. optionally help you set up custom worktree setup and teardown hooks to ensure each worktree has a fresh environment and doesn't collide with the others.

**Setup is now complete!**

---
## 5 - Full reference

There are a lot of skills and commands in Facto, so here's a full reference.

Facto is built around a simple high-level workflow:

1. **Create GitHub issue(s)** — optional, but can help your organization and enable agents automatically grabbing work to do.
1. **Start a task** — in a terminal, run `task-start` to create a git worktree and branch. This is also optional, but helps isolate the work so multiple tasks can run in parallel.
1. **Build** — open Claude Code and use the `/facto:*` skills to go from requirements to a merged PR. The skills handle planning, implementation, and validation.
1. **Review** — review the PR on GitHub and merge when happy.
1. **End the task** — run `task-end` to clean up the worktree and (if merged) delete the branch.

### 5-1 - Worktree management: `task-*` shell scripts

Facto makes it easy to work on multiple unrelated tasks in parallel on one machine via git worktrees. Without Facto, creating worktrees manually isn't hard -- but setting each worktree up so each has its own server, database, port selections, etc. can be. Facto provides a framework for automating isolated worktree setup and teardown.

#### Worktree management commands

These are shell scripts that get added to your `PATH` during `/facto:setup-facto`:

- `task-start` — creates a new branch and worktree, and runs your project's optional custom worktree setup script.
    - `task-start --issue <number|url>` — creates the branch and worktree name based on the issue's contents, which also enables facto skills to automatically update the issue's status as they work.
    - `task-start <conversational description>` — creates the branch and worktree name based on your description.
- `task-list` — lists all active task worktrees with their path and branch.
- `task-end` — checks for uncommitted changes and resolves with you how to handle them, removes the worktree, and deletes the branch if its PR has merged.

#### Customizing worktree setup/teardown for isolation and resource management

When you run `/facto:setup-facto` in your project, it will help you set up some Facto settings and optionally create your custom setup and teardown scripts:

- `<project repo>/.facto/worktree-setup.sh` — runs after `task-start` creates the worktree (e.g. install deps, copy `.env`, run migrations, start services).
- `<project repo>/.facto/worktree-teardown.sh` — runs before `task-end` removes the worktree (e.g. stop services, free ports).

What you put in your setup/teardown scripts will depend on your project, but could include things like:
* setting environment variables to establish unique port numbers for worktree servers to run on
* making a dev database clone just for this worktree so migrations and data changes are isolated

### 5-2 - Task execution: `/facto:*` skills
Once you're in an isolated worktree, or if you're only working on a single task per repo, use the `/facto:*` skills to do the work.

Facto skills fall into two categories (some skills are both):
* **procedure skill:** An ordered sequence of phases to follow start-to-finish — invoke them directly with /<skill> like you're running a command.
* **reference skill:** A set of independent how-tos with no required order — should be picked up automatically by agents running, but refer to them explicitly in prompts if needed to ensure they're used.

#### Setup (one-time)

Run once, per project or app, to establish a baseline; then use the funnel and pipeline skills for ongoing work.

###### `/facto:setup-facto`
Configures your project's repo to use Facto. Run this once in each project repo in which you want to use Facto. Configures worktree commands, issue tracking and worktree setup/teardown for isolation. Sets up the Facto mechanics themselves.

###### `/facto:setup-new-project`
Bootstrap the product direction and technical architecture of a brand-new project. Comprehensive interview about the problem, target users, features, UI design, and tech stack, then produces foundational `PRODUCT-REQUIREMENTS.md` and `TECHNICAL-DESIGN.md` documents that anchor the project.

###### `/facto:setup-design`
!!Very work-in-progress!!

One-time setup for an **existing** app: stands up `docs/design/` from the current state — walking the live UI and source code to produce a device-accurate, per-view design spec for every view, then writing the top-level `index.md`. Run once per surface to establish the evergreen baseline; `/facto:plan-design` maintains it from there. See `/facto:ref-design-system` for the doc contract it follows.

#### Front of the funnel

These produce the requirements/design documents that the pipeline consumes. You can also write your own requirements by hand and skip these.

###### `/facto:plan-product`
For a new feature or feature set in an existing project. Interviews about the problem, target users, and features, then produces a product requirements document. Does not cover visual design (use `/facto:plan-design`) or implementation and tech choices (use `/facto:plan-implementation`).

###### `/facto:plan-architecture`
For technical architecture decisions and high-level technical plans. Walks through functional and non-functional requirements, explores options with trade-offs, and produces an architecture document with a basic implementation plan.

###### `/facto:plan-design`
Designs a feature's UI before implementation planning — produces a view inventory, flow map, and per-view design specs. Sits between `/facto:plan-product` and `/facto:plan-implementation`, reads `/facto:ref-design-mock` for the mechanics of writing out the design-mock HTML file, and reads + updates the evergreen design docs (`/facto:ref-design-system`). Optional and explicit: the suite does not auto-run it, but use it whenever the feature has meaningful UI to nail down before planning.

###### `/facto:ref-design-mock`
The mechanics reference for producing the Figma-style interactive HTML design-mock file: template structure, design tokens, phone frames, layout bands, and the serve-and-inspect workflow. Used by `/facto:plan-design` to render screens, but also usable standalone when you just want a quick rendered mock of a feature without the full design step.

###### `/facto:ref-design-system`
The reference skill defining the contract for **project-wide, evergreen design documentation**: the `docs/design/` layout (a top-level `index.md`, and per surface a `design-system.md` plus per-view specs under `views/`), the "view" model (`screen`, `region`, and `overlay` as inclusive examples, not an exhaustive taxonomy), and the upsert routine that keeps it current. `/facto:plan-design` reads these docs and upserts them after each design task; the docs persist across tasks, unlike the per-task design mock. (Bootstrapped for existing apps by `/facto:setup-design`.)

#### Research

###### `/facto:research`
Turns a research question into a dated, cited HTML report. Scopes the question, runs parallel research subagents, synthesizes the report, then runs an adversarial fact-check loop to catch fabrications and stale claims before delivery. Use for deep-dives, comparisons, or competitive/market context.

#### Pipeline

Start here if you already have requirements (or use one of the front-of-funnel skills first).

##### `/facto:plan-implementation`
Takes product requirements, designs, or front-of-funnel outputs and produces a detailed implementation plan where each step = one commit, with validation commands and commit messages.

##### `/facto:implement`
Hands the plan to subagents and runs autonomously: implements each step, validates after each (tests, lint, build), commits via `/facto:commit-or-amend`, runs `/facto:review-loop-code` at the end, and creates a PR via `/facto:pr`.

##### `/facto:review-loop-code`
Iterative review/fix/validate cycle on a stack of commits. Reviews the diff, fixes all in-scope feedback, folds fixes into the right commits via `/facto:commit-or-amend`, and repeats until clean (default max 5 cycles).

##### `/facto:pr`
Creates or updates a GitHub PR in a "clean, stacked commits" style -- in this style, large changes are broken up into several single-change commits, and iterations on a branch and PR are amended into existing commits on the branch if applicable, rather than tacking them on as new commits at the end. **This is a very personal PR style that may not be for everyone.** Also does some helpful things like detecting whether there's an existing PR already to update rather than creating a new one, and writing a thorough PR description with verification steps.

##### `/facto:iterate`
After a PR is open, applies follow-up feedback. Makes the code change, then hands off to `/facto:pr` for committing, pushing, and updating the PR. Triggers automatically when you request changes on a branch with an open PR.

#### Always available

##### `/facto:commit-or-amend`
Looks at uncommitted changes, decides which existing commit each change belongs to, and folds them in (amend or fixup) — or creates a net-new commit if the change is genuinely independent. Used throughout the pipeline; also useful directly.

#### Issue tracking

###### `/facto:observe`
Captures an observation about the product or app you're building as a GitHub Issue — a few words in, a well-formed Issue out. Routes it to a matching open or recently-closed Issue (commenting) or opens a new one, and can close an Issue on its own when positive evidence is strong.

#### Bug fixing

For going from a bug report to a verified, green PR. `/facto:fix-bug` is the entry point; the other two are reusable helpers it orchestrates (and both are usable standalone).

###### `/facto:fix-bug`
End-to-end, autonomous bug fix. Reproduces the bug (`/facto:repro-bug`), diagnoses the root cause, fixes it with adaptive escalation (a direct commit for small/localized fixes; `/facto:plan-implementation` + `/facto:implement` for large/structural ones), verifies against the logged repro steps, opens a PR (`/facto:pr`), and watches CI until green (`/facto:watch-and-fix-ci`). Guards against symptom-only fixes and against removing working functionality.

###### `/facto:repro-bug`
Reproduces a reported bug in the running app and returns precise, repeatable repro steps. Brings up the app, drives it (exploring when the report lacks exact steps), then distills the minimal sequence and evidence — or reports a clean "could not reproduce". First step of `/facto:fix-bug`, also usable standalone.

###### `/facto:watch-and-fix-ci`
Makes CI pass on the current branch's open PR. Watches the checks, and for each failure pulls its logs, reproduces it locally by re-running that check's own command, fixes the root cause, pushes via `/facto:iterate`, and loops until green. Guards against silencing CI by deleting legitimate tests. Final step of `/facto:fix-bug`, also usable standalone.
