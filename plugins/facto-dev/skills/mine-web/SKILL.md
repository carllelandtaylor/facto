---
name: mine-web
description: "Scan curated AI-factory topics on the open web for recent advances and best practices. Files concrete actionable findings as factory improvement observations (source: internet-research) and writes a dated reading-list HTML to research/. Invoke with /facto-dev:mine-web. Procedure skill (follow the phases in order)."
disable-model-invocation: true
color: yellow
---

# Factory Improvement: Mine Web for Observations

> **Model:** when run as a subagent, prefer `model: sonnet`.

Scan the open web for recent articles, posts, and documentation that are worth filing as factory improvement observations. An internet finding is worth filing when it falls into one of:

1. An open Issue with Status **In review** or **In test** — does the finding support or refute the fix attempt in flight (PR open or just merged)?
2. An open Issue with Status **Backlog** or **In progress** — does the finding accumulate evidence for or against the underlying problem?
3. **A finding that contradicts an approach the factory is currently taking toward an OKR, or surfaces a known industry failure mode that would prevent the factory from meeting an OKR's key result.** Findings that merely affirm "industry is also doing X like we are" are not filed — they're routine reassurance, not actionable signal. Generic industry trends without a tie to a current factory objective do not qualify.

**Note on positive vs negative observations.** External findings that affirm an OKR is being met by industry are not filed — they're routine reassurance, not actionable signal. Positive findings are filed only when they relate to a specific open Issue (criteria 1–2), where they drive closure of that Issue. Criterion 3 therefore covers only findings that contradict the factory's approach or surface industry failure modes — not findings that affirm.

Findings that fall into none of those — recycled summaries, promotional content, paywalled pieces with no extractable claim, or results already cited within the dedupe window — are dropped. The goal is to keep memory dense, not to log everything.

Unlike `facto-dev:mine-logs`, this skill does not ask for developer approval before writing. It files observations and writes the research HTML directly, then surfaces only items it's uncertain about in the final report so the developer can review, edit, or revert those specifically. This trades a small risk of false-positive memory for substantially less interruption, in line with the factory principle that the system does most work independently.

For the full memory model, see `DEVELOPMENT.md` §3.4 in the factory repo.

## Setup: Resolve the Factory Repo + GitHub Repo + `gh` auth

```bash
FACTORY_REPO="${FACTO_REPO:-$(cd "$(dirname "$(readlink -f ~/.claude/skills/facto-dev/skills/mine-web/SKILL.md)")"/../../../.. && pwd)}"
test -f "$FACTORY_REPO/.facto/settings.json" || { echo "ERROR: factory repo not found at '$FACTORY_REPO'. Set FACTO_REPO to your factory checkout (run /facto-dev:setup-facto-dev once)." >&2; exit 1; }
REPO_SLUG="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field repo)"
test -n "$REPO_SLUG" || { echo "ERROR: could not derive REPO_SLUG from $FACTORY_REPO" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh CLI is not authenticated. Run 'gh auth login' and re-try." >&2; exit 1; }
```

### Resolve the GitHub Project + Status field

```bash
PROJECT_OWNER="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field project.owner)"
PROJECT_NUMBER="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field project.number)"
PROJECT_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field project.name)"
STATUS_FIELD_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field status_field)"
STATUS_BACKLOG_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field status_values.backlog)"
STATUS_IN_PROGRESS_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field status_values.in_progress)"
STATUS_IN_REVIEW_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field status_values.in_review)"
STATUS_IN_TEST_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field status_values.in_test)"
STATUS_DONE_NAME="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field status_values.done)"
IGNORE_LABELS_JSON="$(facto-helper.sh --root "$FACTORY_REPO" tracker.field labels.ignore)"

PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json | jq -r .id)" \
  || { echo "ERROR: cannot read project $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
test -n "$PROJECT_ID" || { echo "ERROR: project ID is empty for $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
```

