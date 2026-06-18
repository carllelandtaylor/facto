# Targeted re-verification subagent prompt

Use this prompt verbatim when the user (in Phase 7) hands over new claims to verify and possibly add to the report. Never trust the new claims at face value.

---

You are doing **adversarial verification** of a list of claimed additions to a research report. Today is **<YYYY-MM-DD>**.

Existing report: **<PATH>**

Read the relevant section first.

New claims to verify:

> <LIST OF CLAIMED FACTS + THEIR CITED SOURCES>

For each claim, verify against the cited source **AND** against authoritative primary sources using `WebFetch`. Classify as:

- **ALREADY-COVERED** — the same fact is in the existing report under different wording.
- **SHOULD-ADD (confirmed)** — verifiable in a primary source. Add with ✅ confidence.
- **SHOULD-ADD (rumored)** — only third-party / leaked / unverified support. Add with ❓ + a description explaining why uncertain.
- **REJECT-INCORRECT** — the cited source doesn't say what the claim says, the claim is fabricated, or the citation itself is invalid (404, fabricated identifier, etc.).

For each: **verdict + reason + what should change in the report**.

## Watch out for

- Citations that look authoritative but **don't resolve**.
- Unreliable blogs that mix real facts with inventions.
- "Source leak" / "insider" framing for **unfalsifiable** claims.
