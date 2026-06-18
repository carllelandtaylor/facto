---
name: commit-or-amend
description: "TRIGGER when: about to commit, amend, fixup, or fold a working-tree change into the commit stack — even tiny ones. NEVER run `git commit` or `git commit --amend` directly. Procedure skill (follow the phases in order)."
color: green
---

# Commit or Amend Skill

> **Model:** when run as a subagent, prefer `model: sonnet`.

Fold working tree changes into the appropriate existing commits to keep the commit history clean. Changes that don't belong to any existing commit get their own new commit.

## Supporting Files

- **Commit message template** — format and examples for new commit messages: [commit-message-template.md](commit-message-template.md)

## Input

You need:
- **Base ref** — the commit to compare against (e.g., `main`, a specific SHA). If not provided, ask the user or infer from context (e.g., the merge base with `main`).
- **Commit message** (for net-new commits) — optionally provided by the caller. If not provided, write one yourself.
- **Context** (optional) — why the changes exist, what new libraries/APIs/services are being used and why, and how to verify the changes. Used to write commit message bodies.

---

## Phase 1: Assess the Working Tree

Run these commands in parallel:
- `git status` — see what's staged and unstaged
- `git log <base>..HEAD --oneline` — see the existing commits in the stack

If the working tree is clean (no staged or unstaged changes), report "Nothing to commit" and stop.

---

## Phase 2: Stage Changes

If there are unstaged changes, review them and stage the relevant files. Do not blindly `git add -A` — only stage files that are intentional changes, not generated files, build artifacts, or secrets.

---

## Phase 3: Attribute Changes to Commits

For each changed file (or hunk, if a file has changes belonging to different commits), determine where it belongs:

1. **Most recent commit** — the change extends or fixes work done in HEAD
2. **An earlier commit** — the change extends or fixes work done in a specific prior commit in the stack
3. **Net-new** — the change isn't related to any existing commit and needs its own commit

Use `git log <base>..HEAD -- <file>` and the commit messages/diffs to determine which commit each change belongs to.

---

## Phase 4: Apply

Process changes in this order: earlier commits first, then most recent, then net-new.

### For changes belonging to the most recent commit:
```bash
git add <files>
git commit --amend --no-edit
```

### For changes belonging to an earlier commit:
```bash
git add <files>
git commit --fixup=<target-commit-hash>
GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <base>
```

If multiple fixes target different earlier commits, create all the fixup commits first, then run a single rebase to squash them all at once.

### For net-new changes:
```bash
git add <files>
git commit -m "<appropriate commit message>"
```

Follow the [commit message template](commit-message-template.md). Every commit message body must include:
- **Context:** why this change exists, and if new libraries, APIs, or services are introduced, what they are and why they were chosen
- **Verification** (when meaningful)**:** split into `Automated:` (exact commands) and `Manual:` (numbered steps with expected results). Omit the Verification section entirely for changes that are trivially correct — e.g., documentation, comments, config that doesn't affect behavior.

Keep it to 2–5 lines each — enough for a developer reading `git log` to understand the change without reading the diff.

---

## Phase 5: Verify

Run `git log <base>..HEAD --oneline` and confirm the commit history looks correct. Report what was done:
- Which files were amended into which commits
- Any new commits created
- The final commit stack
