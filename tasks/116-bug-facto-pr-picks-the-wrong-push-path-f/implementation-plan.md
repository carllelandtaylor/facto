# Implementation Plan — Fix the push-path decision for `task-start.sh` branches

**Based on:** GitHub Issue #116 ("BUG: facto:pr picks the wrong push path for task-start branches, whose upstream is origin/main"), plus the codebase analysis in Phase 2 of `/facto:plan-implementation`.
**Created:** 2026-08-27
**Branch:** `fix/116-bug-facto-pr-picks-the-wrong-push-path-f`

There is no PRD or design doc for this task — it is a bug fix, and Issue #116's body (What's happening / Impact / Repro / Expected / Root causes) is the requirements input.

---

## Problem

`task-start.sh` creates every task branch with `git worktree add --track … origin/<main>`, which sets the new branch's upstream to `origin/main` — not to a same-named remote branch, which does not exist yet. Two consumers read `@{u}` and wrongly infer "this branch has been pushed":

1. `plugins/facto/skills/pr/SKILL.md` Phase 5 (line 145) — selects the "has upstream" path and runs a plain `git push` instead of `git push -u origin <branch>`. With the default `push.default=simple` this aborts mid-skill; with `push.default=upstream` or `tracking` it would push feature commits onto `origin/main`.
2. `plugins/facto/skills/pr/SKILL.md` Phase 1 (line 45) — `git diff @{u}..HEAD` compares against `origin/main`, so on a branch whose commits are all already in main's history it reports `remote_uptodate=0` and the skill stops with "Nothing new to put in a PR" before Phase 5 is ever reached. Verified in this worktree: `remote_uptodate=0`, `ahead=0`, `behind=0`, and `git ls-remote --heads origin fix/116-…` is empty.
3. `plugins/facto/bin/task-end.sh` lines 69–92 — the same logic in shell. `_te_upstream` resolves to `origin/main`, the unpushed count is measured against main, and the non-empty-upstream branch runs plain `git push`.

The `ahead`/`behind` counts Phase 5 derives are therefore measured against `origin/main`, which also makes the Case C `--force-with-lease` decision meaningless.

`facto:iterate` and `facto:watch-and-fix-ci` delegate pushing to `facto:pr` and inherit the fix for free. A repo-wide grep confirms these are the only three sites that read an upstream.

## Approach

Per `DEVELOPMENT.md` §1.3 Principle 2 ("Hooks enforce, prompts guide — models are non-deterministic, so a skill prompt … works most of the time and silently fails the rest"), the push decision moves out of `SKILL.md` prose and into a new read-only `facto-helper.sh push-plan` subcommand. Both consumers then read one deterministic, unit-tested answer.

The decision keys on whether a **same-named remote branch** exists (`git ls-remote --heads origin <branch>`), never on `@{u}` — which is correct regardless of what upstream happens to be configured, and therefore also repairs the worktrees that already exist with the bogus upstream.

Two hardenings fall out of the redesign and are deliberate:

- The plain-push command becomes `git push origin <branch>` (explicit refspec) rather than bare `git push`. This removes the `push.default` sensitivity that Issue #116 identified as the dangerous configuration — the destination can no longer be inferred from config.
- The force-push uses the plain `--force-with-lease`, leasing against the remote-tracking ref.

  > **Corrected during implementation.** This plan originally specified the *explicit* lease form `--force-with-lease=<branch>:<remote_sha>` with the SHA read live from `ls-remote`, on the reasoning that the remote-tracking ref "may be stale". That was wrong, and dangerously so: a value read live from the remote always matches, so the push can never be refused — the lease silently degrades to a bare `--force`. Caught in manual verification, where the emitted command overwrote a commit another clone had pushed. The remote-tracking ref's staleness *is* the signal the lease exists to check. The default form was then verified to refuse in both risky cases (another clone pushed; the branch was never fetched) and to succeed on the ordinary amend-then-push flow. The original plan's "stale expectation is still rejected" evidence was misleading — it hardcoded an old SHA rather than using the value push-plan actually emits, so it tested git rather than this code.

