# Commit Message Template

All commits must follow this format:

```
Short descriptive message

Context:
Brief explanation of why this change exists. If new libraries, APIs,
or services are introduced, explain what they are and why they were
chosen. If an existing pattern is being extended, note that.
Keep it to 2-5 lines — enough for a developer reading `git log` to
understand the change without reading the diff.

Verification:
Automated:
  <exact command to run>
Manual:
  <numbered steps to manually verify, what to look for, expected result>
```

**Omit the Verification section** for changes that are trivially correct and don't need verification — e.g., documentation-only changes, adding comments, config tweaks that don't affect behavior. When in doubt, include it.

## Examples

```
Add webhook retry with exponential backoff

Context:
Users reported missed webhook deliveries when downstream services had
brief outages. Added retry logic using the `p-retry` library (chosen
for its simple API and configurable backoff). Retries up to 3 times
with exponential backoff (1s, 2s, 4s) before marking delivery as failed.

Verification:
Automated:
  npm test -- --grep "webhook retry"
  npm run lint
Manual:
  1. Trigger a webhook with the downstream service stopped
  2. Watch logs — should see 3 retry attempts with increasing delays
  3. Restart the downstream service — queued webhooks should deliver
```

```
Prevent duplicate form submissions on slow networks

Context:
The submit button remained active during API calls, allowing users to
click it multiple times and create duplicate records. Disables the
button on submit and re-enables on completion or error. Follows the
existing loading state pattern used in CheckoutForm.

Verification:
Automated:
  npm test -- --grep "SubmitButton"
Manual:
  1. Open Chrome DevTools > Network > Slow 3G
  2. Submit the form — button should disable immediately
  3. Wait for response — button should re-enable
  4. Check the database — only one record created
```

## When This Template Applies

- **New commits** — use this format
- **Amends** — if the existing commit message doesn't already follow this format, use `--amend` (without `--no-edit`) to rewrite it
- **Fixups** (`--fixup=<hash>`) — no message needed, git generates it automatically
