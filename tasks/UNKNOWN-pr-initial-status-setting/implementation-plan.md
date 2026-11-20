# Implementation Plan: Configurable initial state (draft or open) for PRs created by `facto:pr`

**Requirements and specs:** Developer request in the planning session: "I want /pr to have a new facto setting that controls whether PRs newly created start as Draft or Open." The developer then chose to store the setting per repo in the committed `.facto/settings.json`. No issue is attached, and there is no PRD or design doc.
**Created:** 2026-11-19

---

## Requirements Summary

- A new setting in the repo's `.facto/settings.json` decides whether `facto:pr` creates a new PR as a draft or as an open PR.
- The setting is per repo and committed, so it is shared by everyone who works in the repo.
- When the setting is absent, PRs open as they do today. Existing repos see no change.
- The setting only applies when `facto:pr` creates a PR. That covers both create paths: no PR exists yet, and the previous PR is `MERGED`. The update path and the reopen path leave the PR's draft/open state alone.
- When a PR is created as a draft, the active issue still moves to `in_review`, exactly as it does for an open PR.
- `/facto:setup-facto` asks for the setting, and the README documents it.

## Key Decisions

| Decision | Options Considered | Chosen | Rationale |
|----------|-------------------|--------|-----------|
| Where the setting is stored | Local git config (per user); gitignored `.facto/settings.local.json`; user-level file keyed by repo; the committed `.facto/settings.json` | `.facto/settings.json` | The developer said a shared per-repo value is fine. The file already exists and the helper already reads it. |
| Shape of the value | Enum `draft` \| `open`; boolean | Enum at `.pr.initial_state` | Matches the developer's wording. Any other value prints a warning to stderr and falls back to `open`. |
| How a user sets it | `/facto:setup-facto` question plus README; README only | `/facto:setup-facto` question plus README | Setup is where every other per-repo setting is chosen. |
| Issue Status when the new PR is a draft | Still `in_review`; leave at `in_progress` | Still `in_review` | CLAUDE.md defines In review as "solutions are up in a PR", and a draft PR meets that. Nothing in Facto would move the issue to `in_review` later when the PR is marked ready. |

## Notable Technical Choices

- **New read-only subcommand `facto-helper.sh pr-initial-state`.** It prints exactly `draft` or `open`. Validation and the default live in one place that tests can cover, instead of being restated in skill prose. It follows the existing `_tasks_base` pattern for reading a top-level key with `jq`. Like `task-dir`, it works when no config exists: a missing `settings.json` means `open`. It is therefore placed **before** the "All remaining subcommands need the config to exist" guard.
- **`gh pr create --draft`.** This is the standard `gh` flag. No new dependency is added.

---

## Commits

1. `feat: add facto-helper.sh pr-initial-state subcommand`: resolves the setting to `draft` or `open`, with behavioral tests.
2. `feat: let facto:pr create PRs as drafts when configured`: both create paths in Phase 6 pass `--draft` when the helper prints `draft`. Includes structural tests.
3. `feat: ask for the PR initial state in setup-facto and document it`: adds the setup question and the README section.

---

### Step 1: Add `facto-helper.sh pr-initial-state`

**Goal:** One tested command answers "should a newly created PR be a draft?" for the current repo.

**Changes:**
- `/home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/bin/facto-helper.sh`
  - Add a `pr-initial-state` block placed before the `# All remaining subcommands need the config to exist` guard, next to `task-slug`, `task-dir` and `push-plan`, which also work without a config.
  - Logic:
    - If `$CONFIG` is missing, print `open` and exit 0.
    - Otherwise read `jq -r '.pr.initial_state // empty' "$CONFIG"`. If `jq` fails (malformed JSON), treat the value as empty.
    - Empty → `open`.
    - `draft` or `open` → print it as is.
    - Any other value → print `WARNING: .pr.initial_state must be "draft" or "open"; got "<value>" — using "open"` to stderr, print `open` to stdout, and exit 0. The fallback is deliberately lenient: a typo must never block PR creation.
  - Add the subcommand to the header's `Subcommands:` list and to the usage line printed for an unknown subcommand.
- `/home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/bin/tests/facto-helper.test.sh`
  - Add cases using the existing `_run` helper and the throwaway repo. Each case rewrites `$_TMP/.facto/settings.json`.
    - No `settings.json` at all → `open`, exit 0.
    - `settings.json` with no `pr` key → `open`.
    - `"pr": {"initial_state": "draft"}` → `draft`.
    - `"pr": {"initial_state": "open"}` → `open`.
    - `"pr": {"initial_state": "Draft"}` (wrong case) → stdout `open`, the warning on stderr, exit 0.
    - Malformed JSON → `open`, exit 0.
  - Update the file's header comment to list `pr-initial-state` among the covered subcommands.

