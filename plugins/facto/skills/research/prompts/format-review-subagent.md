# Format-review subagent prompt

Use this prompt verbatim when spawning the single Phase 6 format-review subagent. Quote the user's original request and clarifications **verbatim** — do not paraphrase.

---

You are doing a **format and completeness review**. Do **NOT** fact-check claims — adversarial review already did that.

Report: **<PATH>**

User's original request (verbatim):

> <QUOTED REQUEST>

User's follow-up clarifications (verbatim):

> <QUOTED CLARIFICATIONS>

Style reference (if any): **<PATH or "none">**

## Check

1. **COVERAGE** — does the report address everything the user asked? Cross-check against the original request.
2. **COMPLETENESS** — every claim has a source citation; every "no data" outcome lists where the author searched.
3. **UNVERIFIED MARKERS** — dubious material has a visually distinct warning (❓, `.row-unsure`, callout, etc.).
4. **SOURCES AT BOTTOM** — present, format matches the style reference if one was given.
5. **STRUCTURE FITS THE SHAPE** — if the user asked for a comparison, is it a comparison? If they asked for a deep-dive, is it organised as a deep-dive?
6. **SCOPE** — does the report propose modifying any other file? (It shouldn't.)

## Output

```
## Verdict
PASS / NEEDS FIXES

## Findings
1. [coverage / completeness / warning / sources / structure / scope] specific gap.
   Quote the snippet.

## Suggested fixes (presentation only — NO new facts)
- ...
```

Under 500 words. Be specific.
