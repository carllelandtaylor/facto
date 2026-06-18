---
name: status
description: "Show the current state of the Facto improvement memory: open GitHub Issues grouped by Project Status, counts of recently-closed Issues, plus OKR status from OKRS.md. Read-only. Invoke with /facto-dev:status. Procedure skill (follow the phases in order)."
disable-model-invocation: true
color: yellow
---

# Facto Improvement: Status

> **Model:** when run as a subagent, prefer `model: sonnet`.

One-shot summary of the improvement memory. Lists open GitHub Issues on the configured tracker repo (see `.facto/settings.json`) grouped by Project Status (Backlog / In progress / In review / In test), a count of recently-closed Issues by reason, plus OKR status from `OKRS.md`. Flags attention items (stalled In review or In test Issues, Backlog Issues with many comments).

This skill is **read-only** — it does not modify any Issues, labels, OKRs, or files. It exists to give the developer a quick view of where the loop stands before deciding what to run next (e.g. `/facto-dev:think` to walk open Issues, `/facto-dev:observe` to file something new).

For the full memory model, see `DEVELOPMENT.md` §3.4 in the Facto repo.

## Setup: Resolve the Facto Repo + GitHub Repo + `gh` auth

```bash
FACTO_REPO="${FACTO_REPO:-$(cd "$(dirname "$(readlink -f ~/.claude/skills/facto-dev/skills/status/SKILL.md)")"/../../../.. && pwd)}"
test -f "$FACTO_REPO/.facto/settings.json" || { echo "ERROR: Facto repo not found at '$FACTO_REPO'. Set FACTO_REPO to your Facto checkout (run /facto-dev:setup-facto-dev once)." >&2; exit 1; }
REPO_SLUG="$(facto-helper.sh --root "$FACTO_REPO" tracker.field repo)"
test -n "$REPO_SLUG" || { echo "ERROR: could not derive REPO_SLUG from $FACTO_REPO" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh CLI is not authenticated. Run 'gh auth login' and re-try." >&2; exit 1; }
```

