# Story 003: Drag-and-Drop Transport

> **Epic**: Player Character System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration — ADR-0007
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: `TR-player-003` (Drag-and-drop transport: carry item from tile to storage container)

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary (as specified)**: `TransportManager` class with `DragState {IDLE, DRAGGING, SNAP_BACK}`. Drag start on resource pin click → validate tile has resource pin. Drag update → compute Manhattan distance to nearest storage building, calculate cost preview (`energy = 2 × quantity + 1 × distance`, `ticks = 5 × distance`). Valid target = storage building tile (green highlight). On valid drop → call `InventorySystem.start_transport()` (creates IN_TRANSIT state per ADR-0005), action slot transitions to TRANSPORT state. On invalid drop → SNAP_BACK state, pin returns to source tile, no energy/tick cost.

**Engine**: Godot 4.6 | **Risk**: HIGH (verification required: drag input handling in Godot 4.6)

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/player-character-system.md`, scoped to this story:*

- [x] **AC3** GIVEN a resource pin on a tile WHEN the player drags it to a storage building AND the player has sufficient energy THEN the transport begins and deposits items into storage on completion
  > **Deviation**: Energy formula implemented as `maxi(1, distance)` instead of `2 × quantity + 1 × distance`. No quantity multiplier. Implemented via immediate `InventorySystem.try_deposit()` in `map_root.gd:_try_deposit_to_building()`, not `start_transport()` — no IN_TRANSIT state created. Tick cost = `distance × 5`.
- [x] **AC4** GIVEN a resource pin on a tile WHEN the player drags it to a non-storage tile AND releases THEN no items are deposited to storage
  > **Deviation**: Non-storage tile drops do NOT snap back — they succeed as tile-to-tile relocations (Story 007 behaviour). The distinction between "transport to storage" and "relocate on world" is merged into one drag flow. Only impassable/OOB/full tiles snap back.
- [x] **AC10** GIVEN a storage building is full WHEN the player attempts transport THEN the transport fails and pin returns to source tile
  > **Known issue**: In `map_root.gd:_try_deposit_to_building()` (line ~1160–1185), energy is consumed *before* the deposit result is checked. If storage is full, the pin snaps back visually but the energy cost is already deducted. Energy is not refunded.
- [ ] **AC15** GIVEN a transport drag where source tile equals the storage building tile (distance = 0) THEN transport energy cost = 2 × quantity and tick cost = 0
  > **Not met**: At distance 0, `maxi(1, 0) = 1` energy is charged and `1 × 5 = 5` ticks advance. The zero-distance edge case is not special-cased.

---

## Implementation — Actual

*This story was implemented as part of the unified resource relocation drag system. The ADR-specified `TransportManager` class and `start_transport()` flow were not used.*

**Files:**
- `src/systems/player_character.gd` — `RelocationDrag` inner class; `try_start_relocation()`, `get_relocation_preview()`, `try_commit_relocation()`, `cancel_relocation()`, `is_relocating()`
- `src/scenes/map_root.gd` — Drag input handling (`_unhandled_input`), `_try_deposit_to_building()`, `_update_drag_overlays()`

**Drag flow (actual):**

1. **LMB press on resource icon** (`map_root._unhandled_input`):
   - `_hit_test_resource_icon()` finds the icon under cursor
   - `_player.try_start_relocation(tile, resource_idx, resource_id)` → sets `RelocationDrag.state = DRAGGING`
   - `relocation_started` signal emitted

2. **Drag update** (`map_root._process` + `_update_drag_overlays`):
   - Icon follows cursor
   - `_player.get_relocation_preview(hovered_tile)` → returns `{energy_cost, tick_cost}`
   - Cost labels (⚡ and ⏱️) displayed above cursor
   - Path line + animated dots drawn from source to hovered tile
   - Color: valid (blue `#4A7EA8`) / invalid (red `#C45A4A`)

3. **LMB release** (`map_root._unhandled_input`):
   - If hovered tile has a building → `_try_deposit_to_building(target_tile, building_id)`:
     - Storage building (`assigned_container_id != &""`): `InventorySystem.try_deposit()` → removes from WorldGrid, frees icon node, advances ticks
     - Production building: `BuildingRegistry.receive_input_from_world()` → routes to input buffer
     - Snap back if: resource not in allowed inputs / no energy / deposit failed
     - **Bug**: energy spent before deposit result — not refunded on failure
   - If no building → `_player.try_commit_relocation(target_tile, grid)`:
     - SUCCESS: resource moved in WorldGrid, icon node position updated, ticks advanced
     - SNAP_BACK_*: icon animates back to source position

**Cost formulas (actual):**
- Energy: `maxi(1, manhattan_distance)` — minimum 1 regardless of distance
- Ticks (sufficient energy): `distance × 5`
- Ticks (depleted/food): `distance × 15`

**Signals emitted:**
- `relocation_started(source: Vector2i, resource_id: StringName)`
- `relocation_completed(source: Vector2i, target: Vector2i, resource_id: StringName)`
- `relocation_cancelled(source: Vector2i)`

---

## Deviations from Story Spec

| # | Specified | Actual | Impact |
|---|-----------|--------|--------|
| 1 | `TransportManager` class | `RelocationDrag` inner class in `PlayerCharacter` | Naming only — same concept |
| 2 | `start_transport()` → IN_TRANSIT state | `InventorySystem.try_deposit()` — immediate deposit | No async transit; inv-003 stub unused |
| 3 | Energy = `2 × qty + 1 × dist` | Energy = `maxi(1, dist)` | Quantity has no effect on energy cost |
| 4 | `transport_started/completed/cancelled` signals | `relocation_started/completed/cancelled` signals | Different names |
| 5 | Non-storage drop → snap back always | Non-storage drop → relocate on world tile | Story 007 and 003 merged into one drag |
| 6 | Distance 0 → energy = 2×qty, ticks = 0 | Distance 0 → energy = 1, ticks = 5 | AC15 not met |
| 7 | Energy refunded on full-storage snap-back | Energy consumed before deposit check | AC10 partially broken |

**Advisory**: Deviations 3, 5, 6 represent intentional design simplification. Deviation 7 is a latent bug — file as tech debt if AC10 correctness is required before vertical slice.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: EnergyPool class (already implemented)
- [Story 002]: Action dispatch (tile-click harvesting)
- [Story 004]: Depletion penalty and food refill (no interaction with transport logic)
- [Story 007]: Resource-relocation-drag — tile-to-tile movement (implemented alongside this story)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/resource_relocation_test.gd` — exists and covers relocation drag ACs

**Status**: [x] Test file exists — covers Story 007 ACs (relocation flow: AC2, AC4, AC5, AC6, AC7, AC8, AC9)
> **Gap**: No dedicated tests for building-deposit flow (`_try_deposit_to_building`). AC3 (building deposit), AC10 (full-storage refund bug), and AC15 (zero-distance edge case) are not covered by automated tests.

---

## Dependencies

- Depends on: Story 001 (EnergyPool), Story 002 (ActionSlot must have TRANSPORT state)
- Unlocks: None directly — but blocks visual/feel work (drag visuals, VFX)
