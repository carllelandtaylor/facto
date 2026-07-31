# Facto Development

## About this doc

This doc describes the goals of Facto and how we will continuously improve it. This doc is for people and agents iterating on Facto, not just using it for a project.

## 1 - The Facto Project
### 1.1 - Vision

This repository implements a **software factory** — a system in which Claude Code can plan, build, polish, and ship high-quality software with minimal human intervention through the middle of the work, scaling the developer's capacity well beyond what they could write by hand.

Facto aims to ultimately be proficient in
- Product development
- Product design
- Engineering
- Product marketing
- Customer support
- Data analytics
- Other adjacent functions

but will build these capabilities over time.

### 1.2 - Goals/Requirements

The software producted by Facto:

- **Product direction** — what Facto chooses to build serves the user well, solving the right problems in effective ways.
- **UI/UX Design** — UI output is intuitive, appealing, and functionally correct on the user's tasks.
- **Code correctness** — code works correctly and reliably; it does what it's supposed to do.
- **Code maintainability** — code is clear, idiomatic, and easy for humans and agents to read and maintain.
- **Reviewability** — humans can easily inspect and understand changes.

How Facto operates:

- **Independence** — Facto can make a lot of progress autonomously without needing to frequently ask the developer for information or permission (asking lots of questions up front and at the end is fine, just not in the middle).
- **Reliability** — Facto runs end-to-end without breaking, stalling, or unexpectedly stopping mid-task. When something does go wrong, it recovers rather than waiting for the developer to nudge it back on track.
- **Throughput** — Facto ships a high volume of work per unit time across all in-flight tasks.
- **Single-task speed** — Facto completes individual tasks quickly. (Important for critical bug fixes, production-incident fixes, and any time-sensitive single piece of work.)
- **Cost-effective** — Facto is runnable at an economic cost.
- **Project-agnostic** — Facto is in its own repo, and in this repo has no knowledge of the actual projects and repos it will be used to help build.
- **Project-customizable** — projects using Facto can customize its behavior as needed via configuration in their own repo.
- **Automatically Self-improving** — Facto reflects on its own work and improves itself over time.

### 1.3 - Facto Principles

These principles guide how Facto operates and how it's designed. These principles are learned over time from industry best practices and Facto's own experience. Consider these principles when adding to or modifying any of Facto's code-building compoents. Update these principles if we learn new ones.

1. **Single-threaded writes, multi-threaded intelligence** — at any moment, only one agent modifies the working tree. Multiple intelligences (planner, reviewer, advisor) can run in parallel, but they produce read-only artifacts that feed one writer.

   *Why:* parallel writers make implicit decisions the other can't see — naming, interfaces, error handling — and the work doesn't compose.

   *Example:* `facto:review-loop-code` spawns a read-only review subagent that produces feedback; the implementation agent reads the feedback and writes the fix.

2. **Hooks enforce, prompts guide** — when a behavior must happen, encode it as a hook that gates the action. Skill prompts express defaults; the model can ignore them, but hooks cannot be ignored.

   *Why:* models are non-deterministic, so a skill prompt saying "always run tests" works most of the time and silently fails the rest.

   *Example:* "tests must pass before a session ends" belongs in a Stop hook running the project's verify command, not in a skill prompt asking Claude to remember.

3. **Structured artifacts between steps** — every pipeline step produces a file that the next step reads. State that matters never lives only in conversation context.

   *Why:* conversation context is volatile (compaction drops detail), bounded, and invisible to other sessions, so anything load-bearing in chat will eventually be lost.

   *Example:* `facto:plan-implementation` writes a markdown plan to disk that `facto:implement` reads — the plan survives compaction and stays inspectable to humans.

4. **Skills as the primary primitive** — Facto is composed of skills. Subagents are transient workers spawned by skills for context isolation or constraint, not first-class building blocks; custom subagent definitions should be rare.

   *Why:* skills are lightweight, composable, and user-invocable; custom subagents add a parallel hierarchy that gatekeeps context and triggers inconsistently.

   *Example:* `facto:implement` is a skill that spawns transient Sonnet subagents when a step warrants one, rather than relying on a custom `implement-worker` agent definition.

5. **Pipeline composition over monolithic skills** — each skill does one phase well. Add a skill rather than growing an existing one when responsibilities cross. The macro shape is plan → implement → review → ship.

   *Why:* every line in SKILL.md is a recurring token cost once invoked, and a skill that absorbs multiple phases dilutes its triggers and becomes brittle to edit.

   *Example:* `facto:implement` and `facto:review-loop-code` are separate skills rather than one mega-skill with a `--mode=implement` / `--mode=review` switch.

