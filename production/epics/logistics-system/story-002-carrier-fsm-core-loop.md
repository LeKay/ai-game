# Story 002: Carrier FSM Core Loop

> **Epic**: Logistics System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-002`, `TR-logistics-004`, `TR-logistics-007`, `TR-logistics-011`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture
**ADR Decision Summary**: Self-contained carrier FSM (8 states) replaces NPC task cycle for carrier-assigned NPCs. Tick-driven deterministic loop (step 3 of processing order). NPC interface: `set_carrier_state()`, `get_npc_position()`, `is_available()`, `release_npc()`, `on_npc_at_location()`. Travel time = Manhattan distance × ticks_per_tile.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — carrier FSM is pure GDScript data. Uses `Engine.get_singleton()` for cross-system calls (stable since Godot 1.0). Verify `ticks_advanced()` signal timing for NPC travel timers at 60fps and 144fps.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Visual pool pattern — recycled scene templates, registry owns all state
- Required: Production carrier transport — output held in building buffer, carrier calls `collect_output()` and `try_deposit()`
- Required: Carrier travel time formula — `carrier_travel_ticks = floor(distance × ticks_per_tile)`
- Forbidden: Never use TileMap for rendering — always TileMapLayer

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] Carrier FSM implements all 8 states: IDLE, TRAVEL_TO_SOURCE, AT_SOURCE, WAITING_SOURCE, TRAVEL_TO_DESTINATION, AT_DESTINATION, WAITING_DESTINATION, RETURN_HOME with correct transitions
- [ ] Travel time = Manhattan distance × `ticks_per_tile` (Formula 1): TRAVEL_TO_SOURCE and TRAVEL_TO_DESTINATION each deduct `floor(distance × ticks_per_tile)` ticks per tick
- [ ] At AT_SOURCE: if buffer has output, carrier picks up `min(buffer_amount, carrier_capacity)` items, enters TRAVEL_TO_DESTINATION; if buffer empty, enters WAITING_SOURCE
- [ ] At AT_DESTINATION: if destination has free space, carrier unloads cargo, enters RETURN_HOME; if destination full, enters WAITING_DESTINATION
- [ ] RETURN_HOME deducts `floor(dist_dest_home × ticks_per_tile)` ticks; on arrival, carrier enters IDLE and calls `NPCSystem.release_npc()`
- [ ] When NPC is assigned to a route, the Logistics System's carrier FSM replaces the NPC System's task cycle (precedence rule from GDD Core Rules 5)
- [ ] NPC interface contract: LogisticsSystem calls `NPCSystem.set_carrier_state(npc_id, state)` on state transitions only, `NPCSystem.get_npc_position(npc_id)` for distance calc, `NPCSystem.is_available(npc_id)` during route creation, `NPCSystem.release_npc(npc_id)` on route end, `NPCSystem.on_npc_at_location(npc_id, building_id)` on arrival at source/destination
- [ ] The carrier FSM processes as step 3 in tick processing order: (1) HungerSystem, (2) BuildingRegistry, (3) LogisticsSystem, (4) InventorySystem, (5) DayTransition events
- [ ] Formula 1 round-trip: `carrier_round_trip_ticks = (dist_home_source + d + dist_dest_home) × ticks_per_tile + loading_ticks + unloading_ticks`
- [ ] Planning shortcut for home-at-source: `carrier_round_trip_ticks = floor(d × ticks_per_tile × 2) + loading_ticks + unloading_ticks`

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**Tick processing order** (from ADR-0011): The tick dispatcher calls `_advance_tick()` on each system in priority order. LogisticsSystem is step 3. This guarantees building production completes BEFORE carriers poll for output (carriers poll AT_SOURCE, which checks `BuildingRegistry.has_output_buffer()`).

**Carrier loop pseudocode** (from ADR-0011, implemented in `_process_carrier(route)`):

```
IDLE:
    // Waiting for route activation — no-op on each tick

TRAVEL_TO_SOURCE:
    route.remaining_ticks -= 1
    if <= 0:
        carrier_state = AT_SOURCE
        npc.on_npc_at_location(route.npc_id, route.source_building_id)

AT_SOURCE:
    if building.has_output_buffer(source_id):
        pickup = min(buffer_amount, carrier_capacity)
        building.collect_output(source_id)
        route.cargo = pickup
        route.cargo_resource = resource_type
        carrier_state = TRAVEL_TO_DESTINATION
        route.remaining_ticks = calc_travel_time(dest_pos)
    else:
        carrier_state = WAITING_SOURCE
        route.wait_ticks = 0

WAITING_SOURCE:
    route.wait_ticks += 1
    if >= 300: timeout (see Story 003)
    if building.has_output_buffer(source_id):
        pickup = min(buffer_amount, carrier_capacity)
        building.collect_output(source_id)
        route.cargo = pickup
        carrier_state = TRAVEL_TO_DESTINATION
        route.remaining_ticks = calc_travel_time(dest_pos)

TRAVEL_TO_DESTINATION:
    route.remaining_ticks -= 1
    if <= 0:
        carrier_state = AT_DESTINATION
        npc.on_npc_at_location(route.npc_id, route.destination_building_id)

