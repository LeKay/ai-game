# UX Spec: Inventory Screen

> **Status**: In Design
> **Author**: user + ux-designer
> **Last Updated**: 2026-05-31
> **Journey Phase(s)**: Mid-session management (transport planning, storage check, pre-build review)
> **Template**: UX Spec

---

## Purpose & Player Need

The inventory screen gives the player an immediate, scannable read of everything currently stored across all Storage Areas. The player arrives here to answer one question: **"What do I have?"** — before deciding to transport, build, assign an NPC, or eat. This screen is opened dozens of times per session; it must be fast to read, fast to close, and never require the player to do math to understand their situation. A full storage is visible at a glance; a dangerous gap (no food, low wood) is equally obvious. The screen does not allow direct action on items — it is a read-only dashboard that informs decisions made elsewhere (transport, building placement, production assignment).

---

## Player Context on Arrival

The player arrives mid-session with a specific question in mind — verifying resource counts before a decision. They were just in the game world (transporting, building, harvesting) and need a quick confirmation without losing their mental thread. First encounter: Day 1 after placing the first Storage Area and depositing their first items. Emotional state on arrival: **purposeful and focused** — the player wants one answer fast. They are not browsing. The screen should answer in one glance and be closed within 3–5 seconds in typical use. Arrival is always voluntary (player-triggered via `I` shortcut); the game never redirects the player here automatically.

---

## Navigation Position

This screen is a modal overlay accessible directly from the gameplay view at any time. It sits at: `Gameplay View → [I]` — no parent menu. It is always reachable and not gated by game state. The tick system is paused for the duration.

---

## Entry & Exit Points

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| Gameplay (any state) | Press `I` (toggle) | Current game state — tick system pauses on open |
| Gamepad | Dedicated inventory button | Same |

| Exit Destination | Trigger | Notes |
|---|---|---|
| Gameplay View | Press `I` again, press `Escape`, or click outside modal | Tick system resumes. No state changes — screen is read-only. |

---

## Layout Specification

### Information Hierarchy

1. **Item blocks** (resource type + total quantity) — primary content, occupies the majority of the screen. This is the answer to "what do I have?"
2. **Capacity summary bar** — always-visible header beneath the tabs. Contextualizes the item list ("how full am I overall?").
3. **Tab bar** — structural navigation at the top. Switches main content area between Inventory / Crafting / Buildings / NPCs.

### Layout Zones

**Zone 1 — Tab Bar** (fixed top, 40px height)
Tab buttons for Inventory / Crafting / Buildings / NPCs. Active tab has `#F0EDE6` fill with `#3A3A3A` text. Inactive tabs use `#5A5A5A` fill, `#A8A49C` text. Close button `×` anchored far right (same visual as inactive tab button). Tab bar does not scroll.

**Zone 2 — Capacity Bar** (fixed, 36px, immediately beneath tab bar)
Displays: `Storage: [occupied] / [total] slots` with a horizontal fill bar. Color-coded to match the slot utilization thresholds from `inventory-storage-system.md` Formula 6: green (0–74%), amber (75–89%), red (90–100%). Does not scroll — always visible above the item grid.

**Zone 3 — Item Grid** (fills remaining height, scrollable vertically)
Fluid grid of item blocks. Blocks represent unique resource types aggregated across all Storage Areas. Blocks wrap left-to-right; new rows form as blocks overflow the available width. Vertical scroll activates when rows exceed the visible area. No empty slot placeholders — only resources currently in storage appear.

### Component Inventory

| Component | Zone | Interactive | Data Source | Pattern Reference |
|-----------|------|-------------|-------------|-------------------|
| Tab buttons (Inventory / Crafting / Buildings / NPCs) | Zone 1 | Yes — click to switch content | Static (tab names are fixed labels) | Tabbed Navigation (Pattern 9) |
| Close button `×` | Zone 1 | Yes — click or `Escape` to close | — | — |
| Capacity bar label `Storage: X / Y slots` | Zone 2 | No | Inventory System — `get_capacity()` aggregated across all containers | Resource Counters (Pattern 4) |
| Capacity fill bar | Zone 2 | No | Inventory System — utilization ratio (Formula 6) | — |
| Item block (icon + quantity) | Zone 3 | No (read-only in this release) | Inventory System — aggregated `resource_id → total_quantity` across all containers | — |
| Scroll area | Zone 3 | Yes — mouse wheel / trackpad | — | — |
| Empty state label | Zone 3 | No | Shown when 0 items in storage | — |