Rationale: tracker identifiers (project owner/number/name, Status field name, Status option names, ignored labels) come from `.facto/settings.json` in the factory repo via `bin/facto-helper.sh`. The `--root "$FACTORY_REPO"` flag passed to each `facto-helper.sh` call locks the config lookup to the factory's `.facto/settings.json` regardless of which repo this skill is invoked from. This skill never writes Status, so the Status field option IDs (`STATUS_*_ID`) are not needed and are not resolved. `PROJECT_ID` is resolved here because it is needed if the fallback `gh project item-list` path is taken in Phase 1. Status option names are compared as strings (e.g. checking whether `.status.name` equals `$STATUS_IN_REVIEW_NAME`) — no IDs required. All Status writes go through facto-dev:observe.

---

## Progress Tracking

Before starting, use `TaskCreate` to create one task per phase below — the phase title as `subject` and a present-continuous label as `activeForm`. All tasks start `pending`. At the start of each `## Phase N` section, use `TaskUpdate` to set its task to `in_progress`; set it to `completed` when that phase is done.

## Phase 1: Load Memory Context (open Issues + OKRs + URL dedupe set)

One bulk `gh issue list` for the matching corpus, plus a read of OKRs, plus a dedupe-set fetch from Issue comments:

```bash
gh -R "$REPO_SLUG" issue list \
  --state open \
  --json number,title,body,labels,comments,updatedAt,projectItems \
  --limit 200
```

Paginate if 200 records returned. Filter out any Issue carrying a label in `$IGNORE_LABELS_JSON` (e.g. `test-fi`):

```bash
jq --argjson ignore "$IGNORE_LABELS_JSON" '[.[] | select([.labels[].name] | any(. as $l | $ignore | index($l)) | not)]'
```

For each candidate Issue, extract its Status from the `projectItems` array (entry with `title == $PROJECT_NAME`) by reading `.status.name`. The actual JSON shape is `{"projectItems":[{"status":{"optionId":"…","name":"Backlog"},"title":"<project name>"}]}` — `status` is an object, so the column name lives at `.status.name`. Example jq: `.projectItems[] | select(.title == $name) | .status.name` (with `--arg name "$PROJECT_NAME"`). Criterion 1 keys off Status ∈ {`$STATUS_IN_REVIEW_NAME`, `$STATUS_IN_TEST_NAME`}; criterion 2 keys off Status ∈ {`$STATUS_BACKLOG_NAME`, `$STATUS_IN_PROGRESS_NAME`}. Issues with `null` `.status`, or with no entry for the configured project (not yet on the project), fall under criterion 2 by default.

**Working inline filter.** To annotate every Issue with its Status in one pass, collect matches into an array and take `first`, then fall back to `null` — never place `//` directly after a parenthesized expression inside an object value, jq's parser rejects it (`syntax error, unexpected //, expecting '}'`):

```bash
jq --arg name "$PROJECT_NAME" '[.[] | . + {projectStatus: (([.projectItems[] | select(.title == $name) | .status.name] | first) // null)}]'
```

Fallback if `projectItems` doesn't expose field values on a given `gh` version: `gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 200` and merge by `content.number`.

Read OKRs at `$FACTORY_REPO/OKRS.md` — full file: each objective's slug and objective-level status dot (🟢 / 🟡 / 🔴 / ❓) from its `## <slug> <dot>` header, its `**Description:**`, and its markdown table of KRs (Target column + per-row Current status dots; survey-measured KRs flagged with 📋). Used to derive OKR-targeted queries (Phase 3c) and to apply the filing bar (Phase 5).

**URL dedupe set.** Collect URLs already cited in any open or recently-closed Issue (body or comments) within the last 60 days:

```bash
gh -R "$REPO_SLUG" issue list \
  --state all \
  --search "is:issue updated:>=$(date -d '60 days ago' +%Y-%m-%d)" \
  --json body,comments --limit 200 \
  | jq -r '.[] | (.body // ""), (.comments[]?.body? // "")' \
  | grep -oE 'https?://[^ )>"]+'
```

