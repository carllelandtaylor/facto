---
name: pr
description: "TRIGGER when: a PR needs to be created or updated — whether you have uncommitted changes, unpushed commits, or the PR description is stale. Uses facto:commit-or-amend for commits, then pushes and creates or updates the GitHub PR. Procedure skill (follow the phases in order)."
color: blue
---

# PR Creation / Update Skill

> **Model:** when run as a subagent, prefer `model: sonnet`.

Create or update a GitHub pull request with a thorough summary, requirements context, and verification steps. If a PR already exists for the current branch, it will be updated in place rather than creating a duplicate.

## Supporting Files

- **PR body template** — the structure and format to follow for the PR description: [pr-body-template.md](pr-body-template.md)

## Core Rule

**Run all phases to completion without stopping.** This skill must proceed through every phase (1 through 7) in a single invocation. Do not return control to the user between phases unless a phase explicitly requires user input (e.g., asking for a reason). After any subagent completes, immediately continue to the next phase.

## User Authorization for Force-Push-with-Lease

> **User authorization for force-push-with-lease.** Running `/facto:pr` constitutes user pre-authorization for `git push --force-with-lease` on the current branch when `facto:commit-or-amend` has rewritten history. The user has reviewed this authorization and accepts it by invoking this skill. `--force-with-lease` (never bare `--force`) preserves the safety net: it refuses to push if the remote moved unexpectedly.

---

## Input

You should have or be given:
- A stack of commits to include in the PR
- Requirements or goals for the changes
- Optionally: product requirements docs, design docs, or ticket links
- Optionally: context on technical choices made (new libraries, APIs, services, patterns — what was chosen, what alternatives were considered, and why)

If a caller already supplied the base ref, the reason for the change, a one-line summary, or the PR number, use those and skip re-deriving them. When run standalone, derive everything yourself from the Phase 1 inspection below — never depend on caller-passed context.

---

## Phase 1: Gather Context

Gather all branch state in **one** command — each separate call re-bills the full cached context, so batch them:
```bash
git branch --show-current; echo '---LOG---'; git log main..HEAD --oneline; echo '---STAT---'; \
git diff main...HEAD --stat; echo '---STATUS---'; git status --porcelain; echo '---REMOTE---'; \
git diff @{u}..HEAD --quiet 2>/dev/null; echo "remote_uptodate=$?"
```
This returns the branch name, the commits going into the PR, the changed files, the working-tree state, and whether the remote is already up to date. `remote_uptodate=0` means the remote matches HEAD (no diff); any non-zero value — including `128` when the branch has no upstream yet — means there is something to push, so proceed.