### Item Block Specification

| Property | Value |
|----------|-------|
| Block width | 72px |
| Block height | 84px |
| Icon size | 48×48px, centered in upper 60px of block |
| Quantity label | `×N` format, Silkscreen 14px, `#F0EDE6`, centered below icon |
| Block background | `#2a2a2a`, 1px border `#4a4a4a` |
| Hover state | Border becomes `#A8A49C` |
| Block gap | 8px horizontal and vertical |
| Content padding | 16px inside modal on all sides |

### Modal Dimensions

| Property | Value |
|----------|-------|
| Width | 900px, centered horizontally |
| Vertical position | Centered vertically |
| Min height | 300px |
| Max height | ~600px (item grid scrolls if overflow) |
| Background | `#1a1a1a` at 95% opacity, 4px corner radius |
| Backdrop | `#000000` at 40% opacity, click to close |
| At 1920×1080 | ~510px game world visible on each side |

### ASCII Wireframe

```
                ┌──────────────────────────────────────────── ×┐
                │ [Inventory] │ Crafting │ Buildings │ NPCs      │  ← Tab bar (Zone 1)
                ├──────────────────────────────────────────────┤
                │  Storage: 45 / 150 slots  [██████░░░░]  30%  │  ← Capacity bar (Zone 2)
                ├──────────────────────────────────────────────┤
                │                                              │  ↑
                │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐       │  │
                │  │  🪵  │ │  🪨  │ │  🫐  │ │  🌿  │ ...  │  │ Item grid
                │  │  ×5  │ │  ×3  │ │  ×12 │ │  ×2  │       │  │ (Zone 3,
                │  └──────┘ └──────┘ └──────┘ └──────┘       │  │ scrollable)
                │                                              │  │
                │  ┌──────┐ ┌──────┐                          │  │
                │  │  ⚒   │ │  🧵  │                          │  ↓
                │  │  ×1  │ │  ×8  │                          │
                └──────────────────────────────────────────────┘
```

**Data model note — per-type aggregation:** The GDD defines storage as individual slots per container (`InventorySlot.resource_id + quantity`). This screen aggregates across all containers: for each unique `resource_id`, total quantity = sum of all slot quantities across all `InventoryContainer` instances on the map. This is the correct display for a combined global view. The per-slot detail view (showing individual slots and stack progress) is reserved for a future per-container detail panel (e.g., when clicking a specific Storage Area on the map).

**Deviation from GDD storage panel spec:** The `inventory-storage-system.md` UI Requirements section specifies a 10-column slot grid with empty slot placeholders. This screen intentionally shows only occupied resource types with no empty slots — consistent with the "combined global view" and "read-only dashboard" design decisions. The fixed-column slot grid is appropriate when the player opens a single container; it is not appropriate for an aggregated multi-container summary.

---

## States & Variants

| State / Variant | Trigger | What Changes |
|----------------|---------|--------------|
| **Default** | ≥1 item in any storage container | Item grid shows all resource type blocks. Capacity bar shows current utilization. |
| **Empty** | 0 items across all containers | Zone 3 shows centered text: `"No items in storage yet"`. Capacity bar shows `0 / 50 slots` (or current max). No item blocks rendered. |
| **Full** | Capacity utilization ≥ 90% | Capacity bar turns red (`#E05555`), pulses at 1Hz. Label updates to match. |
| **Warning** | Utilization 75–89% | Capacity bar turns amber (`#D4A85C`). No pulsing. |
| **Tab: Inventory** | Player selects Inventory tab | Default state — item grid shown in Zone 3. |
| **Tab: Crafting / Buildings / NPCs** | Player selects an unimplemented tab | Zone 3 shows centered placeholder: `"[Tab name] — coming soon"`. Capacity bar remains visible (unchanged). |
| **Loading** | Modal first opens | 100ms fade-in on the modal container. Content is rendered immediately — no spinner. |

---

## Interaction Map

Input methods: Keyboard/Mouse (primary), Gamepad (partial — navigation + core actions).

