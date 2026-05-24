# Story 002: HUD — Resource Bar, Energy, Time Controls

> **Epic**: UI System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**UX Spec**: `design/ux/hud.md`
**TR-IDs**: TR-hud-001, TR-hud-002, TR-hud-003, TR-hud-004

**ADR Governing Implementation**: ADR-0003: Input Context System (WORLD_ACTIVE by default, UI context for HUD controls)

**Engine**: Godot 4.6 | **Risk**: LOW — Godot Control node system is stable. Post-cutoff APIs used: none.

**Control Manifest Rules (this layer)**:
- Required: UI screens use scene-based navigation
- Guardrail: Input context must switch to `WORLD_ACTIVE` when HUD is visible during gameplay

---

## Acceptance Criteria

*From UX spec `design/ux/hud.md`:*

- [ ] **AC-HUD-01**: No HUD element occupies the center 60% horizontal × 40% vertical of the gameplay view
- [ ] **AC-HUD-02**: Top band is exactly 64px height on all supported resolutions
- [ ] **AC-HUD-03**: All screen-space HUD elements remain anchored to screen edges during window resize
- [ ] **AC-HUD-06**: Tab key cycles through top band focusable elements in order: Tick Speed → Play/Pause → Storage Panel
- [ ] **AC-HUD-07**: D-pad cycles top band in same order; A button activates; B/back dismisses building detail view
- [ ] **AC-HUD-08**: Escape key dismisses building detail view and closes building placement menu
- [ ] **AC-HUD-09**: All HUD text meets WCAG AA 4.5:1 contrast ratio
- [ ] **AC-HUD-10**: Warning and alert states are distinguishable without color
- [ ] **AC-HUD-11**: No HUD text renders below 14px minimum font size
- [ ] **AC-HUD-13**: During dialogue/cutscene, world-space HUD elements are hidden
- [ ] **AC-HUD-15**: Toast queue drops oldest when 4th toast arrives (FIFO, max 3)
- [ ] **AC-HUD-17**: Food status indicator shows "Unlimited" when NPC count is 0
- [ ] **AC-HUD-18**: Debuff indicator appears within one frame of hunger state change

---

## Implementation Notes

*Derived from UX spec `design/ux/hud.md` and ADR-0003:*

### Scene Structure

Create `res://ui/hud/hud.tscn` — a persistent scene loaded with every gameplay session:

```
hud (CanvasLayer)
├── top_band (Control)                    — Zone 1: 64px fixed height, full width
│   ├── day_display (Control)             — Element 1: day number + tick progress bar
│   │   ├── day_label (Label)             — "Day 12"
│   │   └── progress_bar (TextureProgressBar)
│   ├── tick_controls (Control)           — Element 2: speed buttons + play/pause
│   │   ├── speed_indicator (Label)       — "1x"
│   │   └── play_pause_btn (Button)      — play/pause toggle
│   ├── npc_count_label (Label)           — Element 3: "3/5 NPCs"
│   ├── food_status_label (Label)         — Element 4b: "Food: 3 days" / "Unlimited"
│   ├── debuff_indicator (Control)        — Element 4c: hidden by default
│   │   ├── hunger_icon (TextureRect)     — 24px red ⚠
│   │   └── debuff_text (Label)           — "HUNGRY"
│   ├── resource_warnings (Control)       — Element 7: warning icons
│   │   └── warning_icons (HBoxContainer) — 24×24px icons
│   └── energy_bar (Control)              — Element 4: horizontal fill bar
│       ├── energy_background (TextureRect)
│       ├── energy_fill (TextureRect)      — color-coded fill
│       └── energy_label (Label)           — "45/100"
├── storage_panel (Control)               — Zone 3: top-right collapsible panel
│   ├── storage_toggle (Button)           — collapses/expands panel
│   ├── collapsed_state (Label)            — "Used: 4/12"
│   └── expanded_state (VBoxContainer)     — per-resource list (hidden when collapsed)
│       └── resource_rows (VBoxContainer)
│           └── resource_row (Control)     — icon + label + count
├── toast_container (Control)             — Zone 4: bottom-right
│   └── toast_stack (VBoxContainer)        — max 3 toasts, FIFO eviction
│       └── toast_item (Panel)            — transient message
├── building_detail_panel (Control)       — Element 10: right-side fixed panel (hidden)
│   ├── header (Label)
│   ├── npc_assignment (Control)
│   ├── input_slots (Control)
│   └── output_slots (Control)
├── placement_ghost (Sprite2D)            — Element 12: build mode preview (world-space)
└── construction_preview (Sprite2D)       — Element 13: under construction (world-space)
```

### Signal Bindings

Subscribe to system signals from the HUD root node:

| Signal | Source | Handler | Elements |
|--------|--------|---------|----------|
| `ticks_advanced(delta)` | TickSystem | Update progress bar, day counter | Day Display |
| `speed_changed(speed)` | TickSystem | Update speed indicator | Tick Speed |
| `pause_state_changed(running)` | TickSystem | Toggle play/pause icon | Play/Pause |
| `energy_changed(current, max)` | PlayerCharacter | Update energy bar fill + label | Energy Bar |
| `hunger_state(fed, food_available, food_required)` | HungerSystem | Update food status, show/hide debuff | Food Status, Debuff |
| `npc_count_changed(count)` | NPCSystem | Update NPC count label | NPC Count |
| `storage_capacity_changed(used, total)` | InventorySystem | Update storage panel | Storage Panel |
| `resource_count_changed(id, quantity)` | InventorySystem | Update expanded resource rows | Storage Panel (expanded) |
| `toast_request(level, message)` | Any system | Push toast to queue | Toast Container |
| `production_state_changed(id, state)` | BuildingSystem | Show/hide production warning | Production Warning |

