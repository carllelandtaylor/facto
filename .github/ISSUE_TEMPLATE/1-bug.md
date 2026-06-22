---
name: Bug
about: Something not working right (bug, regression, slowness, drift).
title: "BUG: <one-line statement of the problem>"
labels: []
---

<!--
Title rule: state the problem, not a proposed fix — the same problem may attract several fix attempts and the title must outlive them.
    ✅ BUG: facto:pr subagent exits after commit, skipping push and PR update
    ❌ Add re-read anchors at facto:implement phase boundaries (that's the fix)
-->

## What's happening
<One paragraph — the event itself, anchored in time.>

### Impact
<Concrete effect — time lost, quality miss, regression, etc.>

## Repro Steps
<Numbered steps to reproduce. Omit this section, Observed Result, and Expected Result if N/A — e.g. enhancement requests or external research findings with no executable repro.>

1. <first step>
2. <second step>

### Observed Result
<!--
What actually happens when the steps above are run — the observable behavior a developer running the repro sees. Not the internal mechanism that produced it.
    ✅ Expected Result is phrased as an implementation approach: "facto-dev:think reads PR links from `closedByPullRequestsReferences`..."
    ❌ The `closedByPullRequestsReferences` field is being ignored by the GraphQL caller
-->

### Expected Result
<!--
What should happen instead — the observable outcome a developer would see if the bug were fixed, not the implementation mechanism for achieving it.
    ✅ facto-dev:think can report 'Fix in flight: PR #N (merged YYYY-MM-DD)' in its per-Issue reasoning
    ❌ facto-dev:think reads PR links from `closedByPullRequestsReferences` (available via GraphQL)
-->

## Root cause(s)
- <First root cause — what an improvement could change.>
- <Second root cause, if applicable.>