| Player Action | Mouse Input | Keyboard Input | Gamepad Input | Visual Feedback | Outcome |
|---|---|---|---|---|---|
| Open inventory | — | `I` (toggle) | Inventory button | Modal fades in | Screen appears, tick system pauses |
| Close inventory | Click backdrop or `×` button | `I` or `Escape` | Back / B button | Modal fades out | Returns to gameplay, tick system resumes |
| Switch tab | Click tab button | `Tab` cycles tabs | D-pad left/right | Active tab highlight updates | Zone 3 content switches |
| Scroll item grid | Mouse wheel / trackpad scroll | Arrow keys (when grid focused) | D-pad up/down | Grid scrolls vertically | More item blocks visible |
| Hover item block | Cursor over block | — | — | Block border: `#4a4a4a` → `#A8A49C` | Visual acknowledgement only (no tooltip) |

## Events Fired

| Player Action | Event | Payload | Consuming Systems |
|---|---|---|---|
| Open inventory | `inventory_opened()` | none | Tick System (pause), HUD (hide storage panel per Context 5) |
| Close inventory | `inventory_closed()` | none | Tick System (resume), HUD (restore storage panel) |
| Tab switch | — (UI-local state only) | — | None |
| Scroll | — (UI-local state only) | — | None |

**Note — no inventory modification events:** This screen is read-only. No item interaction events are fired. Item count changes visible in the grid are driven by `resource_count_changed` signals from the Inventory System (live data binding), not player actions.

## Transitions & Animations

| Transition | Duration | Easing | Notes |
|---|---|---|---|
| Screen enter (open) | 100ms | ease-in | Modal container + backdrop fade in simultaneously |
| Screen exit (close) | 80ms | ease-out | Modal container + backdrop fade out simultaneously |
| Tab content switch | 80ms | ease-out | Zone 3 content cross-fades |
| Tab button highlight | Instant | — | Active tab style applies immediately on click/press |
| Capacity bar color change | Instant | — | Reflects live data — no animated transition |
| Scroll | Smooth (system default) | — | Native ScrollContainer smoothing in Godot |

**Motion sensitivity:** All modal animations (100ms fade-in, 80ms fade-out, 80ms tab cross-fade) must be disabled when the reduced-motion accessibility setting is active. When disabled, all transitions are instant.

---

## Data Requirements

This screen is read-only. It binds to signals from the Inventory System and re-renders on change. It never writes data.

| Data | Source System | Read / Write | Update Trigger | Notes |
|------|--------------|--------------|----------------|-------|
| Resource type list (all `resource_id`s in storage) | Inventory System | Read | `resource_count_changed(resource_id, quantity)` | Aggregate across all containers: `resource_id → sum(slot.quantity)` |
| Total quantity per resource type | Inventory System | Read | `resource_count_changed(resource_id, quantity)` | Derived: sum all slots with matching `resource_id` across all `InventoryContainer` instances |
| Capacity (occupied slots / total slots) | Inventory System | Read | `storage_capacity_changed(used, total)` | Sum of all containers' `occupied_slots` over sum of all `capacity` values |
| Utilization ratio (%) | Inventory System | Read | Derived from capacity signal | Formula 6 (`(occupied / total) × 100`). Used for capacity bar color and label. |

**Architectural note:** The Inventory System's existing `get_capacity(container_id)` API is per-container. For the combined global view, the HUD/UI must call this for all containers and sum the results. This is a UI-layer aggregation responsibility — the Inventory System does not provide a global capacity API. This should be noted for the implementation story.

---

## Accessibility

**Accessibility tier:** Standard (from `design/ux/accessibility-requirements.md`).

| Requirement | Implementation |
|---|---|
| Keyboard navigation — open/close | `I` toggles modal. `Escape` closes from any state within the modal. |
| Keyboard navigation — tab bar | `Tab` key cycles through tab buttons (Inventory → Crafting → Buildings → NPCs → loops). `Enter` or `Space` activates focused tab. |
| Keyboard navigation — close button | `Tab` reaches `×` button. `Enter` activates. |
| Keyboard navigation — item grid | Arrow keys scroll grid when grid container is focused. |
| Focus indicator | Focused element: `#F0EDE6` fill, `#3A3A3A` text (matches HUD pattern). |
| Color-independent state communication | Capacity bar uses both fill color AND text label (`30% — 45/150 slots`). State is never communicated by color alone. |
| Minimum font size | 14px (Silkscreen). All text in spec meets this minimum. |
| Reduced motion | All modal and tab animations disabled when reduced-motion is active. All transitions become instant. |
| Gamepad navigation | D-pad left/right cycles tabs. B/back closes modal. D-pad up/down scrolls grid. |
| Screen reader | Tab buttons have descriptive labels ("Inventory tab", "Crafting tab"). Modal backdrop has aria-label: "Inventory — press Escape to close" (Godot AccessKit equivalent, if available in Godot 4.6). |

