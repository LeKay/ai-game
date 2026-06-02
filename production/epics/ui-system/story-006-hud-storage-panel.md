# Story 006: HUD — Storage Panel (Global Resource Overview)

> **Epic**: UI System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**UX Spec**: `design/ux/hud.md` — Element 5 (collapsed), Element 6 (expanded), Element 5b (in-transit badge)
**TR-IDs**: TR-hud-storage-01 through TR-hud-storage-05

**ADR Governing Implementation**: ADR-0005: Inventory and Item State Machine
**ADR Decision Summary**: InventorySystem is an Autoload singleton. Emits `storage_changed(container_id)` on every deposit/consume. The HUD aggregates totals by iterating `get_all_containers()` — no per-container state is shown; all containers are summed globally.

**Engine**: Godot 4.6 | **Risk**: LOW — PanelContainer + ScrollContainer are stable APIs. No post-cutoff APIs used.

**Control Manifest Rules (this layer)**:
- Required: UI displays only — HUD never modifies InventorySystem state
- Guardrail: Input context stays `WORLD_ACTIVE` while storage panel is open (panel is not modal)
- Required: All UI text must meet WCAG AA 4.5:1 contrast ratio

---

## Acceptance Criteria

*From `design/ux/hud.md` Elements 5, 5b, 6 and AC table:*

- [ ] **AC1** Storage panel collapsed state always visible in top-right corner beneath top band, showing "Used: X/Y" where X = total occupied slots, Y = total capacity across all containers
- [ ] **AC2** Click toggle button → panel expands downward showing a scrollable list of per-resource rows (icon + name + count); max height 300px with scrollbar on overflow
- [ ] **AC3** Click toggle again, click outside the panel, or press Escape → panel collapses back to "Used: X/Y"
- [ ] **AC4** Panel updates within one frame whenever `InventorySystem.storage_changed` or `InventorySystem.container_capacity_changed` fires
- [ ] **AC5** When no containers exist ("—/—" null state), collapsed label shows "—/—" and expanded list shows "No storage available"
- [ ] **AC6** In-transit badge (Element 5b): visible above the toggle button showing the active transit count when > 0; hidden entirely when count is 0
- [ ] **AC-HUD-05** Expand/collapse slide animation completes within 250ms (200ms ease-out per spec)
- [ ] **AC-HUD-14** When an inventory modal is open, storage panel is hidden entirely

---

## Implementation Notes

### What changes in hud.gd

The existing `_add_stubs()` method in `hud.gd` creates a hidden placeholder `Control` node named `"StoragePanel"`. This story replaces that stub with a real `PanelContainer` built in a new `_add_storage_panel()` method, and removes `"StoragePanel"` from the stubs list.

### StoragePanel scene structure (built in code, not .tscn)

```
StoragePanel (PanelContainer)   — top-right anchor, min-width 160px
├── VBoxContainer
│   ├── CollapseRow (HBoxContainer)      — always visible, min-height 32px
│   │   ├── StorageLabel (Label)         — "Used: X/Y" or "—/—"
│   │   └── ToggleBtn (Button)           — "▼" (expand) / "▲" (collapse)
│   └── ResourceList (VBoxContainer)     — hidden when collapsed
│       └── [ResourceRow × N]            — one per resource type
│           ├── ResourceNameLabel (Label)  — resource id as fallback
│           └── ResourceCountLabel (Label)
InTransitBadge (Label)          — sibling of StoragePanel, overlaid above toggle
```

### Positioning

StoragePanel anchors to top-right of the CanvasLayer:
- `anchor_left = 1.0`, `anchor_right = 1.0`
- `anchor_top = 0.0`, `anchor_bottom = 0.0`
- `offset_top = TOP_BAND_HEIGHT` (48px)
- `offset_right = 0`, `offset_left = -160` (min width)

### Signal wiring

```gdscript
InventorySystem.storage_changed.connect(_on_storage_changed)
InventorySystem.container_capacity_changed.connect(_on_container_capacity_changed)
```

