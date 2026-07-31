#!/bin/bash
# template-task-spec.test.sh — structural tests for template-task-spec.html
#
# The design-mock template (../template-task-spec.html) is filled in by
# facto:ref-design-mock to produce a per-feature design mock. This suite
# guards the load-bearing structural markers the skill and the rendered
# mock depend on — e.g. that a flow-band connector can render a caption
# describing the action that triggers the transition, and that the
# template stays project-agnostic (placeholder tokens, not baked-in
# product values).
#
# These assertions are pinned to specific markers in the template today.
# A future edit to the template should either preserve those markers or
# update this test deliberately — it is not meant to be a loose contract.
#
# Cases 5-8 pin to short marker phrases inside the flow band's and the
# components band's header comments: "once per flow", the band label's
# "Flow — " form, the overlay rule's "drawn as the full screen with the
# overlay over it" / "never as a bare frame", and the components band's
# flow-overlay scope boundary. These phrases are load-bearing the same way —
# a future prose edit to those comments must preserve them or update this
# test deliberately.
#
# This suite only reads the template; it creates nothing and leaves
# nothing behind.

set -uo pipefail  # not -e: we want to run every case and tally failures

# --- Resolve the template under test relative to this file's location ---
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TEMPLATE="${_TEST_DIR}/../template-task-spec.html"

if [[ ! -f "$_TEMPLATE" ]]; then
  echo "FAIL: template under test not found: $_TEMPLATE" >&2
  exit 1
fi

_FAILS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; _FAILS=$((_FAILS + 1)); }

# ── Case 1: .connector-label is defined in the <style> block ───────────────
if grep -qE '^[[:space:]]*\.connector-label[[:space:]]*\{' "$_TEMPLATE"; then
  pass ".connector-label rule is defined"
else
  fail ".connector-label rule not found in <style>"
fi

# ── Case 2: .connector sets flex-direction: column ──────────────────────────
# Anchor on the exact selector "  .connector {" — the pattern requires " {"
# immediately after ".connector", so ".connector-label {" cannot match.
_connector_block="$(awk '
  /^  \.connector \{/ { flag=1; next }
  flag && /^  \}/ { exit }
  flag { print }
' "$_TEMPLATE")"

if [[ -n "$_connector_block" ]] && grep -q 'flex-direction: *column' <<<"$_connector_block"; then
  pass ".connector sets flex-direction: column"
else
  fail ".connector block missing or does not set flex-direction: column"
fi

# ── Case 3: at least one RENDERED connector-label span in the board markup ──
# The bug this guards is the label being present but commented out, which is
# how the template shipped before — a trigger action written as an HTML comment
# renders nothing but a bare arrow. So strip HTML comments (including multi-line
# ones) before looking for the span; a plain grep would happily match the
# commented-out form and report the capability as present.
_markup="$(awk '
  {
    line = $0; out = ""
    while (1) {
      if (incomment) {
        p = index(line, "-->")
        if (p == 0) { line = ""; break }
        line = substr(line, p + 3); incomment = 0
      } else {
        p = index(line, "<!--")
        if (p == 0) { out = out line; break }
        out = out substr(line, 1, p - 1); line = substr(line, p + 4); incomment = 1
      }
    }
    print out
  }
' "$_TEMPLATE")"

if grep -q 'class="connector-label"' <<<"$_markup"; then
  pass "a rendered <span class=\"connector-label\"> exists in the board markup"
else
  fail "no rendered <span class=\"connector-label\"> in the board markup (commented out?)"
fi

# ── Case 4: project-agnostic invariant — the token blocks still carry ───────
# placeholder tokens, not baked-in product values (see the PROJECT-AGNOSTIC
# WARNING in the template's header comment). Two things are checked, both
# scoped to the :root and .t-dark blocks — the phrase and the token names also
# appear in prose above them, so an unscoped grep would pass on a filled-in
# copy:
#   a) the "replace-from-design-system" group markers that tell the skill which
#      values to replace at fill time are still there, and
#   b) a sample of the neutral default values is unchanged. The markers are
#      group-header comments, so on their own they survive someone pasting a
#      brand palette in underneath them — pinning the values is what actually
#      catches that.
_root_block="$(awk '
  /^  :root \{/ { flag=1; next }
  flag && /^  \}/ { exit }
  flag { print }