---

## Localization Considerations

| Text Element | EN Length | Expanded (DE/FR ~40%) | Layout Risk |
|---|---|---|---|
| Tab labels (Inventory, Crafting, Buildings, NPCs) | 4–9 chars | 6–13 chars | Low — short, tab bar has flex space |
| Capacity label `Storage: X / Y slots` | 20–25 chars | 28–35 chars | Low — reserve 140px min for label area |
| Empty state `"No items in storage yet"` | 23 chars | 32 chars | None — centered text, wraps naturally |
| Unimplemented tab placeholder `"[Tab] — coming soon"` | ~20 chars | ~28 chars | None — centered, single line |
| Quantity format `×N` | 2–5 chars | No translation | None — numeric, locale-neutral |
| Close button `×` | 1 char | No translation | None |

**Flagged for localization engineer:**
- Capacity label (`Storage:`) is the only layout-critical translated string. It must not overflow the 36px capacity bar height. If German "Lager:" expands unexpectedly, fall back to icon-only label (barrel icon replacing text prefix).
- Quantity format `×N` uses a multiplication symbol — ensure font includes the `×` glyph (Silkscreen does).
- Tab labels must not truncate. If any translation exceeds the tab button width, abbreviate (e.g., "Bldgs" for Buildings). Do not wrap tab label text.

---

## Acceptance Criteria

- [ ] **Open/close — tick pause:** Pressing `I` to open the inventory pauses the tick system within one frame; closing via `I`, `Escape`, or clicking backdrop resumes it within one frame.
- [ ] **Aggregated item grid:** The item grid displays one block per unique resource type with the correct aggregated total quantity across all Storage Areas (e.g., 8 Wood in Container A + 4 Wood in Container B → one Wood block showing `×12`).
- [ ] **Empty state:** When no items exist in any container, Zone 3 shows `"No items in storage yet"` with no item blocks.
- [ ] **Capacity bar accuracy:** The capacity bar label `Storage: X / Y slots` reflects the correct sum across all containers and updates in real-time on deposit or withdrawal.
- [ ] **Capacity bar color:** Bar is green at < 75%, amber at 75–89%, red + pulsing (1Hz) at ≥ 90%.
- [ ] **Responsive item grid:** Item blocks wrap based on available width. Reducing modal width causes blocks to reflow to fewer columns without overflow or clipping.
- [ ] **Scroll:** Vertical scroll activates when item blocks exceed visible grid height. Mouse wheel and keyboard arrow keys both scroll correctly.
- [ ] **Tab keyboard navigation:** `Tab` key cycles focus through all tab buttons in order (Inventory → Crafting → Buildings → NPCs → loops). `Enter` or `Space` activates the focused tab.
- [ ] **Unimplemented tabs:** Clicking or focusing Crafting, Buildings, or NPCs tabs shows the placeholder text `"[Tab name] — coming soon"` in Zone 3.
- [ ] **Animation timing:** Modal enter animation completes within 150ms; exit within 100ms. With reduced-motion enabled, all transitions are instant (zero animation frames).
- [ ] **Minimum font size:** No text element in the screen renders below 14px.
- [ ] **Color-independent capacity state:** At each utilization tier (normal / warning / critical), both the bar color AND the text percentage label convey the state (not color alone).
- [ ] **HUD storage panel:** Opening inventory hides the HUD storage panel (per `design/ux/hud.md` Context 5). Closing inventory restores it.

---

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ1 | Should clicking a specific Storage Area on the map open a per-container view (showing individual slots) rather than the global combined view? | Determines whether a separate per-container spec is needed. The combined view answers "what do I have globally?" but not "what's in this specific storage?" | Deferred — design after combined view is implemented |
| OQ2 | Should the item grid have a sort order? (e.g., by quantity descending, by resource category, by last-deposited) | Affects scannability for players with many resource types | Deferred to implementation — default to resource_id alphabetical until playtesting shows a need |
| OQ3 | Should item blocks show a secondary indicator for "low stock" (e.g., red tint when quantity < threshold)? | Would surface actionable information without opening the tooltip. Aligns with Pillar 2 (Information Transparency) | Deferred — depends on Resource System projection data availability at display time |