`push-plan` performs no fetch, so `facto-helper.sh`'s documented read-only invariant ("It changes nothing; every subcommand is a lookup that prints to stdout") is preserved. `ls-remote` is a network read, which is new for this file — noted in the subcommand's own doc comment.

### Decisions taken (from Phase 3)

1. **Helper subcommand, not prose.** Per Principle 2, and it collapses the `task-end.sh` duplicate into one implementation.
2. **All three sites in scope** — Phase 5, Phase 1, and `task-end.sh`. Issue #116's own root-cause section names `task-start.sh`'s upstream as the cause, which makes `task-end.sh` the same bug rather than a new one.
3. **Also stop setting the false upstream at the source** (developer's call, overriding the recommendation to fix consumers only). `--track` at `task-start.sh:292` is **redundant** — git's default `branch.autoSetupMerge=true` already sets tracking when the start point is a remote-tracking ref. Verified: `git worktree add … -b feat/x origin/main` with no flag still yields upstream `origin/main`; only `--no-track` suppresses it. So this is a change from `--track` to `--no-track`, not a deletion.

   **This is why item 2 is load-bearing.** With `--no-track`, `_te_upstream` in `task-end.sh` becomes empty, and its existing empty-upstream branch sets `_te_has_unpushed=true` whenever `git log --oneline -1` returns anything — which is always. Every `task-end` would prompt "You have unpushed commits" even with nothing to push. Step 3 must land with step 4 or `--no-track` introduces a regression.
4. **Behavioral tests plus one structural test** (see Test Strategy).

### Test strategy

The behavioral cases test the real decision function against real git states built in a disposable repo with a real `origin`, following the harness already in `plugins/facto/bin/tests/task-start.test.sh`. They reproduce the exact `task-start.sh` state (upstream `origin/main`, no same-named remote branch) and assert the `-u` first-push — so they fail against today's code and pass after the fix. `ls-remote` works against a local-path remote, so no network is needed.

The structural test is a phrase-grep over `pr/SKILL.md`, weaker by nature: it cannot prove the skill behaves correctly, only that the `@{u}`-based push decision has not been re-inlined into the prose. That is the specific regression worth guarding, and it matches the established pattern in `plugins/facto/skills/observe/tests/skill-structure.test.sh`. It is included with that limitation understood, not as evidence of correctness.

---

## Steps

### Step 1: Add the `push-plan` subcommand to `facto-helper.sh`

**Goal:** A single read-only command answers "how should this branch be pushed?" deterministically, keyed on the existence of a same-named remote branch. No consumer is changed yet, so nothing can break.

**Changes:**

- `plugins/facto/bin/facto-helper.sh`
  - Add `push-plan` to the header's `Subcommands:` block:
    ```
    #   push-plan                  — print the push plan for the current branch as key=value lines:
    #                                branch, remote_branch (absent|present), remote_sha, base, ahead,
    #                                action (nothing-to-push|first-push|push|force-with-lease), command.
    #                                Keyed on whether origin/<branch> exists — NOT on @{u}, which on a
    #                                task-start.sh branch points at origin/<main>. Read-only, but unlike
    #                                every other subcommand it makes one network call (git ls-remote).
    ```
  - Add an internal `_resolve_main_branch` helper. `refs/remotes/origin/HEAD` is **not** set in a `task-start.sh` worktree (verified — `git symbolic-ref --short refs/remotes/origin/HEAD` fails with "is not a symbolic ref"), so it must fall back rather than rely on it. Order: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the leading `origin/`) → `origin/main` if `git rev-parse --verify --quiet` finds it → `origin/master` likewise → default `main`. No network call.
  - Add the `push-plan` block before the "Unknown subcommand" fallthrough, matching the existing `if [[ "$subcommand" == … ]]` … `exit 0` style:
    1. `branch="$(git branch --show-current)"`; if empty (detached HEAD), print `ERROR: not on a branch` to stderr and `exit 1`.
    2. If `git remote get-url origin` fails, print `ERROR: no 'origin' remote` to stderr and `exit 1`.
    3. `remote_sha="$(git ls-remote --heads origin "$branch" | cut -f1)"`.
    4. **Absent** (`remote_sha` empty): `base="origin/$(_resolve_main_branch)"` (fall back to the bare main branch name if the remote-tracking ref is missing); `ahead="$(git rev-list --count "${base}..HEAD")"`; `behind=0`.
       - `ahead == 0` → `action=nothing-to-push`, `command=` (empty).
       - `ahead > 0` → `action=first-push`, `command=git push -u origin <branch>`.
    5. **Present:** `base="origin/$branch"`.
       - `remote_sha == $(git rev-parse HEAD)` → `action=nothing-to-push`, `ahead=0`, `behind=0`, `command=` (empty).
       - Else if `git cat-file -e "${remote_sha}^{commit}"` succeeds AND `git merge-base --is-ancestor "$remote_sha" HEAD` succeeds → fast-forward → `action=push`, `command=git push origin <branch>`, with `ahead="$(git rev-list --count "${remote_sha}..HEAD")"` and `behind=0`.
       - Else → diverged, or the remote object was never fetched → `action=force-with-lease`, `command=git push --force-with-lease=<branch>:<remote_sha> origin <branch>`. Emit `ahead`/`behind` from `git rev-list --left-right --count "${remote_sha}...HEAD"` when the object is present locally; emit `ahead=unknown behind=unknown` when it is not, since divergence cannot be measured without the object.
    6. Print the key=value lines (one per line, in the documented order) and `exit 0`.
  - Update the usage line at the bottom (currently line 256) to include `push-plan`.

  Preserve the file's `set -euo pipefail` contract — guard every command whose non-zero exit is an expected outcome with `|| true` or an explicit `if`, as the existing subcommands do.

