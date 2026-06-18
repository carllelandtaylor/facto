# PR Body Template

```
## Summary
[One-line summary: what changed and why]

## Reason for change
[Why this change is needed. Could be a user-facing problem being solved,
a technical problem or limitation being addressed, an opportunity being
taken advantage of, a strategic decision, etc. Be specific about the
before/after if relevant.]

[If product requirements, design docs, or tickets were provided,
reference them here — summarize the key requirements this PR addresses
and cite specific requirement IDs or section names if available.]

## What changed
[Describe the code changes. Call out any non-obvious technical decisions
— alternative approaches that were considered, tradeoffs made, and why
this approach was chosen over others. If the implementation was
straightforward, keep this brief.]

## Screenshots
[Visual/UI changes only. OMIT this entire section for non-visual changes.]

[Captured form — when screenshots were captured and committed to the branch:]
Screenshots for this change are committed under `[relative/path/to/task-dir]/screenshots/`.
View them in the **Files changed** tab, or browse the directory:
[https://github.com/OWNER/REPO/tree/BRANCH/relative/path/to/task-dir/screenshots]

- `[screen-name]-after.png` — [Screen/state] (after)
- `[screen-name]-before.png` — [Screen/state] (before)
- [one bullet per committed file, labeled by screen/state and before/after where applicable]

[Placeholder form — when the change is visual but capture was not possible:]
> ⚠️ Screenshots could not be captured automatically: [reason].
- [ ] Attach screenshots before merging

## Notable technical choices
[For each new library, API, service, or pattern introduced in this PR.
Omit this section if nothing new was introduced.]

### [Library/API/pattern name]
- **What it is:** [What it does and what problem it solves]
- **Why it was chosen:** [Why this over alternatives]
- **Tradeoffs:** [Any downsides or risks accepted]
- **Alternatives considered:**
  - **[Alternative 1]** — [Why it wasn't picked]
  - **[Alternative 2]** — [Why it wasn't picked]

### [Next choice...]
[Same structure as above]

## Verification

**Automated:**
[Exact commands to run with expected outcomes]
- `[test command]` — should pass with N tests
- `[lint command]` — should report no errors
- `[build command]` — should complete successfully

**Manual:**
[Numbered list of specific steps to manually verify the change.
Include exact commands to run (e.g. start a dev server, open a
specific URL, run a seed script), what to do, and expected results.]
1. Run `[command]` to [set up / start / etc.]
2. [Do X]
3. Verify [expected result]

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## PR Title Format

Use conventional commit format, under 70 characters:
- `feat: add webhook retry with exponential backoff`
- `fix: prevent duplicate form submissions on slow networks`
- `refactor: extract shared validation logic into middleware`
- `chore: upgrade React to v19`
