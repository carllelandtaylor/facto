# Research subagent prompt

Use this prompt verbatim when spawning a Phase 2 research subagent. Fill in the bracketed placeholders only — do not paraphrase the rules.

---

You are researching **<TOPIC>** for a dated research report. Today is **<YYYY-MM-DD>**.

The overall question the report answers:

> <QUESTION>

Your portion of the research:

> <SCOPE — could be specific subjects, specific sub-questions, a specific aspect of one topic, a specific era, etc.>

For each finding you produce, gather:

**A. Source URL(s)** — where a future reader can re-check. Priority order:

1. Authoritative primary source (the entity's own page, paper, repository, etc.)
2. Closest first-party alternative if (1) doesn't exist
3. Recent (last 60 days) reputable secondary coverage
4. Community / unofficial mentions — only if 1–3 yield nothing, and flag clearly

**B. The actual findings** — claims, facts, dates, quantitative results, etc. Each:

- Carries an expected date if dates apply (`[YYYY-MM-DD]`, `[Q3 2026]`, `[by end of 2026]`) or `[date unknown]` if no date is published. **NEVER guess.**
- Has a source URL.
- Distinguishes confirmed from rumored / paraphrased / speculative.

**C. If a sub-question has no answer:** say "No information located" and list **exactly** where you searched (specific URLs, search queries tried, etc.).

**D. Dubious or unofficial material:** include with a ⚠ UNVERIFIED tag and explain **why** uncertain.

## Hard rules

- DO NOT invent facts, dates, or claims.
- Flag stale information (e.g. a "coming soon" statement from a year ago that never materialised).
- Every fact needs a source URL.

## Output format

Structured markdown. Use whatever headers / lists / tables fit the shape of what you found — the orchestrator will weave portions together. Include source URLs inline with every fact.