**Validation:**
- [ ] `bash -n plugins/facto/bin/facto-helper.sh` — parses.
- [ ] `plugins/facto/bin/facto-helper.sh push-plan` in this worktree prints `remote_branch=absent`, `action=first-push`, `command=git push -u origin fix/116-bug-facto-pr-picks-the-wrong-push-path-f`. This is the exact state Issue #116 reports, so a `first-push` here is the fix demonstrated.
- [ ] `plugins/facto/bin/facto-helper.sh nonsense-subcommand` still prints the usage line and exits 1, with `push-plan` now listed.
- [ ] Existing suites still pass: `bash plugins/facto/bin/tests/facto-helper.test.sh`.

**Commit message:**
```
feat: add facto-helper.sh push-plan subcommand

Context:
The push decision in facto:pr and task-end.sh was keyed on whether the
branch has an upstream, which task-start.sh sets to origin/main — so a
never-pushed branch reads as already-pushed (Issue #116). This adds one
read-only subcommand that keys the decision on whether origin/<branch>
actually exists, so both consumers can share a single tested answer
instead of re-deriving git plumbing. It is the first subcommand that
makes a network call (git ls-remote); it still changes nothing.

Verification:
Automated:
  bash -n plugins/facto/bin/facto-helper.sh
  plugins/facto/bin/facto-helper.sh push-plan
Manual:
  1. Run `plugins/facto/bin/facto-helper.sh push-plan` in this worktree.
     Expect action=first-push and remote_branch=absent, even though
     `git rev-parse --abbrev-ref @{u}` prints origin/main.
```

---

### Step 2: Cover `push-plan` with behavioral tests

**Goal:** Every branch of the decision is pinned by a test that fails against the old `@{u}` logic, so the bug cannot silently return.

**Changes:**