A URL is treated as a duplicate — and skipped before WebFetch — only if it was cited within the last **60 days**. The `EVERGREEN_DOMAINS` allowlist (`anthropic.com/engineering`, `code.claude.com/docs`, `cognition.ai/blog`, `platform.claude.com/cookbook`) uses a tighter dedupe window of **14 days** — these we expect to re-scan often. Evergreen visits that find no new content at Phase 4 are simply dropped, not filed.

---

## Phase 2: Compute the Recency Window

The date constraints for all queries are computed at invocation time — never hardcoded. This keeps the skill working in 2027 and beyond without edits.

```bash
MONTH_NOW="$(date -u +%Y-%m)"
MONTH_TWO_AGO="$(date -u -d '2 months ago' +%Y-%m)"
```

Use these to construct a natural-language date constraint appended to every query (e.g. `published after 2026-03`). The exact constraint text is derived from `$MONTH_TWO_AGO` when the skill runs.

---

## Phase 3: Run the Query Batch (parallel) — Common + Improvement-Targeted

Issue all queries in a single parallel batch via `WebSearch`. Do not run them sequentially.

**3a. Common topics (steady-state).** These eight standing queries cover the factory's core interest areas. Append the recency constraint from Phase 2 to each:

1. `AI coding agent harness design site:anthropic.com OR site:cognition.ai OR site:platform.claude.com`
2. `agentic coding skills system prompt design`
3. `closed-loop self-improving AI agent SWE-bench`
4. `multi-agent vs single-agent coding architecture`
5. `context engineering compaction subagent isolation`
6. `AI agent evaluation harness observability`
7. `Claude Code hooks subagents skills best practices`
8. `software factory autonomous code review pipeline`

This list is the steady-state set; whoever edits the skill can rotate items as the factory's focus shifts. No external state file — keeping it inside `SKILL.md` matches how all other fi-* skills handle config.

**3b. Issue-targeted queries (dynamic).** For each open Issue loaded in Phase 1, derive one query from its title + body (focused on the actionable root cause), phrased to find external evidence for or against the underlying problem or its proposed direction. Run these alongside the common queries in the same parallel batch. If there are more than 6 open Issues, prioritize Status `In review`, then `In test`, then most-recently-updated `Backlog` and `In progress` (most-recently-updated overall after the In-* tiers), capping at ~6 Issue queries to keep the batch bounded. If there are zero open Issues, run only the common-topic queries from 3a and skip the dynamic layer.

**3c. OKR-targeted queries (dynamic).** For each OKR loaded in Phase 1, derive one query phrased to find external evidence that would help move its key results. The slug is the natural query frame — e.g. for `independence`, search for evidence on agent autonomy and reducing mid-task interruption; for `code-quality`, search for evidence on idiomatic agent-written code and review-loop convergence. Cap the dynamic OKR layer at ~7 queries (one per current OKR). Run alongside 3a and 3b in the same parallel batch.

---

## Phase 4: Triage and Fetch

Apply the four criteria from the intro to each search result. For each surviving candidate:

- Check the URL against the dedupe set from Phase 1. Drop any URL that falls inside the dedupe window (60 days general, 14 days for `EVERGREEN_DOMAINS`).
- Drop hype pieces, recycled summaries, promotional content, and undated posts with no extractable factual claim.

For surviving candidates, issue parallel `WebFetch` calls with a prompt asking specifically for: the concrete claim or finding, who said it, when, and what action it implies for an AI coding factory. Fetch in parallel — one call per candidate URL.

If an evergreen domain fetch returns no new content since the last citation, drop it silently.

If no candidates survive triage, skip Phases 5–8 and report "No web findings worth filing this pass." in Phase 9 — file no observation, write no HTML.

---

## Phase 5: Apply the Two Bars

Internet research surfaces two kinds of useful content; the skill treats them differently.

**Filing bar — observations (memory).** A finding becomes an observation only if it does at least one of: (a) supports or refutes an open Issue (criteria 1–2), or (b) contradicts the factory's current approach toward an OKR or names an industry failure mode against an OKR (criterion 3). "Industry is moving toward X" without a tie to a current factory Issue or OKR does not become an observation. If the article only restates patterns already encoded in open Issues, do not file it. Same density bar as `facto-dev:mine-logs`.

