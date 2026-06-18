---
name: observe
description: "Create or update a GitHub Issue capturing a Facto improvement observation. Routes the observation to a matching open or recently-closed Issue, or opens a new one. May close Issues autonomously when positive evidence is strong. Invoke with /facto-dev:observe. Procedure skill (follow the phases in order)."
disable-model-invocation: true
color: yellow
---

# Facto Improvement: Observe

> **Model:** when run as a subagent, prefer `model: sonnet`.

This skill runs the phases in `plugins/facto/skills/observe/SKILL.md` with the overrides below. Read that file first, then run its phases, applying these overrides.

## Overrides

1. **Tracker config source.** Resolve `FACTO_REPO` from the `FACTO_REPO` env var, falling back to this SKILL.md's path:
   ```bash
   FACTO_REPO="${FACTO_REPO:-$(cd "$(dirname "$(readlink -f ~/.claude/skills/facto-dev/skills/observe/SKILL.md)")"/../../../.. && pwd)}"
   test -f "$FACTO_REPO/.facto/settings.json" || { echo "ERROR: Facto repo not found at '$FACTO_REPO'. Set FACTO_REPO to your Facto checkout (run /facto-dev:setup-facto-dev once)." >&2; exit 1; }
   ```
   Read every tracker field via `facto-helper.sh --root "$FACTO_REPO" tracker.field <path>`, regardless of host repo.

2. **REPO_SLUG.** Use Facto's repo slug (from Facto's `.facto/settings.json` resolved via the `--root` lookup above), not the host repo's. Every `gh -R "$REPO_SLUG"` call targets Facto's Issue tracker.

3. **OKRs path.** Hardcoded to `$FACTO_REPO/OKRS.md`. Ignore any `okrs_path` in the host repo's `.facto/settings.json`. Treat `OKRS_AVAILABLE=true` (the file is guaranteed to exist in the Facto repo).

4. **Issue templates path.** Always `$FACTO_REPO/.github/ISSUE_TEMPLATE/{1-bug,2-feature,3-chore}.md`, regardless of host repo. The fallback section structure embedded in `facto:observe` is never used by `facto-dev:observe`.

5. **Provenance prefix.** Use `facto-dev:observe says:` on every body, comment, and footer line. The footer remains:
   `_facto-dev:observe says: filed YYYY-MM-DD from source=<source>; area=<related-area or n/a>; run=<related-run or n/a>._`

Otherwise, follow `facto:observe` exactly.