- `plugins/facto/bin/tests/facto-helper.test.sh` — add a `push-plan` section. Reuse the file's existing conventions (`pass`/`fail` helpers, `_FAILS` tally, `set -uo pipefail`, `trap … EXIT` cleanup, per-case subshells).
  - Fixture: a bare repo as `origin` plus a working clone, so `ls-remote` and pushes are real. (`task-start.test.sh` points `origin` at the repo itself, which cannot accept pushes; a bare remote is needed here.)
  - Cases:
    1. **The Issue #116 state.** Branch created with `git worktree add --track … origin/main` so its upstream is `origin/main`, no same-named remote branch, one commit. Assert `remote_branch=absent`, `action=first-push`, and that `command` contains `-u origin <branch>`. Additionally assert `@{u}` really does resolve to `origin/main`, so the test documents the trap it guards.
    2. **No upstream at all** (the post-`--no-track` state), one commit → `action=first-push`.
    3. **Fresh branch, zero commits ahead of main** → `action=nothing-to-push`, `ahead=0`. This is the Phase 1 false "Nothing new to put in a PR" case and the `task-end.sh` false-prompt case.
    4. **Remote branch present, local strictly ahead** → `action=push`, and `command` is `git push origin <branch>` — assert it does **not** contain `--force`, and that it names an explicit refspec rather than a bare `git push`.
    5. **Remote branch present, history rewritten via `git commit --amend`** → `action=force-with-lease`, and `command` contains `--force-with-lease=<branch>:<the ls-remote sha>` — assert the SHA is the real remote SHA, not a placeholder, and that bare `--force` never appears.
    6. **Remote branch present and identical to HEAD** → `action=nothing-to-push`.
    7. **Detached HEAD** → exits non-zero.
  - For each case, run the emitted `command` and assert it succeeds, so the test proves the command is executable, not merely well-formed.
- `DEVELOPMENT.md` — update the §4.2 suite table row for `facto-helper.test.sh` to mention push-plan coverage, and correct the "seven self-contained `*.test.sh` files" count if step 3 adds a file (see step 3).

**Validation:**
- [ ] `bash plugins/facto/bin/tests/facto-helper.test.sh` — every case prints `PASS`, exit 0.
- [ ] Temporarily stub `push-plan` to always emit `action=push` and re-run: cases 1, 2, 3, 5 and 7 must `FAIL`. This proves the tests actually discriminate rather than passing vacuously. Revert the stub.
- [ ] The suite leaves nothing behind: `git status --porcelain` is clean afterward and no stray temp dirs remain.

**Commit message:**
```
test: cover push-plan's decision matrix

Context:
Pins every branch of the push decision against real git states built in
a disposable repo with a real bare origin, including the exact Issue #116
state (upstream origin/main, no same-named remote branch) that the old
@{u} check misread as already-pushed. Each case also runs the command
push-plan emits, so the tests prove it is executable and not just
well-formed.

Verification:
Automated:
  bash plugins/facto/bin/tests/facto-helper.test.sh
Manual:
  1. Stub push-plan to always print action=push.
  2. Re-run the suite; cases 1, 2, 3, 5 and 7 must FAIL.
  3. Revert the stub; all cases PASS again.
```

---

### Step 3: Repoint `facto:pr` Phases 1 and 5 at `push-plan`

**Goal:** The skill stops reading `@{u}` entirely. Phase 5 pushes correctly on a task branch, and Phase 1 no longer aborts the skill with a false "Nothing new to put in a PR".

**Changes:**

- `plugins/facto/skills/pr/SKILL.md`
  - **Phase 1 (lines 41–51).** Replace the `git diff @{u}..HEAD --quiet; echo "remote_uptodate=$?"` fragment of the batched command with `echo '---PUSH---'; facto-helper.sh push-plan`. Rewrite the paragraph at line 47: the signal is now `action`, not `remote_uptodate`. Keep the existing ordering guarantee — the "nothing to do" early exit still fires only when the working tree was also clean, because a dirty tree means `/facto:commit-or-amend` runs first and changes the answer. State the exit condition as `action=nothing-to-push` **and** a clean working tree. Delete the sentence explaining `128` when the branch has no upstream; it no longer applies.
  - **Phase 5 (lines 141–167).** Replace the whole three-case block with: run `facto-helper.sh push-plan`, then run the `command` line it prints verbatim; if `action=nothing-to-push`, skip the push. Keep the existing "Never wrap `git push` in `bash -c '...'`" warning verbatim — it is unrelated to this bug and still applies.
  - Add a short note under Phase 5 explaining **why** the decision is delegated: the existence of an upstream does not imply a same-named remote branch, because `task-start.sh` branches track `origin/<main>`. This is the Principle 7 "empirical gotcha" — record the real failure so a future edit does not re-derive the broken check.
  - **"User Authorization for Force-Push-with-Lease" (line 23).** Update to describe the explicit-lease form now emitted: the lease is pinned to the SHA read from `ls-remote` rather than to a possibly-stale remote-tracking ref. Keep the "never bare `--force`" rule verbatim.