**Opportunities bucket.** Findings with a clear actionable lesson the factory could benefit from adopting, but with no matching open Issue and no OKR-violation framing, fall into a third bucket: Opportunities. These are positive-direction findings that belong to no current Issue and no OKR failure mode. They go to the HTML (covered by the HTML bar below) and to the "Opportunities for the developer" section in the Phase 9 report — but they are **never** routed to `/facto-dev:observe`. The developer decides in their own time whether to open a new Issue, wait for more signal, or drop.

**HTML bar — research document.** Wider net. Trends, signals, and "directionally interesting" pieces that don't clear the filing bar still go into the dated research HTML so the developer sees them — they just appear without a corresponding observation. The HTML carries the broader context; the memory stays dense.

Under each theme in the HTML, actionable findings (which were also filed as observations, and are cross-linked) and trend/signal entries (HTML-only) both appear, distinguished by whether an observation filename appears in the entry.

---

## Phase 6: Cluster Into Themes

Group surviving candidates into 2–5 themes (e.g. *closed-loop validation*, *context engineering*, *multi-agent orchestration*). Themes become the H2 sections in the research HTML. A finding that spans themes goes into whichever theme is the primary driver of its actionable cause. If only one theme emerges, use a single H2 in the HTML — don't manufacture additional themes.

---

## Phase 7: Self-Confidence Check

**No developer-confirmation gate in this skill.** All candidates that clear the filing bar are filed autonomously in Phase 8. The `needs-review` tag is a report flag only — it routes the item into the Phase 9 report so the developer can re-read at their leisure, but it never pauses Phase 8.

For each candidate — filing or HTML-only — self-rate confidence and tag as `needs-review` any item where:

- The actionable cause is speculative (the article hints at it but doesn't directly support it).
- The finding contradicts an existing `accepted/` improvement (the skill would be reversing a settled decision).
- The source is a low-signal venue (anonymous blog, marketing copy, undated post) but the claim seems too good to drop.
- The mapping to a `related-skill` is a guess rather than an obvious match.
- The candidate sits on the boundary between filing-bar and HTML-only — the actionable cause exists but is weak.

Everything else proceeds straight to Phase 8 without confirmation. Items tagged `needs-review` are also written and filed — the tag just means they're called out in the Phase 9 report so the developer can re-read and adjust.

---

## Phase 8: File Observations + Write the HTML

**8a. Observations.** For each candidate that cleared the **filing bar** (criteria 1–3), spawn a parallel subagent (`model: "sonnet"`) and have it run `/facto-dev:observe` via the Skill tool in caller (non-interactive) mode, passing:

**Candidates in the Opportunities bucket skip this step entirely.** They are already in the HTML (Phase 8b) and will appear in the Phase 9 report's "Opportunities for the developer" section. Do not route them to `/facto-dev:observe`.

- Natural-language summary of the finding (what was claimed or found)
- Impact line (how it would change the factory if applied)
- The URL and a short quoted excerpt as grounding material
- `source: internet-research`
- `related-skill` if the finding maps to a specific skill
- `related-run`: omit — no specific run; the research HTML filename serves as the run-equivalent reference and goes in the Issue body or comment
- A `target-issue` hint when the candidate was matched to a specific open Issue under criteria 1–2 (biases `facto-dev:observe`'s match step without forcing it)
- The `--non-interactive` flag (or equivalent argument) so `/facto-dev:observe` writes its best draft without prompting.

**Framing rule for internet-research observations.** Observations file what the source said in *third-party voice* — describe the external party's claim, mechanism, and cited data. Do not compare to our factory in the resulting Issue body or comment.

- **Issue title (when creating new):** third-party voice. ✅ "Live-SWE-agent reaches 79.2% on SWE-bench Verified via runtime self-modification of its scaffold." ❌ "Our factory doesn't articulate the choice between gated vs runtime self-modification."
Sections are defined in `$FACTORY_REPO/.github/ISSUE_TEMPLATE/1-bug.md`. Per-section guidance specific to web-sourced findings:

- **"What's happening" section:** the claim + cited data + a short quoted excerpt from the source. Describe the *mechanism* the source attributes for why Y produces Z.
- **"Impact" section:** the magnitude of the external finding (the SWE-bench delta, the token-cost ratio, the latency, etc.) — not our factory's gap. For a positive finding, frame the magnitude in terms of what we're leaving on the table by not adopting the pattern.
- **"Repro Steps" / "Observed Result" / "Expected Result" sections:** omit entirely. External research findings have no internal repro to capture; the template's "omit if N/A" rule applies.
- **"Root cause(s)" section:** the *mechanism the source attributes* (e.g. "treating the agent's scaffold as mutable code that the agent rewrites at runtime correlates with higher SWE-bench scores"). This is the cause-of-the-result *in the world*, not in our factory.

The comparison to our factory's setup is the job of `facto-dev:think` (which has the broader context to judge whether the external pattern applies) or developer-driven labeling/commenting. Mining stays neutral.

The Issue body or comment of each filed observation must include the source URL and the research HTML filename so future passes can locate the source without re-running the web search. This is the bidirectional cross-reference: Issue ↔ HTML.

This skill does not call `gh issue` directly — always file via `/facto-dev:observe` in caller mode so matching, body/comment templates, and the `<skill-name> says: ` prefix convention stay consistent.

Subagents fire in parallel — one per candidate. **Caveat:** parallel `facto-dev:observe` runs can race on the bulk-fetch step. For ≤5 candidates this is acceptable; for larger batches, run in small sequential groups to avoid duplicate-Issue creation from two parallel runs that both decided "no match."

Wait for the 8a subagents to return their resulting Issue URLs before proceeding to 8b — the HTML's "Filed observations" section needs those URLs.

**8b. Research HTML.** Write `$FACTORY_REPO/research/YYYY-MM-DD-ai-factory-scan.html` (slug fixed unless one theme clearly dominates, in which case use a theme-specific slug). Use `date -u +%Y-%m-%d` for the date.

Copy the entire `<head>...</head>` block from `$FACTORY_REPO/research/2026-05-08-coding-factory-reading-list.html` (lines 1–127) verbatim — this includes the inline `<style>` block (lines 6–124) plus all surrounding boilerplate. Then update the `<title>` to match the new HTML's H1, and open `<body>`. Body structure:

```html
<h1>AI Software Factory Web Scan — YYYY-MM-DD</h1>
<p class="subtitle">Curated findings from this run, grouped by theme.</p>

<h2>1. <theme name> <span class="topic-blurb">…one sentence on why this theme matters…</span></h2>
<ul class="sources">
  <li>
    <div class="src-title"><a href="URL">Title</a></div>
    <div class="src-byline">Author · Source · Date</div>
    <p class="src-note">…actionable lesson the factory should consider, or trend/signal worth watching…</p>
    <span class="tag">…</span>
  </li>
  …
</ul>
```

At the bottom of the HTML, include a "Filed observations" section listing each observation filename with its one-line title. This is the HTML → observation direction of the bidirectional cross-reference.

**8c. Stage.** The `/facto-dev:observe` subagents acted on GitHub Issues directly (no files were written on disk). Explicitly stage the HTML:

```bash
git -C "$FACTORY_REPO" add "$FACTORY_REPO/research/YYYY-MM-DD-ai-factory-scan.html"
```

---

## Phase 9: Report

Summarize the run:

- **Queries run**: count of common queries + count of Issue-targeted queries + count of OKR-targeted queries.
- **Candidates surfaced**: count. **Candidates dropped**: count with reason (dup URL / low signal / no actionable cause / evergreen no-new-content).
- **HTML written**: full path.
- **Observations filed**: Issue URLs + action taken (`created`, `commented`, `commented-positive`, `closed`, `reopened`, `created-possible-duplicate`) + one-line summaries.
- **Opportunities for the developer**: for each Opportunities-bucket finding, list: title, URL, one-line actionable lesson, and a "consider: open as new Issue / wait for more signal / drop" hint. This is a "decide later" surface — no automation acts on these; the developer reviews and decides.
- **⚠ Needs-review items**: each item self-tagged in Phase 7, with: filename (HTML entry or observation), why it was flagged (speculative actionable cause / contradicts settled improvement / low-signal source / weak skill mapping / boundary actionable), and the one-step revert: e.g. `git rm <observation-path>` or `git restore --staged <html-path>` plus an edit pointer if only the wording is suspect.

The developer can ignore the report (everything sticks), edit specific items, or revert flagged items in their own time. The skill does not block waiting on them.

---

## Guidelines

- **Two bars; don't conflate them.** The filing bar (memory) is strict: concrete actionable cause required. The HTML bar is wide: trends and signals are welcome. Don't demote an article from the HTML just because it didn't clear the filing bar.
- **Filing bar is OKR-aware.** Findings clear the filing bar by linking to an open Issue (criteria 1–2) or by contradicting the factory's current approach toward an OKR, or surfacing an OKR failure mode (criterion 3). Criterion 3 is negative-only — findings that affirm the factory is on the right track do not get filed; they're not actionable. A finding that's "interesting in general" but doesn't fit either lane goes to the HTML, not memory. This keeps the observation corpus aligned with current factory objectives.
- **No pre-write approval gate.** Write the HTML and file observations in Phase 8, then surface `needs-review` flags in the Phase 9 report. The system learns faster this way.
- **Parallel everything.** `WebSearch` calls in Phase 3 all fire at once. `WebFetch` calls in Phase 4 all fire at once. `/facto-dev:observe` subagent spawns in Phase 8a all fire at once. Never chain these sequentially.
- **Recency window is computed, not hardcoded.** Always derive from `date -u +%Y-%m` and `date -u -d '2 months ago' +%Y-%m` at invocation time. The skill must keep working correctly in 2027 and beyond without any edits to the prompt.
- **Evergreen domains re-scan on a 14-day window.** These sources update frequently enough to be worth revisiting; don't suppress them with the 60-day general rule.
- **Never call `gh issue` directly.** Always go through `/facto-dev:observe` in caller (non-interactive) mode. This keeps matching, body/comment templates, and the `<skill-name> says: ` prefix convention consistent with observations filed by any other path.
- **Source is `internet-research`.** That is the documented category for findings pulled from outside sources. Do not use `developer-feedback` or `claude-code-logs`.
- **URLs and excerpts go in the Issue body or comment.** Greppable for future passes; cited inline so the source is part of the Issue's audit trail.
- **Bidirectional cross-reference.** Every filed observation's Issue body or comment includes the research HTML filename. The HTML's "Filed observations" section lists every resulting Issue URL. Both links must be present.
- **Don't manufacture observations.** If the web search returns nothing relevant, file nothing. An empty pass is a valid outcome — report it and stop.
- **One candidate, one observation.** Don't bundle multiple distinct findings into a single observation.
- **Counter-evidence counts.** A finding that contradicts a fix attempt currently in flight (an Issue with Status `In review` or `In test`) is important evidence — file it and tag `needs-review` if it contradicts a recently-closed-as-completed Issue. (`needs-review` is a triage label, not state; it remains in use.)
- **Internet-research observations describe what the source said.** Do not compare to our factory. The observation captures the external claim, mechanism, and cited data; comparison-to-our-setup is the job of `facto-dev:think` or developer review, not the mining skill.
- **Project Status drives the two-criterion matching.** The deprecated `in-testing` label no longer determines evidence bucketing. Status from `projectItems` does. Issues not yet in the project default to criterion 2.
- **This skill never writes Status.** Resolves project info in Setup to read Status during matching; never calls `gh project item-edit` or any Status-writing API. All Issue-state changes go through facto-dev:observe in caller mode.
- **`test-fi` labelled Issues are filtered out** at the bulk-fetch step.
