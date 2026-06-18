---
name: mine-logs
description: "Scan the current Claude Code session log for events worth filing as factory improvement observations — events that support/refute an open GitHub Issue, reveal a factory problem that goes against an OKR target, or stand alone as a notable failure. Routes each through /facto-dev:observe in caller mode. Invoke with /facto-dev:mine-logs. Procedure skill (follow the phases in order)."
disable-model-invocation: true
color: yellow
---

# Factory Improvement: Mine Session for Observations

> **Model:** when run as a subagent, prefer `model: sonnet`.

Scan the current Claude Code session log (including subagent logs spawned during it) for events worth filing as observations, and propose them. An event is worth filing when it falls into one of:

1. An open Issue with Status **In review** or **In test** — does the event support or refute the fix attempt in flight (PR open or just merged)?
2. An open Issue with Status **Backlog** or **In progress** — does the event accumulate evidence for or against the underlying problem?
3. **The event reveals a factory problem that goes against a KR target** in `OKRS.md`. Specifically: events where the factory failed to meet what a KR targets — e.g. the agent blocked on user input mid-task (against the `independence` KR), the factory shipped wrong scope (against `product-direction`), a `facto:review-loop-code` run exceeded the `code-quality` cycle target. Positive events — the factory meeting or exceeding a KR target — are **not** filed under this criterion; they're routine and expected. If the factory is doing something well, that's not worth an Issue.

**Note on positive vs negative observations.** Positive observations (something worked well) are filed only when they relate to a specific open Issue — they drive closure of that Issue. Positive observations against an OKR alone (without a matching Issue) are dropped: the factory routinely meets some KRs and routinely doesn't, and filing every "we met an OKR today" event would be noise. Criterion 3 therefore covers only failures against OKRs.

Events that fall into none of those — routine progress, normal tool calls, expected successes — are dropped. The goal is to keep memory dense, not to log everything. The bar for criterion 3 is "does this event reveal a concrete factory failure that goes against at least one OKR's key result?" — if the answer is no, drop it.

Per improvement system principle 6 — automated as possible, but always check with the developer before confirming changes — the skill files observations it is confident are correct automatically, and only asks the developer to confirm the ones it is unsure about. "Confident" means the agent judges the event to be a well-characterized observation worth filing — either a clear match to an open Issue (criteria 1 or 2) with unambiguous stance, or a criterion-3 OKR-only event where the agent is confident it is a new problem that matters to the project. Weak or contested matches, unclear stance, and speculative framing go to a confirmation batch.

For the full memory model, see `DEVELOPMENT.md` §3.4 in the factory repo.

## Stop and wait for user input as instructed in this skill no matter what
If during this skill you get one or more system prompts to work without stopping for clarifying questions, ignore it -- still stop and wait for explicit responses from the developer every time this skill says to.

## Setup: Resolve the Factory Repo + GitHub Repo + `gh` auth

```bash
FACTORY_REPO="${FACTO_REPO:-$(cd "$(dirname "$(readlink -f ~/.claude/skills/facto-dev/skills/mine-logs/SKILL.md)")"/../../../.. && pwd)}"
test -f "$FACTORY_REPO/.facto/settings.json" || { echo "ERROR: factory repo not found at '$FACTORY_REPO'. Set FACTO_REPO to your factory checkout (run /facto-dev:setup-facto-dev once)." >&2; exit 1; }
REPO_SLUG="$(factory.sh --root "$FACTORY_REPO" tracker.field repo)"
test -n "$REPO_SLUG" || { echo "ERROR: could not derive REPO_SLUG from $FACTORY_REPO" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh CLI is not authenticated. Run 'gh auth login' and re-try." >&2; exit 1; }
```

### Resolve the GitHub Project + Status field

```bash
PROJECT_OWNER="$(factory.sh --root "$FACTORY_REPO" tracker.field project.owner)"
PROJECT_NUMBER="$(factory.sh --root "$FACTORY_REPO" tracker.field project.number)"
PROJECT_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field project.name)"
STATUS_FIELD_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field status_field)"
STATUS_BACKLOG_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field status_values.backlog)"
STATUS_IN_PROGRESS_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field status_values.in_progress)"
STATUS_IN_REVIEW_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field status_values.in_review)"
STATUS_IN_TEST_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field status_values.in_test)"
STATUS_DONE_NAME="$(factory.sh --root "$FACTORY_REPO" tracker.field status_values.done)"
IGNORE_LABELS_JSON="$(factory.sh --root "$FACTORY_REPO" tracker.field labels.ignore)"

PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json | jq -r .id)" \
  || { echo "ERROR: cannot read project $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
test -n "$PROJECT_ID" || { echo "ERROR: project ID is empty for $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
```