6. **CLI tools before MCP servers** — when Facto needs an external capability, prefer a CLI command the agent can invoke via Bash. Reserve MCP for capabilities that genuinely lack a CLI surface (e.g. browser automation).

   *Why:* CLI output is plain text the agent can grep and pipe, the interaction is reproducible as a shell script, and most popular MCPs duplicate a CLI that already does the job better.

   *Example:* `facto:pr` shells out to `gh pr view` rather than calling a GitHub MCP server — Ronacher's direct test showed `gh` uses context far more efficiently.

7. **Empirical Gotchas over speculative rules** — every observed failure mode becomes a concrete entry in the relevant skill's Gotchas list. Skill prompts converge on rules that came from real failures, not best practices written speculatively up front.

   *Why:* speculative rules ("think hard", "consider edge cases") describe the happy path and don't move behavior on the actual failures.

   *Example:* "After two failed validation cycles this skill tends to keep changing unrelated code; stop and reread the original error" — written after watching it happen, not before.

8. **Components are provisional, not permanent** — each harness component (skill, hook, scaffolding step) exists because the model couldn't do something well enough alone at the time it was added. Each is an assumption about model capability.

   *Why:* model capability moves on every release, so components designed for old failure modes can become counterproductive — over-constraining behavior the model now handles correctly.

   *Example:* Anthropic removed the "sprint" construct from their internal harness when Opus 4.6 landed because the model no longer needed it.

---

## 2 - Conventions
### 2.1 - Skill conventions: procedure vs reference

Skills in `plugins/facto/skills/` and `plugins/facto-dev/skills/` fall into two structural types that determine how they should be read and invoked:
* **procedure skill:** An ordered sequence of phases to follow start-to-finish — run them in the order given, every time the skill is invoked.
* **reference skill:** A set of independent how-tos with no required order — the caller decides which sections to use and when; there is no implied sequence.

Some skills are **both**: you may run the phases in order the first time (acting as a procedure), or individual phases can be reused independently.

Every skill's `description:` field declares its type. **Append** one of these as the final sentence of the description, after the prose (including any `Invoke with /x.`):

- `Procedure skill (follow the phases in order).`
- `Reference skill (independent how-tos — use what you need, in any order).`
- `Procedure + reference skill (run the phases in order once; reuse individual phases as reference when needed).`

---

## 3 - Facto Improvement System

We will continuously improve Facto as a closed-loop system. Human developers and agents will team up to observe and remember what works and doesn't and feed those observations back into changes. We'll codify this system and process of improvement so it's easily repeated, automated, and so we can improve the improvement system!

### 3.1 - Improvement System Goals
1. Recommends the highest-leverage next improvements to make.
2. Learns from its own experience and the rapidly-advancing best practices around the industry.
3. Does most work independently, but confirms changes to Facto with the developer before making them.

### 3.2 - Improvement System Principles
The Facto development and improvement process is based on the following principles. Use these when deciding how to modify them:
1. The improvement system should have clear definitions of success that it's working towards.
2. It should have access to the Facto results so it can compare them against its definitions of success and understand what worked well and what didn't.
3. It should have access to Facto's methods of producing those results (ex: Claude Code logs) so it can inspect them and look for improvements.
4. It should have access to internet resources to learn how other people are solving problems like this.
5. Medium and large Facto improvements should be tested before landing. Each should have one or more verifiable predictions for what they will improve.
6. The Facto improvement process should be mostly automated, but should always check with a human before confirming changes.

### 3.3 - Improvement System

Facto is a closed-loop system. This Facto improvement system is also a closed-loop system, coupled to the Facto system. Here's how they relate:

- Facto
  - Input: instructions and requests from a human developer using Facto
  - Output: built software
- Facto improvement system
  - Input:
    - Developer feedback on the built software, to understand the quality of the Facto output
    - Claude Code logs, to see how quickly and efficiently Facto built its output
    - Improvement memory (see below), to recall what this improvement system has learned from the past
    - Internet research this improvement system performs, to learn from others in this fast-moving domain
  - Output:
    - Modifications to Facto, to improve its future results
    - Entries in the improvement memory, to remember things for future iteration

### 3.4 - Improvement memory

The improvement memory is where the system stores information related to its improvement attempts across sessions. It is split into two surfaces:

1. **GitHub Issues** on `carllelandtaylor/facto` — every Facto improvement (a bug to fix or an enhancement to ship) is one Issue. Supporting observations are comments on the relevant Issue. A new observation either lands as a comment on a matching open or recently-closed Issue, or opens a new Issue if no Issue matches. For the full tracker setup (Project, Status field, PR-linking convention, labels), see the `## Issue tracking` section in the repo-root `CLAUDE.md`.
2. **OKRs** in `OKRS.md` — Facto's current Objectives and Key Results, used as the shared definition of success that improvements are evaluated against.

#### GitHub Issues

The system accumulates observations as Facto works. `facto-dev:observe` routes each one — using a model-based same-root-cause match against existing open and recently-closed Issues — to the right Issue (as a comment) or to a new Issue. `facto-dev:think` periodically reviews open Issues and decides whether to close them, update their Status, or leave them alone.