- `plugins/facto/skills/pr/tests/skill-structure.test.sh` — **new file**, modelled on `plugins/facto/skills/observe/tests/skill-structure.test.sh` (read-only, greps `SKILL.md`, `pass`/`fail` tally, no side effects). Cases:
  1. Phase 5 invokes `facto-helper.sh push-plan`.
  2. No `@{u}` push/staleness decision remains anywhere in the file — assert `@{u}` does not appear at all.
  3. Phase 1's early exit keys on `nothing-to-push`, and the string `remote_uptodate` is gone.
  4. Bare `--force` (not `--force-with-lease`) appears nowhere.
  5. The `bash -c` wrapper warning survives — a guard against the rewrite dropping an unrelated rule.

  Head the file with the same honesty note the `observe` suite carries: these assertions are pinned to specific marker phrases, and a future prose edit should either preserve them or update this test deliberately.
- `DEVELOPMENT.md` §4.2 — add the new suite to the table and correct the file count from "seven" to "eight".

**Validation:**
- [ ] `bash plugins/facto/skills/pr/tests/skill-structure.test.sh` — all `PASS`.
- [ ] `grep -n '@{u}' plugins/facto/skills/pr/SKILL.md` returns nothing.
- [ ] Read Phases 1 and 5 end to end and confirm they are executable as written by someone with no context — every referenced variable is defined in the same phase.
- [ ] Re-run the full suite loop from `DEVELOPMENT.md` §4.2; nothing regresses.

**Commit message:**
```
fix: key facto:pr's push path on the remote branch, not the upstream

Context:
Phase 5 treated "has an upstream" as proof a same-named remote branch
exists. task-start.sh branches track origin/<main>, so every Facto task
branch was misread as already-pushed and got a plain push instead of the
first-push with -u (Issue #116). Phase 1 had the same defect and was
worse: it diffed against origin/main and could stop the skill with
"Nothing new to put in a PR" on a branch that was never pushed. Both now
read facto-helper.sh push-plan. The plain push also gains an explicit
refspec, so push.default can no longer redirect it at origin/main.

Verification:
Automated:
  bash plugins/facto/skills/pr/tests/skill-structure.test.sh
  grep -n '@{u}' plugins/facto/skills/pr/SKILL.md   # expect no output
Manual:
  1. In a task-start.sh worktree with one commit and no remote branch,
     run /facto:pr.
  2. Expect `git push -u origin <branch>` — the remote branch is created
     and its upstream repointed away from origin/main.
  3. Expect the skill to reach Phase 6 rather than stopping at Phase 1.
```

---

### Step 4: Fix `task-end.sh` and stop setting the false upstream in `task-start.sh`

**Goal:** The last consumer of the bad inference is gone, and new worktrees no longer carry an upstream that claims something untrue. These two changes ship together because `--no-track` regresses `task-end.sh` unless its detection is fixed in the same commit.

**Changes:**

- `plugins/facto/bin/task-end.sh` (lines 69–92)
  - Replace the `_te_upstream` resolution and the `_te_has_unpushed` derivation with a single `facto-helper.sh push-plan` call, parsing `action` out of its output.
  - `_te_has_unpushed` becomes `action != nothing-to-push`. This is what stops the "always prompts" regression that `--no-track` would otherwise introduce, and it also fixes today's wrong count (measured against `origin/main`).
  - The push branch runs the emitted `command` verbatim instead of choosing between `git push -u origin "$_te_branch"` and `git push`. Preserve the existing failure handling exactly: on non-zero exit, print `Error: push failed. Aborting cleanup.`, unset the `_te_*` locals, and `return 1`.
  - Update the `unset` lists to drop `_te_upstream`/`_te_unpushed_count` and add whatever new locals replace them — this script is **sourced**, so a leaked variable pollutes the developer's shell.
  - If `push-plan` itself fails (no `origin`, detached HEAD), fall back to treating the branch as having unpushed work and prompting, rather than silently skipping the push. Losing commits during cleanup is the worse failure.