**Validation:**
- [ ] `bash /home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/bin/tests/facto-helper.test.sh` prints `ALL PASS`. All existing `push-plan` and `task-dir` cases still pass.
- [ ] Run `plugins/facto/bin/facto-helper.sh pr-initial-state` in this worktree. This repo's settings have no `pr` key, so it prints `open`.

**Commit message:**
```
feat: add facto-helper.sh pr-initial-state subcommand

Context:
facto:pr needs a per-repo setting for whether newly created PRs start as
drafts. The setting is .pr.initial_state in .facto/settings.json ("draft" or
"open"). This subcommand is the one place that reads and validates it: an
absent key, a missing file and malformed JSON all mean "open", which is
today's behavior. An unknown value warns on stderr and also means "open", so
a typo never blocks PR creation.

Verification:
Automated:
  bash plugins/facto/bin/tests/facto-helper.test.sh
Manual:
  1. In a repo whose .facto/settings.json has no "pr" key, run
     facto-helper.sh pr-initial-state — expect "open".
  2. Add "pr": {"initial_state": "draft"} and rerun — expect "draft".
```

---

### Step 2: `facto:pr` creates drafts when configured

**Goal:** A PR that `facto:pr` creates is a draft exactly when `pr-initial-state` prints `draft`. Nothing else about the PR's state changes.

**Changes:**
- `/home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/skills/pr/SKILL.md`
  - In Phase 6, add a short subsection, "Initial state (first creation only)", next to "Active Issue link + Status write". It says:
    - Before `gh pr create`, run this in a ```bash block:
      ```bash
      facto-helper.sh pr-initial-state
      ```
    - If it prints `draft`, add `--draft` to `gh pr create`. If it prints `open`, add nothing.
    - This applies to both create paths: no PR exists, and the previous PR is `MERGED`.
    - The update path and the reopen path (`gh pr reopen`) never change draft/open state. Never run `gh pr ready` or `gh pr ready --undo`.
    - The `in_review` Status write still happens for a draft PR.
  - In the two Phase 6 bullets that say "create one with `gh pr create`", point to the new subsection so neither path can skip it.
  - Add a matching clause to the existing "Update path — explicit no-write rule" paragraph: do not change the PR's draft/open state.
  - In Phase 7, add one line: when the PR was created, report whether it was created as a draft or as open.
- `/home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/skills/pr/tests/skill-structure.test.sh`
  - Add cases in the existing style:
    - A ```bash block contains `facto-helper.sh pr-initial-state`. This uses `_code_lines`, so a mention in prose doesn't count.
    - The text `--draft` appears in `SKILL.md`.
    - No ```bash block contains `gh pr ready`. The skill must never flip the state of an existing PR.
    - The marker phrase forbidding draft/open changes on the update path is present.
  - Update the header comment to say the suite now also guards the draft setting.

**Validation:**
- [ ] `bash /home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/skills/pr/tests/skill-structure.test.sh` prints `ALL PASS`. The new cases fail if run against the pre-change `SKILL.md`.
- [ ] Manual end-to-end check: see Test Plan below.

**Commit message:**
```
feat: let facto:pr create PRs as drafts when configured

Context:
facto:pr now reads facto-helper.sh pr-initial-state before gh pr create and
passes --draft when it prints "draft". It does this on both create paths (no
PR yet, and previous PR merged). Updating or reopening a PR never changes its
draft/open state. The active issue still moves to in_review, because a draft
PR is still a solution up in a PR.

Verification:
Automated:
  bash plugins/facto/skills/pr/tests/skill-structure.test.sh
Manual:
  1. In a scratch repo with "pr": {"initial_state": "draft"}, run /facto:pr
     on a new branch with one commit. gh pr view --json isDraft -q .isDraft
     prints true.
  2. Make another commit and run /facto:pr again (update path). isDraft is
     still true.
  3. Remove the "pr" key, open a fresh branch, run /facto:pr. isDraft is
     false.