(`gh repo view` does not accept `-R` with a local directory path. The subshell derives the slug from the Facto repo's git remote without changing cwd.)

### Resolve the GitHub Project + Status field

facto-dev:status reads Status; never writes. The `set_issue_status` helper from facto-dev:observe/facto-dev:think is not needed here.

```bash
PROJECT_OWNER="$(facto-helper.sh --root "$FACTO_REPO" tracker.field project.owner)"
PROJECT_NUMBER="$(facto-helper.sh --root "$FACTO_REPO" tracker.field project.number)"
PROJECT_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field project.name)"
STATUS_FIELD_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field status_field)"
STATUS_BACKLOG_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field status_values.backlog)"
STATUS_IN_PROGRESS_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field status_values.in_progress)"
STATUS_IN_REVIEW_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field status_values.in_review)"
STATUS_IN_TEST_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field status_values.in_test)"
STATUS_DONE_NAME="$(facto-helper.sh --root "$FACTO_REPO" tracker.field status_values.done)"
IGNORE_LABELS_JSON="$(facto-helper.sh --root "$FACTO_REPO" tracker.field labels.ignore)"

PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json | jq -r .id)" \
  || { echo "ERROR: cannot read project $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
test -n "$PROJECT_ID" || { echo "ERROR: project ID is empty for $PROJECT_OWNER/projects/$PROJECT_NUMBER" >&2; exit 1; }
```

Rationale: facto-dev:status never writes Status, so the Status field option IDs (`STATUS_*_ID`) are not needed and are not resolved. `PROJECT_ID` is resolved here because it is needed if the fallback `gh project item-list` path is taken in Phase 1. Status option names are read directly from `.status.name` in the `projectItems` JSON without needing the option IDs. All tracker configuration (project number, owner, status field name, status option names, and ignore labels) is sourced from `.facto/settings.json` in the Facto repo — the single source of truth for Facto tracker settings. The `--root "$FACTO_REPO"` flag passed to each `facto-helper.sh` call locks the config lookup to Facto's `.facto/settings.json` regardless of which repo this skill is invoked from.

---

## Phase 1: Gather State (two bulk Issue fetches + OKRs file)

Two `gh issue list` calls — one for all open Issues, one for recently-closed — never loop `gh issue view` per Issue:

```bash
# Fetch 1: all open Issues (no date filter — must be complete)
gh -R "$REPO_SLUG" issue list \
  --state open \
  --json number,title,labels,updatedAt,comments,projectItems \
  --limit 200

# Fetch 2: recently-closed Issues (last 30 days)
THIRTY_DAYS_AGO="$(date -d '30 days ago' +%Y-%m-%d)"
gh -R "$REPO_SLUG" issue list \
  --state closed \
  --search "is:issue closed:>=$THIRTY_DAYS_AGO" \
  --json number,title,state,stateReason,labels,updatedAt,closedAt,comments,projectItems \
  --limit 200
```

If either call returns 200 records, paginate: for open Issues, append `--search "updated:<$OLDEST_UPDATED_AT"` and repeat (incrementing the upper bound each page); for closed Issues, adjust the `closed:` range the same way. Concatenate pages locally.

Note: Fetch 1 must be `--state open` without a date filter to guarantee all open Issues are returned — a date-filtered `--state all` query will silently drop open Issues that have had no activity in 30+ days.

To extract the Status for each Issue: inspect the Issue's `projectItems` array, find the entry whose `title == $PROJECT_NAME`, and read `.status.name`. The actual JSON shape is `{"projectItems":[{"status":{"optionId":"…","name":"Backlog"},"title":"<project name>"}]}` — `status` is an object with `optionId` and `name`, so the human-readable column name is at `.status.name`. Example jq: `.projectItems[] | select(.title == $name) | .status.name` (with `--arg name "$PROJECT_NAME"`). If an Issue is not a member of the project (no matching entry), or `.status` is `null`, treat its Status as `$STATUS_BACKLOG_NAME` for display purposes.

**Working inline filter.** To annotate every Issue with its Status in one pass, collect matches into an array and take `first`, then fall back to `$STATUS_BACKLOG_NAME` — never place `//` directly after a parenthesized expression inside an object value, jq's parser rejects it (`syntax error, unexpected //, expecting '}'`):

```bash
jq --arg name "$PROJECT_NAME" --arg backlog "$STATUS_BACKLOG_NAME" \
  '[.[] | . + {projectStatus: (([.projectItems[] | select(.title == $name) | .status.name] | first) // $backlog)}]'
```

Fallback: if `projectItems` is absent or empty across all Issues, run `gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --limit 200` and merge on `content.number`.

Also read OKRs from the file:

```bash
cat "$FACTO_REPO/OKRS.md"
```

Parse each `## <slug> <dot>` section to extract: the slug, the objective-level status dot (🟢 / 🟡 / 🔴 / ❓), the `**Description:** ...` line, the `**Last updated:** ...` line, and the markdown table of KRs (two columns: `Target (KR)` and `Current status`). Each KR row carries its own status dot in the Current status cell. Survey-measured KRs are flagged with 📋 in the Target cell. **Do not assess or compute any status — this skill is read-only and prints whatever is on disk.**

Status legend (from the file): 🟢 = meeting the goal with positive evidence; 🟡 = partial / some signal, some gaps; 🔴 = clearly not meeting, or unmeasured; ❓ = KRs not yet defined for this objective. The objective-level dot is the worst of its KR-level dots, set by the developer's manual edits to `OKRS.md` (no skill auto-grades OKRs in the current model).

If `OKRS.md` is missing, the OKR section in Phase 3 simply notes "OKRS.md not found" and the rest of the report continues normally.

---

## Phase 2: Compute Attention Items

While walking the fetched Issues, flag the following. Today's date comes from `date +%Y-%m-%d`.

- **Stalled In review or In test Issues** — open Issues whose Status is `In review` or `In test` and whose most-recent comment is more than **14 days** old (or which have no comments since they entered that Status). The review or testing is going on too long without observed signal.
- **Backlog candidates ready to move** — open Issues in `Backlog` Status with **more than 3 comments**. High comment count suggests enough evidence has accumulated for a fix direction to be proposed or work to begin.
- **Stale OKR statuses** — OKRs in `OKRS.md` whose `**Last updated:** ...` date is more than 30 days before today (or whose value is still `_n/a_` and `OKRS.md` was created more than 30 days ago), **excluding** OKRs whose objective-level dot is ❓ (those have no KRs yet and are intentionally not assessed).