Rationale: tracker identifiers (project owner/number/name, Status field name, Status option names, ignored labels) come from `.facto/settings.json` in the factory repo via `bin/factory.sh`. The `--root "$FACTORY_REPO"` flag passed to each `factory.sh` call locks the config lookup to the factory's `.facto/settings.json` regardless of which repo this skill is invoked from. This skill never writes Status, so the Status field option IDs (`STATUS_*_ID`) are not needed and are not resolved. `PROJECT_ID` is resolved here because it is needed if the fallback `gh project item-list` path is taken in Phase 2. Status option names are compared as strings (e.g. checking whether `.status.name` equals `$STATUS_IN_REVIEW_NAME`) — no IDs required. All Status writes go through facto-dev:observe.

---

## Progress Tracking

Before starting, use `TaskCreate` to create one task per phase below — the phase title as `subject` and a present-continuous label as `activeForm`. All tasks start `pending`. At the start of each `## Phase N` section, use `TaskUpdate` to set its task to `in_progress`; set it to `completed` when that phase is done.

## Phase 1: Locate the Session Log

Claude Code stores session logs at:

```
~/.claude/projects/<project-slug>/<session-id>.jsonl
```

The project slug is the current working directory with every non-alphanumeric character replaced by `-` (Claude Code's own slug rule — `/`, `.`, and any other non-alphanumerics each become a `-`, so consecutive non-alphanumerics produce consecutive dashes). The session ID is not exposed to the skill via any environment variable, so identify it by emitting a unique marker and then finding which session log captured it. This is more reliable than picking the most-recently-modified log, which is fragile when multiple Claude Code sessions are active in the same project.

**Bash call A** — emit a unique marker:

```bash
PROJECT_SLUG="$(pwd | sed 's|[^a-zA-Z0-9]|-|g')"
SESSION_DIR="$HOME/.claude/projects/$PROJECT_SLUG"
if [ ! -d "$SESSION_DIR" ]; then
  echo "ERROR: Computed slug '$PROJECT_SLUG' has no matching directory under ~/.claude/projects/." >&2
  echo "Claude Code's project-slug rule may have drifted. Ask the developer for the session log path before continuing." >&2
  exit 1
fi
MARKER="FI_OBS_MINE_LOGS_MARKER_$(date +%s%N)_$RANDOM"
echo "$MARKER"
```

The bash call's output (including the echoed marker) is recorded in this session's `.jsonl` *after* the call returns — so a single bash call cannot grep for its own marker. The next bash call can.

**Bash call B** — locate the session log that captured the marker:

```bash
SESSION_LOG="$(grep -l "$MARKER" "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1)"
SESSION_ID="$(basename "$SESSION_LOG" .jsonl)"
SUBAGENT_DIR="$SESSION_DIR/$SESSION_ID/subagents"
echo "Session log: $SESSION_LOG"
echo "Subagent dir: $SUBAGENT_DIR"
```

Note: `$MARKER` must be set in the same shell environment as the grep. Bash calls in this skill don't share environment by default, so include the marker as a literal value in the grep command if running it in a separate invocation, e.g. `grep -l 'FI_OBS_MINE_LOGS_MARKER_...' ...`.

If `$SESSION_LOG` is empty, the cwd may not match the session's project, or the marker hasn't been flushed yet. Try once more with a brief delay; if it still fails, ask the developer for the session log path before continuing.

The skill will read both the main session log and any subagent logs under `$SUBAGENT_DIR`.

---

## Phase 2: Load Memory Context (open Issues + OKRs)

One bulk `gh issue list` plus a read of the OKRs file:

```bash
gh -R "$REPO_SLUG" issue list \
  --state open \
  --json number,title,body,labels,comments,updatedAt,projectItems \
  --limit 200
```

Paginate if 200 records returned. Filter out any Issue carrying a label in `$IGNORE_LABELS_JSON` (e.g. `test-fi`, plan-validation data — never production state):

```bash
jq --argjson ignore "$IGNORE_LABELS_JSON" '[.[] | select([.labels[].name] | any(. as $l | $ignore | index($l)) | not)]'
```

For each candidate Issue, extract its Status from the `projectItems` array (entry with `title == $PROJECT_NAME`) by reading `.status.name`. The actual JSON shape is `{"projectItems":[{"status":{"optionId":"…","name":"Backlog"},"title":"<project name>"}]}` — `status` is an object, so the column name lives at `.status.name`. Example jq: `.projectItems[] | select(.title == $name) | .status.name` (with `--arg name "$PROJECT_NAME"`). Criterion 1 keys off Status ∈ {`$STATUS_IN_REVIEW_NAME`, `$STATUS_IN_TEST_NAME`}; criterion 2 keys off Status ∈ {`$STATUS_BACKLOG_NAME`, `$STATUS_IN_PROGRESS_NAME`}. Issues with `null` `.status`, or with no entry for the configured project (not yet on the project), fall under criterion 2 by default — they're effectively Backlog from the mining skill's perspective.

**Working inline filter.** To annotate every Issue with its Status in one pass, collect matches into an array and take `first`, then fall back to `null` — never place `//` directly after a parenthesized expression inside an object value, jq's parser rejects it (`syntax error, unexpected //, expecting '}'`):

