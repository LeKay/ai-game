# Story 003: Drag-and-Drop Transport

> **Epic**: Player Character System
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration — ADR-0007
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: `TR-player-003` (Drag-and-drop transport: carry item from tile to storage container)

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: `TransportManager` class with `DragState {IDLE, DRAGGING, SNAP_BACK}`. Drag start on resource pin click → validate tile has resource pin. Drag update → compute Manhattan distance to nearest storage building, calculate cost preview (`energy = 2 × quantity + 1 × distance`, `ticks = 5 × distance`). Valid target = storage building tile (green highlight). On valid drop → call `InventorySystem.start_transport()` (creates IN_TRANSIT state per ADR-0005), action slot transitions to TRANSPORT state. On invalid drop → SNAP_BACK state, pin returns to source tile, no energy/tick cost.

**Engine**: Godot 4.6 | **Risk**: HIGH (verification required: drag input handling in Godot 4.6)
**Engine Notes**: Drag-and-drop input handling in Godot 4.6 — verify `InputEventDrag` works as expected. The minimum drag threshold (5px cursor movement before entering DRAGGING state) prevents distinguishing short taps from drags. Use `Vector2i` for tile coordinates, `Vector2` for world-space cursor position.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/player-character-system.md`, scoped to this story:*

- [ ] **AC3** GIVEN a resource pin on a tile WHEN the player drags it to a storage building AND the player has sufficient energy THEN the transport begins, deducts `2 × quantity + 1 × distance` energy and `5 × distance` ticks, and deposits items into storage on completion
- [ ] **AC4** GIVEN a resource pin on a tile WHEN the player drags it to a non-storage tile AND releases THEN the pin returns to its original position with no energy or ticks consumed
- [ ] **AC10** GIVEN a storage building is full WHEN the player attempts transport THEN the transport fails, pin returns to source tile (NOT lost), and no energy/ticks are consumed
- [ ] **AC15** GIVEN a transport drag where source tile equals the storage building tile (distance = 0) THEN transport energy cost = 2 × quantity and tick cost = 0

---

## Implementation Notes

*Derived from ADR-0007 Implementation Guidelines:*

**TransportManager class structure:**
```
class TransportManager:
    enum DragState { IDLE, DRAGGING, SNAP_BACK }

    - state: DragState
    - source_tile: Vector2i?
    - target_building: BuildingSlot?
    - drag_position: Vector2
    - quantity: int
    - resource_id: StringName

    Methods:
    - on_drag_start(tile_pos: Vector2i) -> DragStartResult
    - on_drag_update(cursor_pos: Vector2) -> DragPreview
    - on_drag_end(cursor_pos: Vector2) -> TransportResult
    - cancel() -> void
