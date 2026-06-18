# Implementation Plan: [Feature/Change Name]

**Requirements and specs:** [Requirements/designs this plan was derived from]
**Created:** [Date]

---

## Requirements Summary

- [Bullet point summary of what needs to be built]
- [...]

## Key Decisions

| Decision | Options Considered | Chosen | Rationale |
|----------|-------------------|--------|-----------|
| [What was decided] | [Option A, Option B, ...] | [Which one] | [Why] |

## Notable Technical Choices

[Summarize any new libraries, APIs, services, patterns, or methods being introduced. For each one, briefly state what it is and why it was chosen over alternatives.]

- **[Library/API/pattern name]** — [What it is and why it was chosen]
- [...]

---

## Commits

1. `type: short message` — [What this commit does and why]
2. `type: short message` — [What this commit does and why]
3. [...]

---

## Verification Coverage

| Domain | Expertise | PRD criterion | Verification |
|---|---|---|---|
| [domain] | [high/medium/low] | [criterion text] | [automated / manual-described / blocked-no-tooling] |

## Risks

- [Any rows from the Verification Coverage table with `low` expertise or `blocked-no-tooling` verification, plus any other risks surfaced during analysis]

## Test Plan

- [ ] All project tests pass: `[actual test command]`
- [ ] Linter passes: `[actual lint command]`
- [ ] Type checker passes: `[actual typecheck command]`
- [ ] Build succeeds: `[actual build command]`
- [ ] Manual verification:
  - [ ] [Specific end-to-end check 1]
  - [ ] [Specific end-to-end check 2]
  - [ ] [...]

## Flags

- [ ] [Any issues to flag to the developer — e.g. no test framework set up, ambiguities in requirements, etc.]