### Top Band Layout (64px height, 2 rows of 32px)

Row 1 (top 32px): Day counter + Tick progress + Tick speed + Play/Pause + NPC count
Row 2 (bottom 32px): Food status + Debuff indicator + Resource warnings + Energy bar

All elements anchored to screen edges via `AnchorPreset` (AnchorTop, AnchorLeft/Right).

### Energy Bar Color States

| Range | Color | Pattern |
|-------|-------|---------|
| 50-100% | `#4CAF50` green | Solid fill |
| 30-49% | `#FFC107` yellow | Diagonal hatch overlay |
| 10-29% | `#FF9800` orange | Crosshatch overlay |
| 0-9% | `#E05555` red | Pulsing X pattern + skull icon |

Color transitions: 300ms ease-out animation.

### Toast System

- Max 3 toasts visible simultaneously
- FIFO eviction: 4th toast → remove oldest → add new
- Auto-dismiss after 3000ms
- Color-coded: yellow=warning, red=alert, green=success
- Stacks vertically in bottom-right corner
- Each toast has a 300ms fade-in and fade-out

### Debuff Indicator

- Hidden by default (FED state)
- Shows "HUNGRY — actions slowed (2x tick cost)" when HUNGRY
- Appears within one frame of `hunger_state(fed=false)` signal
- Disappears on `hunger_state(fed=true)` transition
- Color: `#E05555` for icon and text

### "Unlimited" Food Status

- When NPC count == 0, food status shows "Unlimited"
- When NPC count > 0, shows "Food: X days" or "⚠️ Low food" (≤ 1 day)

---

## Out of Scope

*Handled by other stories or deferred to MVP:*

- Full resource breakdown projection (requires Resource System — not implemented in VS)
- Building detail view implementation (Building System story — only placeholder UI)
- NPC hunger alert icons (world-space) — deferred to NPC System story
- Production warning icons (world-space) — deferred to Building System story
- Notification Tray consolidation — deferred to MVP per `design/ux/hud.md` § Notification Tray
- Save/Load UI (no UI in VS for manual save)

---

## QA Test Cases

**Story Type**: UI
**Evidence required**: `production/qa/evidence/hud-evidence.md` — screenshot + walkthrough

- **AC-HUD-01**: Safe zone clearance
  - Setup: HUD loaded at 1920x1080 and 2560x1440
  - Verify: No HUD pixel in center 60% horizontal × 40% vertical
  - Pass condition: Zero HUD elements in safe zone at both resolutions

- **AC-HUD-02**: Top band height
  - Setup: Measure top band at 1920x1080 and 2560x1440
  - Verify: Height = 64px ± 0px
  - Pass condition: Exact 64px at both resolutions

- **AC-HUD-03**: Edge anchoring
  - Setup: Resize window from 1920x1080 to 1280x720 and back
  - Verify: All screen-space elements re-anchor, no clipping or overlap
  - Pass condition: All elements maintain edge anchoring at all sizes

- **AC-HUD-06**: Keyboard focus order
  - Setup: Main gameplay with HUD visible
  - Verify: Tab cycles: Tick Speed → Play/Pause → Storage Panel
  - Pass condition: Focus order matches specification, no missing elements

- **AC-HUD-07**: Gamepad navigation
  - Setup: Gamepad connected, HUD visible
  - Verify: D-pad cycles top band same order as keyboard; A activates; B dismisses detail
  - Pass condition: All interactions work, focus indicator visible

- **AC-HUD-08**: Escape dismiss
  - Setup: Open building detail view (placeholder)
  - Verify: Escape closes detail view
  - Pass condition: Detail view hidden after Escape

- **AC-HUD-09**: Text contrast
  - Setup: Inspect all HUD text elements
  - Verify: Primary text ≥ 10:1, button text = 3.8:1
  - Pass condition: All text meets WCAG AA requirements

- **AC-HUD-10**: Color-independent states
  - Setup: Grayscale screenshot of warning icons
  - Verify: Yellow ⚠ (warning) and red ✕ (alert) remain distinguishable
  - Pass condition: Icon shapes differ, not just color

- **AC-HUD-11**: Minimum font size
  - Setup: Inspect all HUD text elements
  - Verify: No text below 14px
  - Pass condition: Minimum font = 14px

- **AC-HUD-15**: Toast FIFO eviction
  - Setup: Trigger 4 toasts simultaneously within 100ms
  - Verify: Exactly 3 toasts visible; oldest is dropped
  - Pass condition: FIFO eviction works correctly

- **AC-HUD-17**: Unlimited food
  - Setup: New game with 0 NPCs
  - Verify: Food status shows "Unlimited"
  - Pass condition: Text reads "Unlimited", not a number

- **AC-HUD-18**: Debuff indicator timing
  - Setup: NPC count > 0, then trigger hunger state change
  - Verify: Debuff indicator appears within one frame
  - Pass condition: Instant appearance, no visible delay

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/hud-evidence.md` — screenshot walkthrough of all HUD elements at multiple resolutions, focus order verification

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Tick System (ticks_advanced, speed_changed, pause_state_changed), Player Character System (energy_changed), NPC System (npc_count_changed), Hunger System (hunger_state), Inventory System (storage_capacity_changed, resource_count_changed), Building System (production_state_changed, build_mode_entered/exited)
- Unlocks: None — HUD is self-contained presentation layer