These thresholds are intentionally rough — they're hints, not rules. Don't suppress an Issue from the main listing just because it's flagged for attention. Labels in `$IGNORE_LABELS_JSON` (from `.facto/settings.json`) are ignored everywhere — they're plan-validation markers, not Facto state.

---

## Phase 3: Report

Print a single report. Suggested layout:

```
Facto improvement memory — status as of <YYYY-MM-DD>

OKR Status
  - <slug> <objective dot>: <description> — last updated <date>
    KRs:
      <kr dot> <target text (truncated if long)>
      ...
  - <slug> ❓: <description> — KRs not yet defined
  ...
  (or: "OKRS.md not found." if the file is missing)

Open Issues
  Backlog (N):
    - #<num> — <title>
  In progress (N):
    - #<num> — <title>
  In review (N):
    - #<num> — <title>
  In test (N):
    - #<num> — <title>

Recently closed (last 30 days): <X> completed, <Y> not-planned

Attention
  - #<num> — <one-line reason>
  ...
  (or: "Nothing flagged.")
```

Rules:
- The **OKR Status** section is always shown — print each objective dot, description, last-updated line, and per-KR dot **verbatim** from `OKRS.md`. Do not reformat or recompute. Show OKRs with objective-level ❓ in their own line with the description; skip their KR table and last-updated line (they have neither).
- **Open Issues** groups by Status in column order: Backlog, In progress, In review, In test. Order within each group by `updatedAt` descending. Title truncated to ~80 chars. Subgroups with zero entries are omitted (e.g. if no Issues are In review, that subgroup is dropped entirely).
- **Recently closed** is a count by close reason. Details available on github.com; do not list each Issue.
- **Attention** lists each flagged Issue with a one-line reason. If nothing is flagged, print "Nothing flagged." Sections with zero entries are omitted **except** OKR Status (always shown, even if every objective is ❓).

---

## Guidelines

- **Read-only.** No `gh issue comment`, `gh issue close`, `gh issue edit`, `gh label`, `gh project item-edit`, no file writes. If the developer asks the skill to act on what it found, point them at `/facto-dev:think`, `/facto-dev:observe`, or manual `gh issue ...` rather than doing it from here.
- **List, don't summarize.** Show titles. The developer can open Issues on github.com for detail.
- **One-line entries.** Multi-line per Issue kills scannability.
- **Bulk-fetch + local-filter.** One `gh issue list` (plus pagination). Never loop `gh issue view`. This is the performance lever; per-Issue calls regress us versus the old file-based model. The bulk fetch includes `projectItems` in the JSON so that Status is available locally without extra per-Issue calls.
- **Comment bodies are not analyzed.** The `comments` field is fetched to get comment count and `createdAt` dates (needed for the stalled-in-review/in-test attention check). Comment text is not read or displayed — the full body is for `/facto-dev:think` to read.
- **OKR Status is read-only and verbatim.** This skill never computes or updates status dots — the developer does that manually on `OKRS.md`. facto-dev:status just opens the file and prints what it finds.
- **Ignore-label filtering.** Labels listed in `$IGNORE_LABELS_JSON` (sourced from `.facto/settings.json`) are invisible — filter Issues whose labels intersect this list out of every section so test data never pollutes the production status view. Example jq filter: `select([.labels[].name] | any(. as $l | $ignore | index($l)) | not)` with `--argjson ignore "$IGNORE_LABELS_JSON"`.
- **Project Status drives Open-Issues grouping.** Labels no longer encode lifecycle state. Status is read from each Issue's `projectItems` (the configured project's membership) and used as the primary group axis.
- **Dynamic project-ID resolution.** Same as facto-dev:observe/facto-dev:think — project number, owner, status field name, and status option names all come from `.facto/settings.json` via `facto-helper.sh`. Project node ID and field IDs are resolved at run time via `gh project view` and `gh project field-list`.