#### OKRs

OKRs are Facto's current Objectives and Key Results — a structured, measurable subset of Facto's durable mission stated in §1.2. Each Objective names a desired property of Facto; its Key Results are prose statements with explicit targets that make the objective observable.

OKRs live in a single file at `OKRS.md` in the Facto repo root, not one file per OKR. The file rarely changes between sessions, so a single document is the simplest shape.

#### Lifecycle

1. **Observations are filed** via `/facto-dev:observe` (developer-initiated) or `/facto-dev:mine-logs` (mines a Claude Code session log and routes each candidate through `/facto-dev:observe` in caller mode). For each observation, `facto-dev:observe` searches open Issues plus Issues closed within the last 30 days for a same-root-cause match. If a match exists, it comments. If the observation is strong positive evidence on an open Issue, `facto-dev:observe` may close that Issue as `completed` and set Status → Done autonomously. If no match exists, a new Issue is opened and Status is set to Backlog.
2. **Open Issues are periodically reviewed** by `/facto-dev:think`. For each Issue, the skill reads body + comments and decides whether to close (as `completed` → Done, or `not-planned` → Done), propose a fix direction (comment, no Status change), demote In review/In test back to Backlog on contradicting evidence, or skip silently. When there's nothing new to say about an Issue, no comment is written — the no-filler rule.
3. **Status is reported** by `/facto-dev:status`. The skill reads open Issues + closed-in-last-30-days, groups by Status, plus prints the OKR status verbatim from `OKRS.md`. Read-only — it never modifies anything.

## 4 - Developing Facto

### 4.1 - Testing in-progress changes with `fi-task-test`

`fi-task-test.sh` (in `plugins/facto-dev/bin/`) lets you test changes to Facto that are still in a worktree, before they merge.

The global install symlinks `~/.claude/skills/facto` and `~/.claude/skills/facto-dev` at the **main checkout's** `plugins/facto` and `plugins/facto-dev`, so Facto improvements made inside a `task-start` worktree aren't active while you work on them. `fi-task-test.sh` bridges that gap by re-pointing those two install symlinks:

- **From inside a worktree** — repoints `~/.claude/skills/facto` → `<worktree>/plugins/facto` and `~/.claude/skills/facto-dev` → `<worktree>/plugins/facto-dev`, so Facto's global install transparently resolves to the worktree's in-progress skills. Only done when the main checkout is **on the default branch, up to date with `origin`, and has no uncommitted changes**.
- **From the main checkout** — repoints both install symlinks back at `<main>/plugins/facto` and `<main>/plugins/facto-dev`. This is the un-do / escape hatch and has no preconditions.

It only ever manipulates the `~/.claude/skills/*` install symlinks — it never modifies tracked files in any checkout.

```bash
# optional alias
alias fi-task-test='fi-task-test.sh'

# in a worktree: point the global install at this worktree's plugins/
fi-task-test.sh
# ...test your in-progress skill changes in any Claude Code session...
# back in the main checkout: restore the committed plugins/
fi-task-test.sh
```

### 4.2 - Running the tests

The shell scripts under `plugins/*/bin/` and the design-mock template have a small
homemade test suite — four self-contained `*.test.sh` files under
`plugins/*/bin/tests/` and `plugins/*/skills/*/tests/`, no test framework:

| Suite | Covers |
|---|---|
| `plugins/facto/bin/tests/task-start.test.sh` | `task-start.sh` argument parsing — issue detection, branch-name derivation, the `UNKNOWN-` no-issue convention |
| `plugins/facto/bin/tests/task-list.test.sh` | `task-list.sh` worktree-listing output (snapshot) |
| `plugins/facto-dev/bin/tests/fi-task-test.test.sh` | `fi-task-test.sh` install-symlink re-pointing (link / reset / preconditions / Facto guard) |
| `plugins/facto/skills/ref-design-mock/tests/template-task-spec.test.sh` | design-mock task-spec template structure — per-flow bands, connector labels, project-agnostic tokens |

Each suite is self-contained and safe to run from anywhere: the script suites set
up their own disposable git repos and assert against them; the template suite only
reads the template. None of them leave anything behind. The
`fi-task-test` suite is sandboxed so it never disturbs your real
`~/.claude/skills/` install while it runs.

Run one suite directly, or all of them. Each prints `PASS`/`FAIL` per case and
exits non-zero if any case fails:

```bash
# a single suite
bash plugins/facto/bin/tests/task-start.test.sh

# all suites — runs every one, flags any that fail
for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
```

**Why homemade, not [bats](https://github.com/bats-core/bats-core)?** The suite is
tiny, and each test just gives the script some inputs and checks the resulting
branches, symlinks, or output — or, for the template, greps it for the structural
markers it must keep. Plain `bash` keeps it zero-dependency and runnable
in any checkout or CI step without an install. Revisit bats if the suite grows
enough that per-test isolation and reporting start to hurt.
