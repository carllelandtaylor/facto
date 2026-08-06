# Facto on Fabro

A [Fabro](https://fabro.sh) workflow for every `/facto:*` skill in
`plugins/facto/skills/`. Fabro runs workflows defined as Graphviz graphs, so
each skill's phases become nodes and each cross-skill invocation becomes a
graph import.

`facto-dev:*` skills are deliberately not included — they are for developing
Facto itself, not for using it.

## Layout

```
fabro/
  install.sh              links workflows/ into ~/.fabro/workflows/
  workflows/facto-*/      one directory per skill: workflow.fabro + workflow.toml
  docker/                 image definition for the ACP environment
  environments/           project.toml snippet for that environment
```

## Install

Fabro resolves a workflow name from exactly two places: the current project's
`.fabro/workflows/` and the user-level `~/.fabro/workflows/`. There is no
configurable search path, so making these available across repositories means
linking them into the user-level directory:

```sh
./install.sh
```

That creates one symlink per workflow. Editing a file here changes what runs
immediately — no reinstall, and no copy to keep in sync. Then, from any repo:

```sh
fabro run facto-fix-bug
```

`./install.sh --uninstall` removes the links again. It only removes symlinks
that point back into this directory, so a hand-written workflow that happens to
share a name is left alone.

## Workflows

| Workflow | Imports |
| --- | --- |
| `facto-fix-bug` | repro-bug, plan-implementation, implement, review-loop-code, pr, watch-and-fix-ci, commit-or-amend |
| `facto-implement` | review-loop-code, review-loop-design-impl, pr, commit-or-amend |
| `facto-watch-and-fix-ci` | iterate, pr |
| `facto-setup-design` | ref-design-mock, ref-design-system, pr |
| `facto-plan-design` | ref-design-mock, ref-design-system |
| `facto-review-loop-code` | commit-or-amend, pr |
| `facto-review-loop-design-impl` | commit-or-amend, ref-design-mock |
| `facto-iterate` | pr |
| `facto-pr` | commit-or-amend |
| `facto-setup-new-project` | setup-facto |
| `facto-commit-or-amend` | — |
| `facto-observe` | — |
| `facto-plan-architecture` | — |
| `facto-plan-implementation` | — |
| `facto-plan-product` | — |
| `facto-ref-design-mock` | — |
| `facto-ref-design-system` | — |
| `facto-repro-bug` | — |
| `facto-research` | — |
| `facto-setup-facto` | — |

Imports use relative sibling paths (`../facto-pr/workflow.fabro`), so the
workflow directories have to stay siblings of one another. The symlink install
preserves that: every directory is linked into the same target, so
`../facto-pr/` still resolves.

Fabro rejects import cycles, and the skills' prose contains apparent ones —
`facto-repro-bug` describes itself as "the first step of `/facto:fix-bug`", for
example. Only real invocations ("run `/facto:X`") are modelled as imports;
descriptive cross-references are not. That is what makes the graph acyclic.

## Running through Claude Code instead of the API

By default Fabro runs its own agent loop against a provider API, which means
API billing. Fabro's `acp` backend instead spawns an external Agent Client
Protocol process that owns its own auth, so pointing it at the Claude Code ACP
adapter runs these workflows on a Claude subscription.

`environments/claude-acp.toml` has the setup: build the image, mint a token
with `claude setup-token`, store it with `fabro secret set`, and copy the
environment block into the target repo's `.fabro/project.toml`. Environments
are per-project in Fabro, so that copy is per-repo even though the workflows
are shared.

## What these are, and are not

These are structural translations of the skills, not runtime-equivalent ones.
The skills are written for the Claude Code harness and use features Fabro's
graph model has no direct counterpart for — most visibly per-step subagent
spawning with a chosen model, which `facto-implement` and `facto-fix-bug` both
do repeatedly. Those became ordinary agent nodes carrying `model="opus"` or
`model="sonnet"` where the skill named one. Fabro child runs would be the
closer analogue if real runtime delegation is wanted; that is a larger change.

Imports splice inline rather than delegating at run time, so node counts
compound. `facto-fix-bug` is 286 nodes once four levels of imports flatten out,
and a graph-level `max_node_visits` applies across all of it.