```bash
jq --arg name "$PROJECT_NAME" '[.[] | . + {projectStatus: (([.projectItems[] | select(.title == $name) | .status.name] | first) // null)}]'
```

Fallback if `projectItems` doesn't expose field values on a given `gh` version: `gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 200` and merge by `content.number`.

For each Issue the matching step uses: title, body, project Status (criterion 1 keys off Status ∈ {`$STATUS_IN_REVIEW_NAME`, `$STATUS_IN_TEST_NAME`}; criterion 2 keys off Status ∈ {`$STATUS_BACKLOG_NAME`, `$STATUS_IN_PROGRESS_NAME`}), and the most recent ~30 comments for context on what evidence has already accumulated.

Read OKRs at `$FACTORY_REPO/OKRS.md` so you know each objective (description in `**Description:**`), its objective-level status dot from the `## <slug> <dot>` header, its KR table (Target column + per-row Current status dots), and the slugs — criterion 3 matches against these. Survey-measured KRs are flagged with 📋 in the Target cell. Closed Issues are deliberately not loaded — mining matches against currently-open state only.

---

## Phase 3: Scan the Session With Memory in Mind

Read the session log (and subagent logs) once, scanning for events that match any of the four criteria. Don't generate a generic candidate list first and then filter — match while reading, so you only surface events that are already pre-filtered for relevance.

Look specifically for:

- **Skill behavior**: did a skill misbehave (didn't follow its own rules, skipped a required step, took an action it shouldn't have) or behave notably well in a way an improvement cares about?
- **Latency / performance**: did an operation take noticeably long — long enough to be worth investigating — or noticeably fast in a way an observation tracks?
- **Failures and retries**: errors, repeated tool calls that kept failing, abandoned approaches, commands the agent had to redo multiple times to succeed.
- **Developer corrections / complaints**: places where the developer pushed back on the agent's choice, told the agent to stop or restart, or expressed frustration. Strong signal — the developer is the ground truth on whether the factory is working.
- **Bug confirmations**: did a known issue (per an existing observation/improvement) actually happen this session?
- **Counter-evidence**: did the agent or skill behave correctly in a case where an observation predicts failure? That's contradicting evidence and is just as important to file.

For each candidate event, capture:

- **What happened** — concise natural-language description of the event.
- **Impact** — one-line concrete effect of the event.
- **Which Issue it relates to** — an Issue number for criteria 1–2 (e.g. `#42`), OR one or more OKR slugs from `OKRS.md` for criterion 3 (e.g. `okrs:[independence,code-quality]`). An event can target both.
- **Stance** — `supports` or `refutes` (relative to the underlying problem the matched Issue is about), or `violates-okr` for OKR-only events — criterion 3 only covers problems, never successes, so no positive direction is needed.
- **Source evidence** — where in the session/subagent log this is visible (timestamp range, line numbers if useful, or quoted excerpt).

Do **not** generate root-cause analysis here. RCA is `facto-dev:observe`'s job; this skill produces the natural-language input that `facto-dev:observe` will analyze. Mining stays focused on "what happened in the session"; "why" is derived during filing.

If no events match, report "No session events worth filing" and stop.

---

## Phase 4: Split Candidates by Confidence, then Confirm Only the Uncertain Ones

Sort each surviving candidate into one of two buckets:

- **Confident** — file directly in Phase 5 without confirmation. The event is plainly visible in the session log (a concrete tool call, error, developer correction, or stated outcome — not inferred from absence) AND one of:
  - **Criterion 1 or 2** — matches a specific open Issue by number with unambiguous stance (`supports`/`refutes`) given the candidate's content and the matched Issue's body and existing comments; OR
  - **Criterion 3 (OKR-only)** — the agent is confident this is a new problem that matters to the project. Absence of an existing matching Issue is NOT a reason to route the candidate to Uncertain; a novel finding is not inherently uncertain to file. Route to Uncertain only if the agent itself is unsure.
- **Uncertain** — must be confirmed by the developer before filing. Use this bucket only for genuine uncertainty:
  - Ambiguous stance (could plausibly be read as `supports` or `refutes`).
  - Weak or contested match to an existing Issue — the candidate "kind of" relates but the connection isn't tight.
  - Speculative framing — the candidate is conjectural ("might be", "possibly") rather than a clearly observed event.
  - Anything the agent has low confidence about for any reason — when in doubt, route to confirmation.

**After sorting, choose your path based on what's in the buckets:**

- **Path A — No uncertain candidates:** Display the **Filing automatically** heads-up (see template below), then proceed immediately to Phase 5. Do NOT ask a question. Do NOT wait. Silence on a confident candidate is consent.
- **Path B — Uncertain candidates present:** Display both buckets (see template below), then wait for the developer's response before Phase 5.
- **No candidates at all:** Report "No session events worth filing" and stop.

**Path A output** (no uncertain candidates — display this heads-up, then go directly to Phase 5):

> **Filing automatically (N):**
> - <candidate-summary> → Issue #<n> (<stance>)
> - ...

**Path B output** (uncertain candidates present — display both buckets, then wait):

> **Filing automatically (N):**
> - <candidate-summary> → Issue #<n> (<stance>)
> - ...
>
> **Need confirmation (M):**
> - <candidate-summary>
>   - Impact: <one-line>
>   - Possible match: Issue #<n> + one-line summary, or `okrs:[<slugs>]`
>   - Stance: <stance>
>   - Reason for uncertainty: <one-line>
> - ...

**Path B developer options.** The following prose applies only when uncertain candidates are present (Path B). In Path A there is no developer interaction; the agent has already moved on to Phase 5.

For the **Filing automatically** bucket (Path B context), the developer's only options are *go-ahead* (the default — proceed to Phase 5) or *pull one back to confirmation* (treat it as uncertain instead). The developer does not have to approve each one individually — silence on a confident candidate is consent.

For the **Need confirmation** bucket, the developer can:
- Approve all, approve a subset, or drop any candidate
- Edit a candidate's wording before filing
- Promote a candidate from confirmation into auto-file if they agree the match is clear

The developer is approving *whether to file the event*, not the RCA — that gets generated by `facto-dev:observe` per candidate after approval. If an RCA later turns out weak, `facto-dev:think` is the next confirmation gate, and the developer can edit the observation file directly.

**Single batched display (Path B).** Don't confirm one candidate at a time. Show both buckets in one message.

**Worked example — Path A (1 confident candidate, 0 uncertain):**

The agent displays:

> **Filing automatically (1):**
> - "Agent blocked mid-task asking for permission to run git commit" → Issue #62 (supports — recurrence of the auto-mode classifier bug)

The agent's very next action is invoking the Phase 5 subagent (a `/facto-dev:observe` Skill call), with no question asked and no wait for a response.

**Gotcha — Path A triggers a confirmation question (observed 2026-05-19 on session fddff49f):**
When exactly one confident candidate and zero uncertain candidates were present, the agent displayed the Filing automatically list and then asked: "Proceed to file this one against #62, or pull it back?" — treating the auto-file as a confirmation prompt rather than a heads-up. This recurred twice in a single run. If you are on Path A, you MUST NOT phrase a question. The template and the surrounding confirmation-shaped prose can cause this mistake. Display the heads-up, then go directly to Phase 5.

---

## Phase 5: File Approved Observations

For each approved candidate, launch a subagent (`model: "sonnet"`) and have it run `/facto-dev:observe` via the Skill tool **in caller (non-interactive) mode**, passing:

- The natural-language summary of the event
- The impact line
- Any relevant log excerpts the subagent should consider as context
- `source: claude-code-logs` (the standard source for events extracted from session logs)
- `related-skill` if the event is about a specific skill
- `related-run` set to the session ID or a more specific reference if available
- A `target-issue` hint when the candidate matched a specific Issue (criteria 1–2) — biases facto-dev:observe's match step toward that candidate without forcing it (if the root cause genuinely differs, facto-dev:observe creates a new Issue with a possible-duplicate note)
- The `--non-interactive` flag (or equivalent argument) so `facto-dev:observe` writes its best draft without prompting

`facto-dev:observe` will draft the observation, judge same-root-cause match, and either comment on the matched Issue, autonomously close on strong positive evidence, comment-only on lower-confidence positive evidence, reopen on recurrence, or open a new Issue. This skill never calls `gh issue` directly — always go through `facto-dev:observe` so the matching logic and comment/body templates stay in one place.

Subagents fire in parallel — one per approved candidate. **Caveat:** parallel facto-dev:observe runs can race on the bulk-fetch step. For ≤5 candidates this is acceptable (collisions are unlikely); for larger batches, run sequentially or in small parallel groups to avoid duplicate-Issue creation from two parallel runs that both decided "no match."

---

## Phase 6: Report

Summarize the pass:

- **Session log scanned**: path + size.
- **Open Issues considered**: total count of open Issues fetched, broken down by Status (Backlog / In progress / In review / In test) counts.
- **Candidates surfaced**: count, split by `auto-filed` vs `confirmed-then-filed`.
- **Observations filed**: Issue URLs + action taken (`created`, `commented`, `commented-positive`, `closed`, `reopened`, `created-possible-duplicate`), each marked `[auto]` or `[confirmed]`.
- **Candidates dropped**: count + brief reason (developer rejected, edited and merged with another, etc.).

---

## Guidelines

- **Match against open Issues and OKRs.** Closed Issues are out of scope. Criteria 1–2 match against currently-open Issues; criterion 3 matches against `OKRS.md`. Together they cover both "do we already track this?" and "does this move our current objectives?" — but routine session activity that does neither is dropped.
- **Bar for criterion 3: "does this event reveal a concrete factory failure against an OKR's key result?"** Match against the KR targets in `OKRS.md`. Drop events that don't indicate a failure: a step that was slow but no KR cares → drop; normal successful tool calls → drop. File only when a KR target is being missed: the agent blocking mid-task → `independence` KR; factory shipping wrong scope → `product-direction`; `facto:review-loop-code` exceeding its cycle KR → `code-quality`. The skill never recommends updating the progress indicators in `OKRS.md` — those are updated manually by the developer. This skill just identifies the problems.
- **Never recommend updating progress indicators in `OKRS.md`.** This skill identifies factory failures against OKR key results and routes them to Issues via `facto-dev:observe`. It does not propose dot changes (🔴/🟡/🟢) to `OKRS.md`. The developer updates those manually when they assess the overall picture.
- **Don't manufacture observations.** If the session has nothing relevant, file nothing. An empty pass is a valid outcome.
- **Source is `claude-code-logs`.** That's the documented category for observations inferred from session activity. Don't use `developer-feedback` for events the agent extracted from a log.
- **Counter-evidence counts.** A session where a skill behaved *correctly* in a case where an Issue's body predicts failure is exactly the kind of contradicting evidence to file — facto-dev:observe will route it as a positive observation, which may produce an autonomous close or a positive-comment-only on lower-confidence evidence.
- **Quote evidence, briefly.** When useful, include a short excerpt from the log in the candidate summary so `facto-dev:observe` has grounded material to write its Issue body or comment from.
- **One candidate, one observation.** Don't bundle multiple distinct events into a single observation, even if they relate to the same Issue — separate observations make pattern detection more robust.
- **Never call `gh issue` directly from this skill.** Always file via `facto-dev:observe` (subagent + Skill tool, non-interactive mode) so matching, body/comment templates, autonomous-close logic, and the `<skill-name> says: ` prefix convention stay in one place.
- **Project Status drives the two-criterion matching.** Labels (specifically the deprecated `in-testing`) no longer determine evidence bucketing. Status from `projectItems` does. Issues not yet in the project default to criterion 2.
- **This skill never writes Status.** It resolves the project and Status field in Setup so it can read Status during matching, but it never calls `gh project item-edit` or any other Status-writing API. All Issue-state changes go through facto-dev:observe.
- **`test-fi` labelled Issues are filtered out** at the bulk-fetch step. They never participate in matching.