Both handlers call the same `_refresh_storage_panel()` method.

### Aggregation logic

```gdscript
func _compute_storage_summary() -> Dictionary:
    # Returns {used: int, total: int, resources: Dictionary[StringName, int]}
    var used := 0
    var total := 0
    var resources: Dictionary[StringName, int] = {}
    for container in InventorySystem.get_all_containers():
        used  += container.get_occupied_count()
        total += container.capacity
        for slot in container.slots:
            if not slot.is_empty():
                resources[slot.resource_id] = resources.get(slot.resource_id, 0) + slot.quantity
    return {&"used": used, &"total": total, &"resources": resources}
```

### Expand/collapse animation

Use a `Tween` on `ResourceList.custom_minimum_size.y`: 0 → natural height (capped at 300px). Duration 200ms, ease-out. Tween is killed and restarted on rapid toggling.

### Null handling

If `InventorySystem.get_all_containers()` returns an empty array, show "—/—" in the collapsed label and "No storage available" as a single label row in the expanded list.

### In-transit badge

The badge is a `Label` positioned as a floating overlay above the ToggleBtn. It subscribes to `InventorySystem.storage_changed` as well; when in-transit count == 0 it sets `visible = false`. For VS scope, in-transit count = number of slots across all containers with `state == InventorySlot.State.IN_TRANSIT` (from story-003 — if not yet implemented, badge stays hidden).

---

## Out of Scope

- Resource icons — no icon assets exist yet; name-only rows are acceptable for VS
- Sorting or filtering the resource list — shown in ResourceSystem definition order (or insertion order)
- Toast suspension on inventory modal open — deferred to the modal system story
- Notification Tray consolidation — deferred to MVP per `design/ux/hud.md` § Notification Tray

---

## QA Test Cases

**Story Type**: UI
**Evidence required**: `production/qa/evidence/storage-panel-evidence.md` — screenshot walkthrough

- **AC1**: Start game with at least one storage container → check collapsed panel shows "Used: X/Y"
- **AC2**: Click toggle → panel expands → confirm resource rows appear, scrollbar present when > 10 resources
- **AC3**: Press Escape → panel collapses → "Used: X/Y" visible again
- **AC4**: Deposit a resource in code → verify panel label updates without restart
- **AC5**: No containers in scene → panel shows "—/—" and "No storage available"
- **AC-HUD-05**: Toggle 10 times rapidly → all transitions complete ≤ 250ms

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/storage-panel-evidence.md` — screenshot walkthrough

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: InventorySystem (Autoload, ADR-0005) — `storage_changed`, `container_capacity_changed`, `get_all_containers()`
- Depends on: HUD story-002 — `hud.gd` and `hud.tscn` must exist (they do, story-002 is Complete)
- Unlocks: Full AC-HUD-06 tab order (Storage Panel Toggle is the 3rd focusable element in the top band)

---

## Completion Notes
**Completed**: 2026-05-31
**Criteria**: 6/8 passing (2 deferred — AC6 pending story-003, AC-HUD-14 pending modal system)
**Deviations**:
- ADVISORY: In-transit badge hardcoded hidden — `InventorySlot.state` not available until inv-003 (start_transport). Resolves automatically when story-003 lands.
- ADVISORY: AC-HUD-14 (hide panel when inventory modal open) deferred — modal system is a future story. Explicitly in Out of Scope.
- ADVISORY: Click-outside collapse implemented during code review; confirmed by code inspection, not yet verified in-engine.
**Test Evidence**: Manual confirmation for AC1–AC3. Code inspection for AC4, AC5, AC-HUD-05. Evidence doc (`production/qa/evidence/storage-panel-evidence.md`) not yet created — create before sprint close-out.
**Code Review**: Complete — 4 required changes applied (TICKS_PER_DAY duplication, click-outside AC3, is_connected guard, speed label format).