AT_DESTINATION:
    if storage.has_free_slots(dest_container):
        inv.try_deposit(dest_container, cargo_resource, cargo)
        route.cargo = 0
        carrier_state = RETURN_HOME
        route.remaining_ticks = calc_travel_time(home_pos)
    else:
        carrier_state = WAITING_DESTINATION
        route.wait_ticks = 0

RETURN_HOME:
    route.remaining_ticks -= 1
    if <= 0:
        carrier_state = IDLE
        npc.release_npc(route.npc_id)
```

**Carrier ↔ NPC TaskState mapping** (from ADR-0011): When the carrier FSM replaces the NPC task cycle, `set_carrier_state()` overwrites the NPC System's internal TaskState. The mapping is documented in ADR-0011's state mapping table.

**Travel time calculation**:
```
calc_travel_time(from_pos, to_pos) -> int:
    distance = GridMap.distance_between(from_pos, to_pos, DistanceMetric.MANHATTAN)
    return floor(distance * TICKS_PER_TILE)
```

**NPC interface via singleton** (from ADR-0011):
```
Engine.get_singleton("NPCSystem").set_carrier_state(npc_id, state)
Engine.get_singleton("NPCSystem").get_npc_position(npc_id)
Engine.get_singleton("NPCSystem").is_available(npc_id)
Engine.get_singleton("NPCSystem").release_npc(npc_id)
Engine.get_singleton("NPCSystem").on_npc_at_location(npc_id, building_id)
```

**Key contract from ADR-0011**: The Logistics System does NOT call `set_carrier_state()` every tick. It only calls it on state *transitions*. The NPC System's internal simulation loop transitions the carrier between logistics states.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 003]: Waiting timeout logic (WAITING_SOURCE/WAITING_DESTINATION timeout behavior)
- [Story 004]: Building status transitions (BLOCKED/STALLED/OPERATING)
- [Story 007]: Efficiency and carrier count formulas (Formulas 3 and 4)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**State machine transitions:**

- **AC-1**: Complete carrier loop from IDLE to IDLE (no waits)
  - Given: Route exists with source at (3,7), destination at (8,2), home at (3,7), ticks_per_tile = 3.0, carrier_capacity = 1, buffer has 3 items, destination has free space
  - When: Carrier starts trip (IDLE → TRAVEL_TO_SOURCE: 10 tiles × 3 = 30 ticks)
  - Then: At 30 ticks, state = AT_SOURCE, picks up 1 item, state = TRAVEL_TO_DESTINATION: 10 tiles × 3 = 30 ticks
  - Then: At 60 ticks total, state = AT_DESTINATION, unloads 1 item, state = RETURN_HOME: 13 tiles × 3 = 39 ticks
  - Then: At 99 ticks total, state = IDLE, NPC released
  - Edge cases: Verify travel_ticks uses floor() for non-integer distance × ticks_per_tile results; verify remaining_ticks decrements correctly even if carrier_capacity = 0 (should still travel but pickup = 0)

- **AC-2**: AT_SOURCE picks up min(buffer, capacity)
  - Given: Buffer has 1 item, carrier_capacity = 1
  - When: Carrier arrives AT_SOURCE
  - Then: pickup = 1, cargo = 1, cargo_resource set, state = TRAVEL_TO_DESTINATION
  - Edge cases: Buffer has 5 items, carrier_capacity = 1 → pickup = 1, 4 items remain in buffer; Buffer has 0 items → state = WAITING_SOURCE (not picked up)

- **AC-3**: AT_DESTINATION unloads if space, waits if full
  - Given: Destination storage has free slots
  - When: Carrier arrives AT_DESTINATION
  - Then: InvSystem.try_deposit() called, cargo = 0, state = RETURN_HOME
  - Edge cases: Storage full (occupied_slots == slot_count) → state = WAITING_DESTINATION, wait_ticks = 0

**NPC interface contract:**

- **AC-4**: set_carrier_state called only on transitions
  - Given: Carrier in IDLE state
  - When: tick advances, carrier stays IDLE
  - Then: set_carrier_state() called 0 times (no-op state)
  - When: Carrier transitions IDLE → TRAVEL_TO_SOURCE
  - Then: set_carrier_state() called exactly once with new state
  - Edge cases: Rapid state changes (e.g., AT_SOURCE → TRAVEL_TO_DESTINATION → AT_DESTINATION → WAITING_DESTINATION) must each call set_carrier_state() exactly once per transition

**Tick order enforcement:**

- **AC-5**: Carrier polls AFTER building production
  - Given: Building completes production cycle this tick, carrier is at AT_SOURCE waiting
  - When: tick processing runs (order: hunger, building, logistics, inventory, day)
  - Then: Building produces output (step 2), LogisticsSystem polls AT_SOURCE (step 3), carrier picks up the item on the SAME tick
  - Edge cases: If building produces and carrier polls before building (wrong order), carrier would go to WAITING_SOURCE — this is the bug AC-5 guards against

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/logistics/carrier_fsm_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (route model and slot validation must exist first)
- Unlocks: Story 003 (waiting timeout builds on AT_SOURCE/WAITING_SOURCE state), Story 004 (building status depends on carrier state), Story 005 (save/load needs carrier state)