```

**Drag flow:**
1. **Drag start** (`on_drag_start(tile_pos)`):
   - Validate tile has a resource pin (check `GridMap.get_resource_pin(tile_pos)`)
   - If no pin → return FAILURE
   - Store source_tile, read resource_id and quantity from pin
   - Transition to DRAGGING state
   - Emit `transport_started(source, target, quantity)` — target is null initially

2. **Drag update** (`on_drag_update(cursor_pos)`):
   - Find nearest storage building tile via GridMap query
   - Compute Manhattan distance
   - Calculate: `energy_cost = 2 × quantity + 1 × distance`, `tick_cost = 5 × distance`
   - Check energy: if energy > 0, `try_spend(energy_cost)` (not spend_unchecked — transport needs upfront energy)
   - Return DragPreview: `{distance, energy_cost, tick_cost, valid_target: is_storage_building}`
   - HUD shows: distance label ("7 tiles"), cost label ("18 energy · 15 ticks")
   - Storage building tile highlights green (valid), non-storage highlights red (invalid)

3. **Drag end** (`on_drag_end(cursor_pos)`):
   - If cursor over storage building: VALID drop
     - If energy sufficient: call `InventorySystem.start_transport(source, target, resource_id, quantity)` → creates IN_TRANSIT state per ADR-0005, deducts energy, transitions ActionSlot to TRANSPORT
     - If energy insufficient: return FAILURE, pin returns to source tile
     - If storage full: InventorySystem returns "full" → return FAILURE, pin returns to source tile (NOT lost)
   - If cursor NOT over storage building: INVALID drop → SNAP_BACK, pin animates back to source_tile
   - Energy and ticks only consumed on VALID drop

4. **Cancel** (`cancel()`):
   - Returns to IDLE state, pin returns to source tile

**Transport formulas (from GDD):**
- Energy: `2 × quantity + 1 × distance` (Manhattan distance)
- Ticks: `5 × distance`
- At 0 Energy: energy check is upfront — `try_spend()` returns false, transport is blocked

**Ownership handoff:** TransportManager handles drag-and-drop UI (cost preview, valid-target highlight, pin animation). Upon valid drop, TransportManager calls `InventorySystem.start_transport()` which creates the IN_TRANSIT state tracked by ADR-0005's transit_items registry. The tick countdown for transit is handled by InventorySystem. This keeps the transport lifecycle in a single system (InventorySystem) and prevents circular serialization.

**Signals to emit:**
- `transport_started(source: Vector2i, destination: Vector2i, quantity: int)`
- `transport_completed(source: Vector2i, destination: Vector2i)`
- `transport_cancelled(source: Vector2i)`

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: EnergyPool class (already implemented)
- [Story 002]: Action dispatch (tile-click harvesting)
- [Story 004]: Depletion penalty and food refill (no interaction with transport logic)

---

## QA Test Cases

**AC-3**: Drag to storage building completes transport
  - Given: Tile at (12,8) has resource pin (3 Stone), storage building at (5,3), energy=50, ActionSlot is FREE
  - When: on_drag_start((12,8)) → on_drag_update(cursor) → on_drag_end(storage_building_pos)
  - Then: Manhattan distance = |12-5| + |8-3| = 12, energy_cost = 2×3 + 12 = 18, tick_cost = 5×12 = 60, energy deducted from 50 to 32, InventorySystem.start_transport() called with (source=(12,8), target=(5,3), resource_id="stone", quantity=3), ActionSlot.state = TRANSPORT, transport_started signal emitted
  - Edge cases: 1 item, distance 0 → energy=2, ticks=0; 5 items, distance 20 → energy=30, ticks=100

**AC-4**: Drag to non-storage tile cancels transport
  - Given: Tile at (12,8) has resource pin (1 Wood), player drags to meadow tile (not a storage building)
  - When: on_drag_start((12,8)) → on_drag_update(cursor) → on_drag_end(meadow_pos)
  - Then: DragState = SNAP_BACK, pin returns to (12,8), no energy deducted, no ticks deducted, transport_cancelled signal emitted
  - Edge cases: drag started but cancelled mid-drag → same result; energy=100, drag cancelled → energy unchanged (100)

**AC-10**: Storage building full → transport fails, pin not lost
  - Given: Storage building at (5,3) is full (all slots occupied), tile at (12,8) has pin, player drags to storage
  - When: on_drag_end(storage_pos)
  - Then: InventorySystem returns "full" signal → TransportResult.FAILURE, pin returns to (12,8), no energy/ticks consumed, transport_cancelled signal emitted
  - Edge cases: partial storage (has space) → transport succeeds; storage at exactly 0 remaining slots → fails; storage slot count matches exact item count → fails (no room)

**AC-15**: Transport from storage tile (distance = 0)
  - Given: Resource pin on the storage building tile itself (12,8) IS the storage building location
  - When: on_drag_start((12,8)) → on_drag_update(cursor) → on_drag_end((12,8))
  - Then: distance = 0, energy_cost = 2 × quantity, tick_cost = 0, energy deducted, items deposited
  - Edge cases: 1 item → energy=2, ticks=0; 3 items → energy=6, ticks=0; tick_cost=0 is valid (immediate deposit)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/transport_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (EnergyPool), Story 002 (ActionSlot must have TRANSPORT state)
- Unlocks: None directly — but blocks visual/feel work (drag visuals, VFX)