- `plugins/facto/bin/task-start.sh` (line 292) — change `--track` to `--no-track`. Add a brief comment recording why: git's default `branch.autoSetupMerge=true` makes `--track` redundant when branching from a remote-tracking ref, and the upstream it sets (`origin/<main>`) is false for a feature branch and misled `facto:pr` (Issue #116). Without the comment, a future reader will "fix" it back.
- `plugins/facto/bin/tests/task-start.test.sh` — add a case asserting the created worktree has **no** upstream (`git rev-parse --abbrev-ref --symbolic-full-name @{u}` fails). No existing case asserts on upstream, so nothing needs updating — only adding.

**Validation:**
- [ ] `bash -n plugins/facto/bin/task-end.sh` and `bash -n plugins/facto/bin/task-start.sh` — both parse.
- [ ] `bash plugins/facto/bin/tests/task-start.test.sh` — all `PASS`, including the new no-upstream case.
- [ ] In a disposable clone, `source task-start.sh --branch throwaway-check`, then confirm `git rev-parse --abbrev-ref --symbolic-full-name @{u}` fails and `facto-helper.sh push-plan` prints `action=nothing-to-push`.
- [ ] In that same worktree, `source task-end.sh` with no commits does **not** prompt to push. Add a commit and confirm it does prompt, and that accepting creates the remote branch.
- [ ] After sourcing both scripts, `set | grep '^_te_'` and `set | grep '^_ts_'` return nothing — no variables leaked into the shell.

**Commit message:**
```
fix: correct task-end.sh's push path and stop task-start.sh setting a false upstream

Context:
task-end.sh carried the same defect as facto:pr — it measured unpushed
commits against origin/main and ran a plain push on any branch with an
upstream. It now reads facto-helper.sh push-plan, the same source of
truth the skill uses. task-start.sh switches --track to --no-track so a
feature branch no longer claims to track origin/main; --track was
redundant anyway, since git auto-tracks when branching from a
remote-tracking ref. The two changes ship together because --no-track
alone would make task-end.sh's old empty-upstream path prompt to push on
every cleanup.

Verification:
Automated:
  bash plugins/facto/bin/tests/task-start.test.sh
Manual:
  1. In a disposable clone, `source task-start.sh --branch throwaway`.
  2. `git rev-parse --abbrev-ref --symbolic-full-name @{u}` must fail.
  3. `source task-end.sh` with no commits: must NOT prompt to push.
  4. Add a commit, run task-end.sh again, accept the push: the remote
     branch is created.
```

---

### Step 5: Record the gotcha in `DEVELOPMENT.md`

**Goal:** The reasoning survives past this PR, so a future edit does not reintroduce the `@{u}` inference.

**Changes:**

- `DEVELOPMENT.md` — under §1.3 Principle 7 ("Empirical Gotchas over speculative rules"), or in the nearest fitting section, add a short entry: an upstream does not imply a same-named remote branch; Facto task branches track `origin/<main>`; push decisions key on `git ls-remote --heads origin <branch>`. Reference Issue #116.
- Confirm the §4.2 table and file count edits from steps 2 and 3 are consistent and land here if they were not already folded in.

Fold this into step 3 or 4 via `/facto:commit-or-amend` if it turns out to be a couple of lines — it does not need to be its own commit.

**Validation:**
- [ ] `DEVELOPMENT.md` §4.2's stated file count matches `ls plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh | wc -l`.

