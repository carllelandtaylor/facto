<!--
  facto:setup-design inventory template.

  Duplicate the "## Surface: <surface-slug>" block once per surface. Fill this
  format — do not invent a different one.
-->

# Bootstrap inventory

**Repo root:** `<absolute path>`

## Surface: <surface-slug>

**Surface root:** `<absolute path>`

**Live screenshots:** Phase 2 saves them in this task's `inventory/` dir (`<task dir>/inventory/<view-slug>--<state>.png`) — the per-state diff targets Phase 3 verifies against.

### Commands
**Launch the app:**
...

**Interact with the running app:**
...

**Take a screenshot:**
...

**Other notable commands:**
<!-- Delete this if none -->
...

### Device profile
<!-- Used to build device-accurate mocks (1 CSS px == 1 dp/pt). -->
| Property | Value |
|----------|-------|
| Resolution (px) | `<W>×<H>` |
| Density | `<dpi>` (or `@2x`/`@3x` scale) |
| Device scale factor (dsf) | `<density/160, or scale>` |
| Logical size (dp/pt) | `<W>×<H>` |
| Geometry source | `<e.g. adb uiautomator dump / getBoundingClientRect>` |

### Existing design assets
| Asset name | Path/Pattern | Notes |
|------------|--------------|-------|
| … | … | … |

### Views
<!-- Screenshots live in this task's inventory/ dir, one per state, named <view-slug>--<state>.png -->

| Kind | Name/slug | Route or trigger | States | State screenshots | Notes |
|------|-----------|------------------|--------|-------------------|-------|
| screen | … | … | default, loading, empty, error | `<view-slug>--default.png`, … | unreachable states, etc. |
| region | … | … | … | … | … |
| overlay | … | … | … | … | … |

<!-- Duplicate the "## Surface:" block above for each additional surface. -->
