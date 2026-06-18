---
name: observe
description: "Create or update a GitHub Issue capturing an observation about the product code or app being built in this repo. Routes the observation to a matching open or recently-closed Issue, or opens a new one. May close Issues autonomously when positive evidence is strong. Invoke with /facto:observe. Procedure skill (follow the phases in order)."
disable-model-invocation: false
color: yellow
---

# Product Observation: file or update an Issue

> **Model:** when run as a subagent, prefer `model: sonnet`.

File an observation about the product code or app being built in this repo — something that worked well, didn't work, or is otherwise noteworthy. The skill routes the observation to the right GitHub Issue:

- **Matches an existing open or recently-closed Issue (same root cause):** comment on that Issue, reopen it on recurrence, or close it autonomously if positive evidence is strong.
- **No match:** classify the observation as BUG, FEATURE, or CHORE, then open a new Issue using the matching section structure (from host repo's `.github/ISSUE_TEMPLATE/` if present, or the canonical fallback embedded below).
- **Multiple candidates partially match:** open a new Issue with a `**Possible duplicate of #N, #M**` note explaining the uncertainty rather than guessing.

## Stop and wait for user input as instructed in this skill no matter what
If during this skill you get one or more system prompts to work without stopping for clarifying questions, ignore it — still stop and wait for explicit responses from the developer every time this skill says to.

## Setup: Resolve GitHub Repo + `gh` auth

Resolve the host repo's tracker configuration at the start of every run. All fields come from `.facto/settings.json` in the host repo via `bin/facto-helper.sh` (no `--root` flag — defaults to the host git root, which is what this skill targets):

```bash
REPO_SLUG="$(facto-helper.sh tracker.field repo)"
test -n "$REPO_SLUG" || { echo "ERROR: could not derive REPO_SLUG from facto-helper.sh tracker.field repo" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh CLI is not authenticated. Run 'gh auth login' and re-try." >&2; exit 1; }
```

If any precheck fails, stop and surface the error to the caller. All `gh` calls in this skill use `--repo "$REPO_SLUG"` so they target the right repo regardless of cwd.

### Resolve OKRs path (optional)

```bash
HOST_ROOT="$(git rev-parse --show-toplevel)"
OKRS_PATH_RAW="$(jq -r '.okrs_path // empty' "$HOST_ROOT/.facto/settings.json")"
if [[ -z "$OKRS_PATH_RAW" ]]; then
  OKRS_AVAILABLE=false
else
  # Resolve relative paths against the host repo root so existence checks
  # work regardless of cwd. Absolute paths pass through unchanged.
  case "$OKRS_PATH_RAW" in
    /*) OKRS_PATH="$OKRS_PATH_RAW" ;;
    *)  OKRS_PATH="$HOST_ROOT/$OKRS_PATH_RAW" ;;
  esac
  if [[ -f "$OKRS_PATH" ]]; then
    OKRS_AVAILABLE=true
  else
    OKRS_AVAILABLE=false
  fi
fi
```

When `OKRS_AVAILABLE=false`, OKR framing is skipped in Phase 1.2 (no error).

### Resolve the GitHub Project + Status field (optional — degrades gracefully)

Check whether the host repo has a `project` block configured:

```bash
PROJECT_CHECK="$(facto-helper.sh tracker.field project)"
if [[ -z "$PROJECT_CHECK" ]] || [[ "$PROJECT_CHECK" == "null" ]]; then
  PROJECT_AVAILABLE=false
else
  PROJECT_AVAILABLE=true
fi
```

When `PROJECT_AVAILABLE=false`, all `gh project` calls in Phase 5 are skipped (no Status writes). This is the expected state for repos with only a `tracker.type` + `tracker.repo` config and no `project` block.

When `PROJECT_AVAILABLE=true`, resolve the project and Status field:

```bash
PROJECT_OWNER="$(facto-helper.sh tracker.field project.owner)"
PROJECT_NUMBER="$(facto-helper.sh tracker.field project.number)"
PROJECT_NAME="$(facto-helper.sh tracker.field project.name)"
STATUS_FIELD_NAME="$(facto-helper.sh tracker.field status_field)"
STATUS_BACKLOG_NAME="$(facto-helper.sh tracker.field status_values.backlog)"
STATUS_IN_PROGRESS_NAME="$(facto-helper.sh tracker.field status_values.in_progress)"
STATUS_IN_REVIEW_NAME="$(facto-helper.sh tracker.field status_values.in_review)"
STATUS_IN_TEST_NAME="$(facto-helper.sh tracker.field status_values.in_test)"
STATUS_DONE_NAME="$(facto-helper.sh tracker.field status_values.done)"

PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json | jq -r .id)" \
  || { echo "ERROR: cannot read project $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
test -n "$PROJECT_ID" || { echo "ERROR: project ID is empty for $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }

STATUS_FIELD_JSON="$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json \
  | jq --arg name "$STATUS_FIELD_NAME" '.fields[] | select(.name == $name)')" \
  || { echo "ERROR: cannot list fields for project $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
test -n "$STATUS_FIELD_JSON" || { echo "ERROR: Status field ($STATUS_FIELD_NAME) not found in project" >&2; exit 1; }

STATUS_FIELD_ID="$(echo "$STATUS_FIELD_JSON" | jq -r .id)"
STATUS_BACKLOG_ID="$(echo "$STATUS_FIELD_JSON"     | jq -r --arg n "$STATUS_BACKLOG_NAME"     '.options[] | select(.name == $n) | .id')"
STATUS_IN_PROGRESS_ID="$(echo "$STATUS_FIELD_JSON" | jq -r --arg n "$STATUS_IN_PROGRESS_NAME" '.options[] | select(.name == $n) | .id')"
STATUS_IN_REVIEW_ID="$(echo "$STATUS_FIELD_JSON"   | jq -r --arg n "$STATUS_IN_REVIEW_NAME"   '.options[] | select(.name == $n) | .id')"
STATUS_IN_TEST_ID="$(echo "$STATUS_FIELD_JSON"     | jq -r --arg n "$STATUS_IN_TEST_NAME"     '.options[] | select(.name == $n) | .id')"
STATUS_DONE_ID="$(echo "$STATUS_FIELD_JSON"        | jq -r --arg n "$STATUS_DONE_NAME"        '.options[] | select(.name == $n) | .id')"
```

Rationale: tracker identifiers (project owner/number/name, Status field name, Status option names) come from `.facto/settings.json` in the host repo via `bin/facto-helper.sh`. Hardcoded option IDs would silently break if the project is deleted and recreated (the node IDs change), so they are resolved dynamically. Dynamic resolution costs one extra API call per run — `gh project view` plus `gh project field-list` — but the system survives a project recreation without any code change.

### Status-setting helper: `set_issue_status <issue-number> <status-name>`

This helper is a conceptual procedure — execute the steps inline wherever the skill calls `set_issue_status`. The `<status-name>` argument is one of: `Backlog`, `In progress`, `In review`, `In test`, `Done`.

All steps in this helper are wrapped in `if [[ "$PROJECT_AVAILABLE" == "true" ]]; then … fi` — they are no-ops when no project board is configured.

1. **Resolve the project item ID** for the given Issue. Paginate if the project has more than 200 items (repeat with adjusted offset until the response has fewer than 200):

   ```bash
   ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
     --format json --limit 200 \
     | jq -r --argjson num <issue-number> \
       '.items[] | select(.content.type == "Issue" and .content.number == $num) | .id')"
   ```

2. **If no item is found**, add the Issue to the project. `gh project item-add` may silently no-op if the Issue was already added by a repo→project auto-add workflow — this is idempotent by design:

   ```bash
   ITEM_ID="$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
     --url "https://github.com/$REPO_SLUG/issues/<issue-number>" \
     --format json | jq -r .id)"
   test -n "$ITEM_ID" || { echo "ERROR: could not add Issue <issue-number> to project" >&2; exit 1; }
   ```

3. **Edit the Status field** using the resolved option ID (`STATUS_BACKLOG_ID`, `STATUS_DONE_ID`, etc. — already resolved in Setup):

   ```bash
   gh project item-edit \
     --project-id "$PROJECT_ID" \
     --id "$ITEM_ID" \
     --field-id "$STATUS_FIELD_ID" \
     --single-select-option-id "$STATUS_<NAME>_ID"
   ```

   Replace `STATUS_<NAME>_ID` with the matching variable for the requested status name (e.g. `$STATUS_BACKLOG_ID` for `Backlog`, `$STATUS_DONE_ID` for `Done`).

4. Note: `gh project item-add` may return an existing item ID when the Issue was already in the project (auto-add workflows can pre-populate items for new Issues in the repo). The helper is idempotent — calling it twice with the same status has no harmful effect.

---

## Entry modes

Two modes, selected by the caller:

- **Manual mode** (default, used when invoked as `/facto:observe`): the skill drafts the observation from the natural-language input, asks the user when there's a specific piece it's uncertain about (see "When to ask" below), then executes via `gh` and reports.
- **Caller mode** (used when another skill invokes this one with a `--non-interactive` flag): the skill drafts and executes without prompts. On any ambiguity it defaults to **create a new Issue with a possible-duplicate note**, never to silently picking the wrong Issue.

The behavior produced is identical in both modes. The only difference is whether the skill ever prompts the developer.

---

## Input

The caller may pass the natural-language summary as the skill argument. Otherwise (manual mode), ask:

> "What did you observe? Give me a short summary plus any relevant context."

Optional metadata (caller passes these, or the skill asks in manual mode only if a value is needed and not present):

- **`source`** — one of `developer-feedback`, `claude-code-logs`, `internet-research`, or other short string. Defaults to `developer-feedback` in manual mode if not specified.
- **`related-project`** — the sub-project or module this observation came from (e.g. `billing`, `mobile-app`). Omit if not applicable.
- **`related-area`** — the area, component, or module the observation is about (e.g. `auth`, `billing`, `mobile-app`).
- **`related-run`** — a reference to the specific run, PR, or session (e.g. `PR-72`, session id).

These all flow **inline into the Issue body or comment**, not into YAML frontmatter (no frontmatter exists on Issues).

---

## Progress Tracking

Before starting, use `TaskCreate` to create one task per phase below — the phase title as `subject` and a present-continuous label as `activeForm`. All tasks start `pending`. At the start of each `## Phase N` section, use `TaskUpdate` to set its task to `in_progress`; set it to `completed` when that phase is done.

## Phase 1: Draft the Observation

### Phase 1.1: Classify the observation

Before drafting, classify the observation as **BUG**, **FEATURE**, or **CHORE** using these rules:

- **BUG** — the observation describes something not working right (a reproducible failure, regression, slowness, or drift). Default type when `source: claude-code-logs`.
- **FEATURE** — the observation describes a capability that does not yet exist and that would help if added. Default when the input frames "we should have X" or "X is missing."
- **CHORE** — the observation describes cleanup needed: refactor, dependency bump, docs maintenance, or consolidation of drift.
- **Internet-research exception:** when `source: internet-research`, the type is a research finding — file with **no prefix** in third-party voice. The body shape for these follows the BUG template (What's happening / Impact / Root cause), since research-mining skills already produce that shape.

If classification is ambiguous (the observation could be BUG or FEATURE), prefer **BUG** when there's a concrete failure mode to capture, or **FEATURE** when the framing is forward-looking. In caller mode, when truly ambiguous, default to BUG and add a note in the body: `_classification: ambiguous between BUG and FEATURE; filed as BUG._`. In manual mode, ambiguity is a **When to Ask** trigger.

### Phase 1.2: Draft the body sections

From the natural-language input plus any context, draft the sections matching the classified type. First, check whether the host repo has Issue templates:

**If `.github/ISSUE_TEMPLATE/1-bug.md` (or the feature/chore equivalent) exists in the host repo**, read it for canonical section names and heading levels, then fill each section with the content drafted from the observation.

**If the host repo has no matching Issue template**, use the canonical fallback section structure below. Document in Phase 7 that the fallback fired.

#### Canonical fallback section structure

**BUG:**
```
## What's happening
<One paragraph — the event itself, anchored in time.>

### Impact
<Concrete effect — time lost, quality miss, regression, etc.>

## Repro Steps
<Numbered steps to reproduce. Omit this section, Observed Result, and Expected Result if N/A.>

1. <first step>
2. <second step>

### Observed Result
<What actually happens when the steps above are run.>

### Expected Result
<What should happen instead.>

## Root cause(s)
- <First root cause — what an improvement could change.>
- <Second root cause, if applicable.>
```

**FEATURE:**
```
## What's missing
<One paragraph — the capability that's absent and the situation where its absence bites.>

## Why it would help
<Concrete benefit. If it would move an OKR, name it.>

## Sketch
<Optional one paragraph. Rough shape of the capability. Not a design — the implementer decides specifics.>

## Open questions
- <Question for the implementer to think about and decide.>
```

**CHORE:**
```
## What needs cleaning up
<One paragraph. Current state and why it's friction.>

## Desired end state
<One paragraph. What the world looks like after this is done.>

## Open questions
- <Question for the implementer to think about and decide.>
```

**Per-section semantic guidance — BUG:**

- **What's happening** — one paragraph. The event, anchored in time. Quote evidence briefly where useful.
- **Impact** — one paragraph. Concrete effect: time lost, quality miss, regression introduced, developer correction. If the observation is *positive*, name what improved instead. If `OKRS_AVAILABLE=true`, consult `$OKRS_PATH` — if the observation moves a KR target in either direction, frame Impact in those terms. Otherwise write Impact without OKR references.
- **Repro Steps / Observed Result / Expected Result** — include only when the observation is a reproducible failure (a command, hook, or workflow that misbehaves under stated conditions). Omit all three sections entirely (don't leave empty headings) for enhancement-style observations, external research findings, or one-off events that can't be replayed — the template's placeholder explicitly allows this.

  When you do include them, write Repro Steps as the **shortest path** a developer or agent can follow to reproduce the *high-level* issue — not a transcript of the exact actions taken when the problem was first seen. Look for simpler/faster routes: a minimal input that triggers the same code path, a single command that exercises the offending branch, a one-line script. **If the failure surfaced inside a tool or command run by a skill, the repro is "run the skill" (with the minimal inputs that trigger it) — not "run the individual command the skill happened to invoke."** The skill's wrapping is part of what's being reproduced.
- **Root cause(s)** — bullet list. Each bullet names something an improvement could change (a skill prompt, a hook, a missing check). Prefer concrete causes over narrative ones. If a cause is genuinely uncertain, mark it `(uncertain)` rather than fabricating a chain.

**Per-section semantic guidance — FEATURE:**

- **What's missing** — one paragraph. The capability that's absent and the situation where its absence bites.
- **Why it would help** — one paragraph. Concrete benefit. If `OKRS_AVAILABLE=true`, consult `$OKRS_PATH` — if the observation is OKR-relevant, frame in those terms. Otherwise write the benefit without OKR references.
- **Sketch** — optional one paragraph. Rough shape of the capability; do not over-specify. The implementer decides specifics.
- **Open questions** — bullet list. Things the implementer should think about and decide.

**Per-section semantic guidance — CHORE:**

- **What needs cleaning up** — one paragraph. Current state and why it's friction.
- **Desired end state** — one paragraph. What "done" looks like.
- **Open questions** — bullet list.

The observation's "stance" is implicit in the prose: a recurrence/new-failure observation is **negative**; an observation that the original problem now appears fixed is **positive**. The match phase (Phase 3) and decision phase (Phase 4) use this stance.

If input is too thin to draft any of the required sections without speculation, that's a **When to Ask** trigger in manual mode. In caller mode, write `(unclear from input)` and continue.

---

## Phase 2: Bulk-fetch Candidate Issues (pagination from day one)

One bulk call, with explicit pagination — do **not** loop `gh issue view` per Issue.

```bash
THIRTY_DAYS_AGO="$(date -d '30 days ago' +%Y-%m-%d)"
gh -R "$REPO_SLUG" issue list \
  --state all \
  --search "is:issue updated:>=$THIRTY_DAYS_AGO" \
  --json number,title,state,stateReason,body,labels,comments,closedAt,updatedAt,projectItems \
  --limit 200
```

If 200 records returned, paginate by adjusting the upper bound of `updated:` to the oldest `updatedAt` in the previous page and repeating until fewer than 200 come back. Concatenate the pages locally.

Filter locally: include every **open** Issue regardless of `updatedAt`, and every **closed** Issue whose `closedAt` is within the last 30 days. Ignore closed Issues older than 30 days even if they updated recently (that's just a stray comment).

**Extracting per-Issue project Status:** For each candidate, extract its current project Status from the `projectItems` array — find the entry whose `title == $PROJECT_NAME` and read `.status.name`. The actual JSON shape returned by `gh issue list --json projectItems` is `{"projectItems":[{"status":{"optionId":"…","name":"Backlog"},"title":"<project name>"}]}` — `status` is an object with `optionId` and `name`, not a flat string, so the human-readable option name lives at `.status.name`. Example jq: `.projectItems[] | select(.title == $name) | .status.name` (with `--arg name "$PROJECT_NAME"`). If `.status` is `null` (Issue is on the project but the Status field is unset) treat as `null`. If `projectItems` is empty or the configured project's entry is absent (Issue not yet on the project) treat as `null` — Phase 5a will add it when a new Issue is created.

When `PROJECT_AVAILABLE=false`, skip Status extraction from `projectItems` entirely — there is no project to cross-reference.

**Working inline filter.** To annotate every Issue with its Status in one pass, collect matches into an array and take `first`, then fall back to `null` — never place `//` directly after a parenthesized expression inside an object value, jq's parser rejects it (`syntax error, unexpected //, expecting '}'`):

```bash
jq --arg name "$PROJECT_NAME" '[.[] | . + {projectStatus: (([.projectItems[] | select(.title == $name) | .status.name] | first) // null)}]'
```

As a fallback if `projectItems` doesn't return field values on a given `gh` version:

```bash
gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
  --format json --limit 200 \
  | jq '[.items[] | {number: .content.number, status: .status}]'
```

Merge by issue number. Pick the primary path if it works; use the fallback if `status` is absent from the `projectItems` inline data.

For match and decision steps that depend on Status, `null` is acceptable — those steps treat `null` as "no Status known" and proceed.

---

## Phase 3: Judge Same-Root-Cause Match

For each candidate Issue, the model reads its body + the last ~30 comments and decides: does this candidate share the **root cause** with the new observation, or only the symptom?

**Gotcha — symptom vs root cause.** Two components can both "hang," both "produce empty output," both "fail at commit time," for *unrelated* root causes. Matching on symptom alone produces silent merges of distinct problems. Match only when the actionable cause underneath the symptom is the same. When in doubt, treat as no-match and let the new Issue carry a "possible duplicate of #N" note for human triage.

Produce one of:

- **`no-match`** — no candidate shares the root cause.
- **`single-match`** — exactly one candidate clearly shares the root cause. Record its number.
- **`ambiguous-match`** — multiple candidates partially fit, but none clearly. Record the candidate numbers and a one-line rationale per candidate.

---

## Phase 4: Decide the Action

Based on stance (Phase 1) and match (Phase 3):

| Stance | Match | Issue state | Action |
|---|---|---|---|
| negative | no-match | — | **5a:** create new Issue |
| negative | ambiguous-match | — | **5a:** create new Issue with possible-duplicate note |
| negative | single-match | open | **5b:** comment with new evidence |
| negative | single-match | closed | **5c:** reopen + comment with new evidence |
| positive | no-match | — | drop (positive observation with no Issue to confirm is noise; report and stop) |
| positive | ambiguous-match | — | **5a:** create new Issue with possible-duplicate note (so the positive signal isn't lost) |
| positive | single-match | open, high confidence | **5d:** close as `completed` with the evidence as the closing comment |
| positive | single-match | open, lower confidence | **5f:** comment only — positive evidence noted, no state change |
| positive | single-match | closed | drop (already closed; positive evidence reinforces a settled outcome — no action needed) |

**Confidence cut for autonomous close (Phase 5d):**

- *High* — the positive observation directly demonstrates the original failure mode (as described in the Issue body and supporting comments) now succeeding, the action took place under similar conditions to the original failures, AND no contradicting evidence exists in the Issue's recent comments.
- *Lower* — partial or indirect positive signal: the observation is adjacent (related area behaving correctly, but not the exact scenario), the observation is positive but the original Issue's root cause description is broader, OR there's any contradiction in recent comments.

When in doubt, treat as lower confidence — 5f is a comment only (no state change), 5d (autonomous close) is heavier to reverse. **Do not close on a single ambiguous positive observation.**

---

## Phase 5: Execute via `gh`

All commands use `--repo "$REPO_SLUG"`. Comment bodies and Issue bodies always start with `observe says: ...`. All `gh project` blocks are wrapped in `if [[ "$PROJECT_AVAILABLE" == "true" ]]; then … fi` — when no project board is configured, Status writes are skipped silently.

### 5a — Create a new Issue

Assemble the body by following the section structure that matches the classified type (from host repo's `.github/ISSUE_TEMPLATE/` if present, or the canonical fallback above), filling each section with the content drafted in Phase 1.2 (and honoring the "omit if N/A" rule for Repro Steps / Observed Result / Expected Result on BUG issues). Then append the skill-specific footers below — these are *not* in the template:

- If `ambiguous-match`: insert a `## Possible duplicate` section before the footer with the body: `This Issue may be the same root cause as #N (one-line reason) and/or #M (one-line reason). Surfacing here rather than commenting on a wrong Issue. Human triage welcome.`
- Always append a horizontal rule and the line: `_observe says: filed YYYY-MM-DD from source=<source>; area=<related-area or n/a>; run=<related-run or n/a>._`

**Title rule.** Apply the framing rule that matches the classified type:

- **BUG** — state the *problem*, not a fix. The same problem may attract several fix attempts and the title must outlive them. ✅ `BUG: upload button hangs on files larger than 5MB`. ❌ `Add file-size check to upload handler`.
- **FEATURE** — name the *desired capability*, not the absence of it. The title should describe what you're building, not what's missing without it. ✅ `FEATURE: Add bulk-export capability to the reporting screen`. ❌ `FEATURE: No bulk-export capability; reporting is tedious`.
- **CHORE** — name the *cleanup needed*, not the past mistake. ✅ `CHORE: Consolidate duplicate auth-token helpers`. ❌ `CHORE: We have three copies of auth-token helpers scattered around`.
- **Internet-research exception** — no prefix, third-party voice.

```bash
gh -R "$REPO_SLUG" issue create \
  --title "<PREFIX>: <one-line statement>" \
  --body "$BODY"
```

Where `<PREFIX>` is `BUG`, `FEATURE`, or `CHORE` per the classification phase (Phase 1.1). For `source: internet-research`, omit the prefix entirely.

Where `$BODY` is the assembled string described above.

Print the resulting Issue URL.

**Add to project + set Status = `$STATUS_BACKLOG_NAME`.** After capturing the new Issue number from the `gh issue create` output, add the Issue to the configured project and set its Status to the configured backlog value. This block runs only when `PROJECT_AVAILABLE=true`:

```bash
if [[ "$PROJECT_AVAILABLE" == "true" ]]; then
  # Capture new issue number from the URL printed above (e.g. extract trailing digit from https://.../issues/72)
  NEW_ISSUE_NUMBER=<number>

  # Add to project (idempotent)
  NEW_ITEM_ID="$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
    --url "https://github.com/$REPO_SLUG/issues/$NEW_ISSUE_NUMBER" \
    --format json | jq -r .id)"

  # Set Status = Backlog
  gh project item-edit \
    --project-id "$PROJECT_ID" \
    --id "$NEW_ITEM_ID" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$STATUS_BACKLOG_ID"
fi
```

### 5b — Comment on an open matched Issue (negative observation)

No Status change — comment-only path. The Issue remains in its current project Status; only a comment is added.

```bash
gh -R "$REPO_SLUG" issue comment <n> \
  --body "$(cat <<'EOF'
observe says: seen again 2026-05-21.

**What happened:** <one-line event summary, with run reference if available>

**Impact:** <one-line concrete effect>

**Same root cause as this Issue:** yes — <one-line confirmation of why the root cause matches>
EOF
)"
```

The "Same root cause" line is **always present** on Issue-comment actions (5b/5c/5d/5f) — it makes the match decision auditable.

### 5c — Reopen + comment (recurrence on a closed Issue)

```bash
gh -R "$REPO_SLUG" issue reopen <n>
```

Set Status = Backlog — recurrence means the previous fix didn't hold; treat as fresh work. This block runs only when `PROJECT_AVAILABLE=true`:

```bash
if [[ "$PROJECT_AVAILABLE" == "true" ]]; then
  # Resolve item ID (see set_issue_status helper in Setup)
  ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
    --format json --limit 200 \
    | jq -r --argjson num <n> \
      '.items[] | select(.content.type == "Issue" and .content.number == $num) | .id')"

  gh project item-edit \
    --project-id "$PROJECT_ID" \
    --id "$ITEM_ID" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$STATUS_BACKLOG_ID"
fi
```

```bash
gh -R "$REPO_SLUG" issue comment <n> \
  --body "$(cat <<'EOF'
observe says: recurrence 2026-05-21 (this Issue was closed <closedAt-date>).

**What happened:** <one-line event summary>

**Impact:** <one-line concrete effect>

**Same root cause as this Issue:** yes — <one-line confirmation>

**State change:** reopened — problem has recurred after the earlier close.
EOF
)"
```

### 5d — Autonomous close as completed (high-confidence positive)

The closing comment uses the **full comment template**, not a one-liner. This preserves the audit detail you'd get from a comment-and-stay-open path.

```bash
gh -R "$REPO_SLUG" issue close <n> --reason completed \
  --comment "$(cat <<'EOF'
observe says: closing as completed 2026-05-21.

**What happened:** <one-line event summary demonstrating the original failure mode now succeeds>

**Impact:** <one-line: the original problem is no longer reproducing>

**Same root cause as this Issue:** yes — <one-line confirmation>

**State change:** closed as completed — positive evidence confirms the original failure mode now succeeds. If this is wrong, reopen and add evidence.

**PR link:** If a specific PR implemented this fix, edit that PR's description to include `Resolves #<N>` so the link is recorded.
EOF
)"
```

Set Status = Done — the Issue is now closed as completed. This block runs only when `PROJECT_AVAILABLE=true`:

```bash
if [[ "$PROJECT_AVAILABLE" == "true" ]]; then
  # Resolve item ID (see set_issue_status helper in Setup)
  ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
    --format json --limit 200 \
    | jq -r --argjson num <n> \
      '.items[] | select(.content.type == "Issue" and .content.number == $num) | .id')"

  gh project item-edit \
    --project-id "$PROJECT_ID" \
    --id "$ITEM_ID" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$STATUS_DONE_ID"
fi
```

### 5f — Comment only (lower-confidence positive)

No Status change — comment-only path. The Issue remains in its current project Status; only a comment is added.

```bash
gh -R "$REPO_SLUG" issue comment <n> \
  --body "$(cat <<'EOF'
observe says: positive evidence noted 2026-05-21.

**What happened:** <one-line event summary demonstrating the scenario working>

**Impact:** <one-line: the original problem did not reproduce in this instance>

**Same root cause as this Issue:** yes — <one-line confirmation>

**State change:** no state change — positive evidence noted but not yet sufficient to close.
EOF
)"
```

---

## Phase 6: When to Ask (manual mode only)

Do **not** ask the developer to approve the routing decision once it's been made. Execute. Triggers that stop and ask:

- **Uncertain why.** A root cause in Phase 1 has an `(uncertain)` marker that, if grounded, would change the action chosen in Phase 4.
- **Thin input.** The natural-language summary doesn't support drafting any of the three sections without speculation.
- **Competing root causes.** Two plausible root causes contradict each other and the skill can't pick which framing applies.
- **Missing required source.** In manual mode, default to `developer-feedback`; ask only if the input is ambiguous about provenance (e.g. relaying a third party's report).

If none of these fire, draft, decide, execute, and report. The developer can edit the resulting Issue or comment directly on github.com.

In caller mode, none of these trigger prompts. Record `(uncertain)` markers in the body where applicable and proceed.

---

## Phase 7: Report

Single-line summary plus URL. Examples:

- `Created new Issue: https://github.com/$REPO_SLUG/issues/72 (Status: Backlog) (no match found among 18 candidates)`
- `Commented on existing Issue #51: https://github.com/.../issues/51 (no Status change) (recurrence — same root cause)`
- `Closed Issue #58 as completed: https://github.com/.../issues/58 (Status: Done) (high-confidence positive evidence)`
- `Reopened Issue #44: https://github.com/.../issues/44 (Status: Backlog) (recurrence)`
- `Commented on Issue #38: https://github.com/.../issues/38 (no Status change) (positive evidence noted — not yet sufficient to close)`
- `Created new Issue #82 with possible-duplicate note (uncertain match against #51, #58): https://github.com/.../issues/82 (Status: Backlog)`

Append parenthetical notes at the end of the report line when a degradation fired:

- `(no project board configured; status writes skipped)` — when `PROJECT_AVAILABLE=false`
- `(no OKRs configured; OKR framing skipped)` — when `OKRS_AVAILABLE=false`
- `(no Issue templates found; used built-in section shape)` — when the fallback section structure was used

In caller mode, also return the action label (`created` / `commented` / `closed` / `commented-positive` / `created-possible-duplicate`), the resulting Issue number, and the resulting Status value (or `no-change` for comment-only paths), so the caller can record it.

---

## Guidelines

- **`observe says: ` prefix on every body and comment.** No exceptions. Provenance is the only way to tell skill-authored content from developer-authored content when both run as the same GitHub user.
- **Bulk-fetch + local-filter.** One `gh issue list` per run (plus pagination). Never loop `gh issue view`. Bulk fetch is the performance lever; per-Issue calls regress us versus the old file-based model.
- **Match on root cause, not symptom.** See the Gotcha in Phase 3. If you can't tell the difference, prefer no-match and let a possible-duplicate note carry the uncertainty.
- **No fix recommendation in the Issue body.** `observe` files what happened, not what to do about it. Fix recommendations belong in higher-level triage (which has time to think about it) or in the developer's manual review.
- **Caller mode never prompts.** Default to "create new Issue with possible-duplicate note" on any ambiguity. The caller is responsible for any upstream confirmation.
- **Positive observations on no-match: drop.** A positive observation with no matching open Issue carries no information the system can act on. Don't create an Issue just to say "thing worked correctly."
- **Same-root-cause line is always present** on Issue-comment actions (5b/5c/5d/5f). It's how the decision is auditable.
- **Autonomous close is a real action.** Phase 5d closes the Issue. Use it only when the high-confidence cut in Phase 4 is met. Anyone reopening a wrongly-closed Issue will see the closing comment's evidence and judge for themselves.
- **Date strings come from the shell at invocation time** (`date +%Y-%m-%d`). Never hardcode dates in the SKILL.md prompts or in body/comment text — the templates above use `2026-05-21` as a placeholder; the skill substitutes the actual date when running.
- **Project Status is the canonical state.** Labels no longer encode lifecycle state in this skill. Status writes are tied to specific actions in Phase 5 (5a, 5c, 5d); comment-only paths (5b, 5f) never change Status.
- **Dynamic project-ID resolution.** Project node ID, Status field ID, and option IDs are looked up once per run via `gh project view`/`field-list` so the system survives a project recreation. Project number, owner, Status field name, and Status option names come from `.facto/settings.json` in the host repo via `bin/facto-helper.sh`.
- **Graceful degradations are not errors.** Missing project board, missing OKRs path, and missing Issue templates are all supported operating modes. The final report notes what was skipped; the skill continues to file structured Issues in all cases.