**Commit message:**
```
docs: record the upstream-is-not-a-remote-branch gotcha

Context:
Issue #116 came from inferring "already pushed" from the presence of an
upstream. Recording it under Principle 7 so the inference is not
re-derived by a future edit to the pr skill or the task scripts.
```

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| Git branch tracking semantics (`--track`, `@{u}`, `push.default`, `ls-remote`) | high | Push path is keyed on whether `origin/<branch>` exists, not on `@{u}` | automated — `facto-helper.test.sh` cases 1, 2, 4 |
| Git branch tracking semantics | high | `--force-with-lease` is only considered when a same-named remote branch exists | automated — `facto-helper.test.sh` cases 4, 5 |
| Facto skill-prompt authoring + structural test suites | high | Phase 1 no longer early-exits "nothing to PR" on a never-pushed branch | automated — `facto-helper.test.sh` case 3, plus `pr/tests/skill-structure.test.sh` case 3 |
| Bash script design (`task-end.sh`, `facto-helper.sh`) | high | `task-end.sh` first-push sets upstream on a `task-start.sh` branch | automated — `task-start.test.sh` no-upstream case, plus step 4's manual `task-end.sh` run |
| End-to-end skill execution by a live model | medium | Running `/facto:pr` on a real fresh task branch creates the remote branch and opens the PR | manual-described — step 3's manual steps and the Test Plan below |

No `low`-expertise rows and no `blocked-no-tooling` rows, so the surfacing rule adds nothing to Risks.

## Risks

- **The structural test is a phrase-grep, not a behavioral one.** It can prove the `@{u}` inference is absent from `SKILL.md`; it cannot prove a live model follows the rewritten prose. Mitigated by moving the actual decision into tested shell, which is the point of decision 1 — the structural test only guards against re-inlining.
- **`push-plan` adds a network call to `facto-helper.sh`**, whose other subcommands are local. A slow or unreachable `origin` now slows `facto:pr` Phase 1 and `task-end.sh`. Accepted: `ls-remote` for a single ref is cheap, and it is the only authoritative answer. Both callers must degrade gracefully when it fails — step 4 specifies the `task-end.sh` fallback explicitly.
- **`ls-remote` reflects the remote, not the local remote-tracking ref.** If someone else pushed the same branch name, `push-plan` reports `force-with-lease` where a human might have expected a plain push. The push is then refused rather than silently clobbering, because the lease compares against what this clone last saw — verified end to end: the other clone's commit survives and the push is rejected with `! [rejected] … (stale info)`.
- **`--no-track` changes what `git status` reports** in every new task worktree (no more "ahead of origin/main by N"). This is a deliberate, developer-approved behavior change beyond the minimum fix, not an accident.
- **Existing worktrees keep the `origin/main` upstream.** They are still fixed, because `push-plan` ignores `@{u}` — and the first `-u` push repoints their upstream correctly.
- **No CI exists in this repo**, so nothing runs these suites automatically on a PR. The suites must be run by hand per the Test Plan. Standing up CI is out of scope for this bug.

## Test Plan

- [ ] All suites pass:
      `for t in plugins/*/bin/tests/*.test.sh plugins/*/skills/*/tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done`
- [ ] Every script parses: `for s in plugins/*/bin/*.sh; do bash -n "$s" || echo "FAILED: $s"; done`
- [ ] No linter, type checker, or build exists in this repo — nothing to run.
- [ ] `grep -rn '@{u}\|@{upstream}' plugins/ --include=*.sh --include=*.md | grep -v /tests/` returns nothing outside test fixtures.
- [ ] Manual verification:
  - [ ] In this worktree, `facto-helper.sh push-plan` prints `remote_branch=absent` and `action=first-push` while `git rev-parse --abbrev-ref @{u}` still prints `origin/main` — the Issue #116 state, now decided correctly.
  - [ ] In a disposable clone: `source task-start.sh --branch throwaway-check` → the new worktree has no upstream.
  - [ ] In that worktree with no commits: `facto:pr` reports nothing to PR, and `task-end.sh` does not prompt to push.
  - [ ] Add a commit there, run `/facto:pr` → it pushes with `-u`, the remote branch is created, and a PR opens. This is Issue #116's Expected Result, checked end to end.
  - [ ] Amend that commit and re-run `/facto:pr` → it force-pushes with an explicit lease and updates the existing PR rather than creating a second one.
  - [ ] Push a conflicting commit to the remote branch from elsewhere, then re-run `/facto:pr` → the push is refused with `stale info`, not silently forced.
  - [ ] After sourcing `task-start.sh` and `task-end.sh`, no `_ts_*` or `_te_*` variables remain in the shell.