```

---

### Step 3: Ask in `setup-facto` and document in the README

**Goal:** Users can find the setting, and `/facto:setup-facto` writes it.

**Changes:**
- `/home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/skills/setup-facto/SKILL.md`
  - Add a new per-project phase, "Phase 3c: Initial state for new PRs", after Phase 3b and before Phase 4. It runs whatever tracker was chosen, including none.
  - The question to ask: "Should PRs that `/facto:pr` creates in this repo start as drafts or as open PRs? Default: open."
  - If the answer is `open`, write nothing, because the absent key already means open.
  - If the answer is `draft`, merge a top-level `"pr": { "initial_state": "draft" }` into `.facto/settings.json` at the repo root, creating the file as `{}` first if it doesn't exist. Use `jq`; never overwrite other keys. A file with no `tracker` key is valid, and `tracker.exists` still reports no tracker.
  - Phase 5 (Activate and verify): when the key was written, verify it with `facto-helper.sh pr-initial-state`, which should print `draft`.
  - Add `/facto:pr`'s initial state to the `description:` frontmatter's summary of what the skill writes, with as few words as possible.
- `/home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/README.md`
  - After the "Choosing an issue tracker" subsection, add a short subsection, "Draft or open PRs". It shows the `"pr": { "initial_state": "draft" }` snippet and states that the absent key means open. It also states that the setting applies only when `/facto:pr` creates a PR.

**Validation:**
- [ ] Both test suites still print `ALL PASS`, because nothing they read changed in a way they assert on.
- [ ] Simulate the jq merge from the setup-facto prose against a copy of this repo's `settings.json` in the scratchpad, and check that `jq .` shows the `tracker` key unchanged plus the new `pr` key.

**Commit message:**
```
feat: ask for the PR initial state in setup-facto and document it

Context:
setup-facto gains a per-project question that writes .pr.initial_state into
.facto/settings.json when the user wants drafts. It merges the key with jq so
tracker config is kept. The README documents the key next to the tracker
settings.

Verification:
Automated:
  bash plugins/facto/bin/tests/facto-helper.test.sh
Manual:
  1. Run /facto:setup-facto in a scratch repo and answer "draft". Then
     facto-helper.sh pr-initial-state prints "draft", and
     jq .tracker .facto/settings.json prints the same tracker config as
     before.
```

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Bash and jq reading `.facto/settings.json` | high | Absent key, missing file or invalid value → `open`; `draft` → `draft` | automated (Step 1 cases) |
| Skill prose (`facto:pr` Phase 6) | high | A newly created PR is a draft when the setting is `draft` | automated (structural, Step 2) + manual-described (Test Plan check 1) |
| Skill prose (`facto:pr` Phase 6) | high | Update and reopen paths leave the draft/open state unchanged | automated (structural: no `gh pr ready`, no-write marker) + manual-described (Test Plan check 2) |
| Skill prose (`facto:pr` Phase 6) | high | The issue still moves to `in_review` for a draft PR | manual-described (Test Plan check 1) |
| Skill prose (`facto:setup-facto`) | high | Setup writes the key without disturbing existing settings | manual-described (Step 3 validation, Test Plan check 4) |

## Risks

- No row has low expertise or `blocked-no-tooling` verification.
- Structural tests can't prove the model follows the `SKILL.md` prose. Whether `--draft` is actually passed is confirmed only by the manual end-to-end check.

## Test Plan

- [ ] All project tests pass:
  - `bash /home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/bin/tests/facto-helper.test.sh`
  - `bash /home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/skills/pr/tests/skill-structure.test.sh`
  - `bash /home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/bin/tests/task-start.test.sh`
  - `bash /home/carltaylor/git/facto/.facto/worktrees/UNKNOWN-pr-initial-status-setting/plugins/facto/bin/tests/task-list.test.sh`
- [ ] Linter passes: N/A. The repo has no linter.
- [ ] Type checker passes: N/A.
- [ ] Build succeeds: N/A.
- [ ] Manual verification (use a scratch GitHub repo, with `fi-task-test` pointing the install at this worktree):
  - [ ] 1. Set `"pr": {"initial_state": "draft"}` and run `/facto:pr` on a new issue-backed branch. `gh pr view --json isDraft -q .isDraft` prints `true`, the issue's Status is `In review`, and the Phase 7 summary says the PR was created as a draft.
  - [ ] 2. Make another commit on the same branch and run `/facto:pr` again. The PR is updated, and `isDraft` is still `true`.
  - [ ] 3. Remove the `pr` key, start a fresh branch and run `/facto:pr`. `isDraft` is `false`.
  - [ ] 4. Run `/facto:setup-facto` in the scratch repo and answer `draft`. `facto-helper.sh pr-initial-state` prints `draft`, and the existing `tracker` config is unchanged.

## Flags

- None.