' "$_TEMPLATE")"

_root_markers="$(grep -c 'replace-from-design-system' <<<"$_root_block")"

_dark_block="$(awk '
  /^  \.t-dark \{/ { flag=1; next }
  flag && /^  \}/ { exit }
  flag { print }
' "$_TEMPLATE")"

_root_defaults_ok=1
for _tok in '--color-primary: *#0057b7' '--color-bg: *#fafafa' '--color-text: *#1a1a1a'; do
  # "--" so the leading dashes of the token name are not parsed as grep options
  grep -qE -- "$_tok" <<<"$_root_block" || _root_defaults_ok=0
done
# .t-dark carries the dark-theme half of the same palette — same invariant.
for _tok in '--color-bg: *#111111' '--color-text: *#f2f2f7'; do
  grep -qE -- "$_tok" <<<"$_dark_block" || _root_defaults_ok=0
done

if [[ -z "$_root_block" ]] || [[ -z "$_dark_block" ]] || [[ "$_root_markers" -lt 5 ]]; then
  fail ":root or .t-dark block missing, or the replace-from-design-system markers are gone (found $_root_markers, expected >= 5)"
elif [[ "$_root_defaults_ok" -ne 1 ]]; then
  fail ":root/.t-dark neutral default token values have been replaced with product values"
else
  pass ":root and .t-dark carry placeholder markers ($_root_markers) and neutral default token values"
fi

# ── Case 5: band-1 header states the per-flow duplication instruction ──────
if grep -q 'once per flow' "$_TEMPLATE"; then
  pass "band-1 header states the per-flow duplication instruction"
else
  fail "band-1 header missing the per-flow duplication instruction ('once per flow')"
fi

# ── Case 6: band label uses the "Flow — <name>" form ────────────────────────
if grep -q 'class="band-label">Flow — <!-- TODO: flow name -->' "$_TEMPLATE"; then
  pass "band-1 label uses the 'Flow — <flow name>' form"
else
  fail "band-1 label does not use the 'Flow — <flow name>' form"
fi

# The band used to be framed as the happy path, which is what let every other
# flow drift into the components band. Band 1 now carries one deliberate
# mention — "there is no primary or happy-path flow" — so this checks that
# every occurrence is that instruction, rather than banning the phrase
# outright. Both spellings are matched: the old header comment said
# "happy-path", the old sublabel said "happy path".
# Flatten to one line first: the guard phrase is inside a wrapped comment, so a
# line-by-line check would misfire the moment someone re-wraps it without
# changing a word.
_flat="$(tr '\n' ' ' < "$_TEMPLATE" | tr -s ' ')"
_happy_total="$(grep -oiE 'happy[ -]path' <<<"$_flat" | grep -c .)"
_happy_allowed="$(grep -oiE 'there is no primary or happy-path flow' <<<"$_flat" | grep -c .)"
_happy_stray=$((_happy_total - _happy_allowed))

if [[ "$_happy_stray" -eq 0 ]]; then
  pass "no band is framed as the happy path"
else
  fail "the template frames a band as the happy path ($_happy_stray stray mention(s))"
fi

# ── Case 7: band-1 header states the overlay rule ───────────────────────────
# "never as a bare frame" is the tail of the sentence "...is drawn as the
# full screen with the overlay over it, never as a bare frame." — pinning to
# this shorter tail keeps the marker on a single wrapped comment line.
if grep -q 'never as a bare frame' "$_TEMPLATE"; then
  pass "band-1 header states the overlay rule"
else
  fail "band-1 header missing the overlay rule"
fi

# ── Case 8: components band states the flow-overlay scope boundary ─────────
if grep -q "belongs in that flow's band" "$_TEMPLATE"; then
  pass "components band header states the flow-overlay scope boundary"
else
  fail "components band header missing the flow-overlay scope boundary"
fi

# ── Tally ────────────────────────────────────────────────────────────────────
echo ""
if [[ "$_FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "$_FAILS test(s) FAILED"
  exit 1
fi