If the working tree is not clean (staged or unstaged changes exist), invoke `/facto:commit-or-amend` directly via the Skill tool (in-context) — not in a subagent — with the base ref (`main`) and any relevant context, then continue — do not stop. This preserves its full fixup/attribution behavior. (If a direct Skill call ever stops `facto:pr` mid-procedure, inline `facto:commit-or-amend`'s attribution logic here instead — never sacrifice fixup fidelity.)

If the remote is up to date (`remote_uptodate=0`) and the working tree was clean, there are no new changes to reflect — report "Nothing new to put in a PR" and stop.

---

## Phase 2: Determine the Branch

- If you are already on a non-main branch (e.g. `feat/foo`, `fix/bar`), use it as the PR branch — no need to ask.
- If you are on `main` (or `master`), **never ask the developer for a branch name**. Either exit early or derive a name and create the branch yourself.

  1. Check whether there is anything to PR (one command):
     ```bash
     echo "ahead=$(git rev-list main..HEAD --count)"; git status --porcelain
     ```
     If `ahead` is `0` AND `git status --porcelain` is empty, there is nothing to PR — exit with: `Nothing to PR — working tree clean and no commits ahead of main. Make changes first.`

  2. Otherwise, **derive a branch name** from the commits / working tree:
     - **Prefix** — use the conventional-commit type of the first commit ahead of main (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, etc.). If the first commit subject is not in conventional-commit form, default to `chore/`.
     - **Slug** — derive a short kebab-case description (3–5 words) from common keywords across the commit subjects ahead of main. If no commits exist yet, slugify from the staged/unstaged file paths or a short summary of the working-tree diff.
     - Example: commits `feat(auth): add X` + `feat(auth): tweak Y` → `feat/auth-add-x-and-tweak-y`.

  3. Create and switch to the branch, then continue:
     ```bash
     git checkout -b <derived-name>
     ```

---

## Phase 3: Clarify the Reason for the Change (if not already known)

The PR body must include why this change is being made. If you don't already know it from the conversation context or provided requirements, ask the user before proceeding:

> "What's the reason for this change? I want to include it in the PR description."

---

## Phase 4: Capture Screenshots of Visual Changes

This phase runs after the reason is known and before the push, so any captured screenshots are committed on the branch and can be referenced in the PR body (Phase 6). The whole phase is **autonomous** — never ask the developer.

Make the cheap visual/not-visual judgment (4a) yourself. If the change is visual, delegate the capture-and-commit work (4b–4f) to a **subagent** (Agent tool) so the heavy image tokens stay out of this skill's context. The subagent returns **only** the list of committed screenshot paths and their labels (or, on failure, the 4g reason) — never the images themselves.

### 4a. Judge whether the change is visual

Decide, **on your own judgment**, whether the changes in this PR could plausibly affect the UI/UX that a person sees or interacts with. Do not rely on any checklist, file-extension list, or heuristic — reason about what the change actually does. If the change could not affect the UI/UX, **skip the rest of this phase** (no Screenshots section will be added to the PR body).

### 4b. Resolve the screenshots directory

```bash
SHOTS_DIR="$(facto-helper.sh task-dir)/screenshots"
```
If `facto-helper.sh task-dir` fails (not in a task worktree / on a feature branch), resolve it with a short kebab-case slug: `SHOTS_DIR="$(facto-helper.sh task-dir "<slug>")/screenshots"`. Then `mkdir -p "$SHOTS_DIR"`.

### 4c. Clean up stale screenshots (re-runs / iterations)

If `$SHOTS_DIR` already contains screenshots from a previous run, the current change may no longer match them. Remove the stale ones before capturing fresh ones so the directory always reflects the current app:
```bash
git rm -q "$SHOTS_DIR"/* 2>/dev/null || true
```

### 4d. Bring up the app and capture the after-state

Capture every distinct surface the change affects (no cap). Determine how to run THIS project and capture it, in this order of preference:
- A **project-specific run skill** or documented run instructions, if the project has one.
- The built-in **`run`** / **`verify`** skills.
- For web UIs: **Playwright MCP** — `browser_navigate` to the running app, then `browser_take_screenshot`.
- For native mobile: boot or attach an **emulator/simulator**, launch the app, navigate to the affected screen(s), and capture.

Save each capture into `$SHOTS_DIR` with a descriptive, labeled filename, e.g. `dashboard-after.png`.

### 4e. Capture the before-state (best-effort)

When the change **modifies an existing screen** (not a brand-new one) and the base version is cheaply runnable, capture the matching "before":
- Create a throwaway worktree at the merge-base: `git worktree add <tmp> "$(git merge-base main HEAD)"`.
- Run that version, capture the same surface(s) into `$SHOTS_DIR` as `*-before.png`.
- Remove the worktree afterward: `git worktree remove <tmp> --force`.

For brand-new screens, capture after-only. If running the base version is impractical (expensive rebuild, missing services), skip the before-state and note it — do not block on it.

### 4f. Commit the screenshots

Still inside the capture subagent, commit the screenshots (it may invoke `/facto:commit-or-amend` via the Skill tool — that is safe here, since the call is contained within the subagent). Stage **only** `$SHOTS_DIR` — never `git add -A`. Use a commit message like `chore: add screenshots for <task-slug>`. This commit lands before the next phase pushes the branch.

### 4g. If capture is not possible

If the change is visual but no viable way to run the app and capture a screenshot exists, capture nothing and record the specific reason (e.g. "no emulator available", "app build failed"). The Create/Update PR phase will emit the **placeholder** form of the Screenshots section with that reason instead of a directory pointer. Capture failures **warn and continue** — they must not abort the PR.

> **Never wrap `git` in `bash -c '...'` or any shell wrapper** in this phase either — always invoke the literal command.

---

## Phase 5: Push the Branch

Determine which of three cases applies from a single check, then run the matching push command:
```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null \
  && echo "ahead=$(git rev-list --count @{u}..HEAD) behind=$(git rev-list --count HEAD..@{u})" \
  || echo "no-upstream"
```

- **Case A — No upstream** (`no-upstream`): push and set upstream.
  ```bash
  git push -u origin <branch-name>
  ```

- **Case B or C — Has upstream**: use the `ahead`/`behind` counts to choose the push.

  - **Case B — `behind == 0`** (local fast-forwards remote, no divergence): a plain push will succeed.
    ```bash
    git push
    ```

  - **Case C — `ahead > 0` AND `behind > 0`** (history diverged after a `facto:commit-or-amend` rewrite): use `--force-with-lease`. The user has pre-authorized this via the "User Authorization for Force-Push-with-Lease" section above. Never use bare `--force`.
    ```bash
    git push --force-with-lease
    ```

> **Never wrap `git push` in `bash -c '...'` or any shell wrapper** — this triggers the auto-mode classifier's bypass-detection and hardens its stance for the session. Always invoke the literal command.

---

## Phase 6: Create or Update the PR

First, check if a PR already exists for the current branch:
```bash
gh pr view --json number,url,state 2>/dev/null
```

- **If a PR exists and its state is `OPEN`:** update it using the targeted-edit process below.
- **If a PR exists and its state is `MERGED`:** ignore it and create a new one with `gh pr create` — the previous PR is no longer active.
- **If a PR exists and its state is `CLOSED`:** ask the user what they want to do — reopen the existing PR (`gh pr reopen <number>`), create a new one, or stop.
- **If no PR exists:** create one with `gh pr create` using the body structure below, plus the "Active Issue link + Status write" section that follows.

### Updating an existing open PR

Never regenerate the body from scratch — the user may have made manual edits (new sections, screenshots, Loom links, reviewer notes, rewordings) that a wholesale replacement would destroy.

Do this in a single pass — fetch the body once, edit once, and do not re-read it afterward to verify:

1. Fetch the current body **once**: `gh pr view <number> --json title,body`
2. Treat it as the source of truth. Apply the minimum set of edits so it reflects the current branch state:
   - Stale info → correct in place
   - New info → add to the most appropriate existing section
   - Info no longer true → remove or revise that specific sentence/bullet
3. Leave everything else verbatim — including user-added sections and inline additions. If unsure whether something is stale, keep it.
   - **Screenshots section (targeted edit):** Treat `## Screenshots` like any other section under the never-regenerate rule. If Phase 4 produced screenshots and the body has no Screenshots section, add one (captured form). If a Screenshots section already exists, refresh only its directory pointer and file list to match the currently committed screenshots. If the change is non-visual, leave the body's Screenshots handling untouched. Preserve all other manual edits verbatim.
4. Apply with a single `gh pr edit <number> --body "..."`. Do not fetch the body again to confirm.

**Update path — explicit no-write rule:** Do **not** insert or modify any `Resolves #N` line on the update path, and do **not** set Project Status. Update-path Status changes are handled by other automation (or by the developer), not here. This preserves the "never regenerate the body" invariant against manual edits.

### Active Issue link + Status write (first creation only)

Before invoking `gh pr create`, check whether the host repo has an active Issue:

```bash
if facto-helper.sh tracker.exists 2>/dev/null; then
  ISSUE_NUMBER="$(facto-helper.sh current-issue 2>/dev/null)" || ISSUE_NUMBER=""
fi
```

If `$ISSUE_NUMBER` is set, build the PR-link line by substituting `{issue}` into `facto-helper.sh tracker.field pr_link_format` (default `Resolves #{issue}` → `Resolves #123`) and insert it into the body as the **second line of the `## Summary` section** (immediately after the one-line summary). Example body fragment:

```
## Summary
<One-line summary>

Resolves #123

## Reason for change
…
```

After `gh pr create` succeeds and the PR URL is captured, set the *issue*'s Project Status → `status_values.in_review` using the same inline `gh project item-edit` pattern as `facto:implement`'s fallback (see that skill for the canonical shell snippet). Status-write failures **warn and continue** — PR creation is the deliverable.

If `facto-helper.sh tracker.exists` fails or `facto-helper.sh current-issue` returns nothing, skip both the link insertion and the Status write — proceed with the current behavior.

### Body structure for new PRs

Build the body from the structure in [pr-body-template.md](pr-body-template.md) — it defines every section (Summary, Reason for change, What changed, Screenshots, Notable technical choices, Verification) and the footer. The facto:pr-specific rules the template does not cover:

- **Summary → Active Issue link:** insert the `Resolves #N` line per "Active Issue link + Status write" above.
- **Screenshots:** fill per "Filling the Screenshots section" below.
- **Verification → Manual:** each step must describe something that could fail even if every file in the diff is exactly as shown — running a command, starting a dev server and exercising a path, checking a CI run's outcome, parsing a config with a real tool. Do NOT include steps that merely verify file existence, content presence, or line deletion — the diff already proves those.

  **Doc-only escape hatch.** For documentation-only, comment-only, gitignore, or pure-config PRs with no executable behavior, replace the numbered list with: `N/A — documentation-only change; diff review is sufficient.` Do not fabricate steps.

  | Bad (rejected) | Good (accepted) |
  |---|---|
  | `confirm file X exists` | `npx playwright test foo.spec.ts` |
  | `verify section Y is present` | `start dev server, click X, expect Y` |
  | `confirm line Z deleted` | `gh run view <id>` and confirm new job passed |
  | `ls path/*.md to confirm files added` | `act --list` to confirm YAML parses |

### Filling the Screenshots section

Fill the `## Screenshots` section using the outcome of **Phase 4 (Capture Screenshots)**:

- **Capture succeeded** → use the captured (pointer) form. Build the directory link from the repo and branch:
  ```bash
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  BRANCH="$(git branch --show-current)"
  REL="$(realpath --relative-to="$(git rev-parse --show-toplevel)" "$SHOTS_DIR")"
  # Directory link: https://github.com/$REPO_SLUG/tree/$BRANCH/$REL
  ```
  List one bullet per committed screenshot file, labeled by screen/state and before/after where applicable.
- **Capture failed (Phase 4g)** → use the placeholder form: keep the unchecked `- [ ] Attach screenshots before merging` item and fill in the specific reason recorded in Phase 4g.
- **Non-visual change** (Phase 4 was skipped) → omit the `## Screenshots` section entirely.

---

## Phase 7: Summary

Report to the user:
- Whether the PR was **created** or **updated**
- The PR URL
- The PR title
- A one-line summary of what the PR covers
- If `/facto:commit-or-amend` was run in Phase 1, list what happened — one line per commit that was added or amended, e.g.:
  - `amended into "Add webhook retry"` — folded in error handling fix
  - `new commit "Fix lint errors"` — addressed eslint warnings

---

## Guidelines

- Keep the PR title short and in conventional commit format (e.g. `feat:`, `fix:`, `refactor:`)
- Verification steps must be specific enough that someone unfamiliar with the change can follow them
- End the PR body with: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- On PR updates, never regenerate the body from scratch. Treat the existing body as the source of truth and apply targeted edits — correct stale info, add genuinely new info, leave everything else alone.
