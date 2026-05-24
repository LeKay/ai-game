# Story 002: Production Cycles and Carrier Transport

> **Epic**: Building System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration — ADR-0008
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/building-system.md`
**Requirements**:
- `TR-build-004` (Production cycle tick advancement for Lumber Camp: input consume → cycle timer → output buffered for carrier)
- `TR-build-003` (Tick-based build time progression: CONSTRUCTING state with accumulated tick counter)

**ADR Governing Implementation**: ADR-0008: Building Placement and Production System Architecture
**ADR Decision Summary**: BuildingRegistry subscribes to TickSystem `ticks_advanced()` once and iterates all buildings in a single loop. CONSTRUCTING buildings accumulate ticks and transition to OPERATING at build_time threshold. OPERATING production buildings call `try_start_production_cycle()` which checks inputs from the building's input buffer (delivered by carrier) and NPC, deducts inputs, starts cycle timer. On cycle complete: output is placed in `buffered_output` and `production_output_ready` is emitted — the Transportation System's carrier NPC calls `collect_output()` to pick it up. Distance does NOT modify output quantity or cycle duration. Formula 3: `carrier_travel_ticks = floor(distance × ticks_per_tile)` governs carrier scheduling only. Formula 4: `production_output = base_output` (full output always). Formula 5: `production_cycle_duration = base_cycle_ticks` (no distance extension).

**Engine**: Godot 4.6 | **Risk**: LOW (stable APIs — `_process`, `Engine.get_singleton()`)
**Engine Notes**: No post-cutoff APIs. Single-loop iteration over `all_buildings` array. Integer arithmetic for tick accumulation.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/building-system.md`, scoped to this story:*

- [ ] **AC-06** GIVEN a building is in CONSTRUCTING state WHEN accumulated ticks reach the build_time threshold THEN the building transitions to OPERATING state, scaffolding disappears, and a construction completion notification appears
- [ ] **AC-09** GIVEN a production building is in OPERATING state with all inputs in its input buffer and NPC assigned WHEN the next tick cycle fires THEN the building deducts inputs from the input buffer, begins a production cycle, and its status shows "Producing"
- [ ] **AC-12** GIVEN a Lumber Camp is at Manhattan distance D from its assigned storage WHEN carrier travel time is computed THEN `carrier_travel_ticks = floor(D × ticks_per_tile)`. For example: distance 10, ticks_per_tile 3.0 → carrier_travel_ticks = 30. Production output is always 5 Wood (base_output) — distance does NOT reduce output.
- [ ] **AC-13** GIVEN a Lumber Camp completes a production cycle WHEN the cycle timer fires THEN the cycle always takes exactly `base_cycle_ticks` (100 ticks) regardless of distance. Output is placed in `buffered_output` and `production_output_ready` is emitted.
- [ ] **AC-14** GIVEN the game is paused WHEN building timers tick THEN no building's accumulated_ticks or production_cycle_ticks advances
- [ ] **AC-22** GIVEN a Residential House completes construction WHEN it enters OPERATING state THEN the first NPC spawns immediately and the npc_spawn_timer starts

---

## Implementation Notes

*Derived from ADR-0008 Implementation Guidelines:*

**Single-loop tick subscription (from ADR-0008):**
```
func on_ticks_advanced(delta):
    for building in all_buildings:
        if building.state == DEMOLISHED:
            continue
        if building.state == CONSTRUCTING:
            building.accumulated_ticks += delta
            if building.accumulated_ticks >= build_time_table[building.type]:
                building.state = OPERATING
                sync_visual_to_state(building)
                if building.type == RESIDENTIAL_HOUSE:
                    building.npc_spawn_timer = 0
                    emit_signal("building_npc_spawn_requested", building.building_id, building.tile, 1)
                elif building.type in [LUMBER_CAMP]:
                    emit_signal("building_construction_complete", building.building_id, building.type)
        elif building.state == OPERATING:
            if building.needs_production_cycle():
                result = building.try_start_production_cycle()
                if result == BLOCKED_NO_INPUT or result == BLOCKED_NO_NPC or result == BLOCKED_NO_CARRIER:
                    building.state = BLOCKED
                    sync_visual_to_state(building)
                elif result == SUCCESS:
                    pass  # production cycle running
        elif building.is_production_complete():
            # Output held in buffer — carrier picks up via collect_output()
            building.buffered_output = production_output  # always base_output, no distance modifier
            emit_signal("production_output_ready", building.building_id, building.buffered_output)
            if building.output_carrier_id == null or building.output_buffer_full():
                building.state = STALLED
                sync_visual_to_state(building)
            else:
                building.accumulated_ticks = 0
                sync_visual_to_state(building)
```

**Transport formulas (from GDD):**
```
# Formula 3: Carrier Travel Time
func calculate_carrier_travel_ticks(distance: int, ticks_per_tile: float = 3.0) -> int:
    return floor(distance * ticks_per_tile)

# Formula 4: Production Output — always full base output, no distance modifier
func calculate_production_output(base_output: int) -> int:
    return base_output  # 5 Wood for Lumber Camp, always

# Formula 5: Production Cycle Duration — always base cycle ticks, no distance modifier
func calculate_cycle_duration(base_ticks: int) -> int:
    return base_ticks  # 100 ticks for Lumber Camp, always
```

**Production building data table (Vertical Slice):**
```
production_table = {
    LUMBER_CAMP: {
        inputs: [
            {resource_id: "wood", quantity: 1},
            {resource_id: "tool", charge_cost: 5.0},
        ],
        output: {wood: 5},   # always 5, no distance reduction
        base_cycle_ticks: 100,  # always 100, no distance extension
        npc_required: true,
    }
}
```

**Residential House NPC spawn (from GDD Formula 8):**
```
if building.type == RESIDENTIAL_HOUSE and building.state == OPERATING:
    building.npc_spawn_timer += delta
    if building.npc_spawn_timer >= 1000 and building.npc_count == 1:
        emit_signal("building_npc_spawn_requested", building_id, tile, 1)
        building.npc_spawn_timer = 0
    elif building.npc_spawn_timer >= 1000 and building.npc_count == 2:
        building.npc_spawn_timer = 0  # hard cap — no third NPC
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Placement and construction start
- Story 003: Failed states — BLOCKED and STALLED transitions
- Story 004: NPC assignment workflow
- Story 005: Demolition
- Transportation System stories: carrier scheduling, collect_output(), deliver_input() — handled by Transportation System epic (separate)

---

## QA Test Cases

**AC-06**: Construction completion
  - Given: Lumber Camp in CONSTRUCTING state, build_time = 200, accumulated_ticks = 0
  - When: ticks_advanced(200) fires
  - Then: state = OPERATING, scaffolding removed, building_construction_complete signal emitted
  - Edge cases: accumulated_ticks = 199, ticks_advanced(1) → transitions; Storage Area (build_time = 0) → never enters CONSTRUCTING

**AC-09**: Production cycle starts
  - Given: Lumber Camp in OPERATING state, input buffer has tool (charge ≥ 5.0) and 1 wood (delivered by carrier), NPC assigned
  - When: next tick cycle fires, try_start_production_cycle() called
  - Then: inputs consumed from input buffer, production_cycle_ticks = 0, state remains OPERATING (producing)
  - Edge cases: tool charge = 4.0 (insufficient) → BLOCKED; no NPC → BLOCKED; input carrier not assigned → BLOCKED_NO_CARRIER

**AC-12**: Carrier travel time = distance × ticks_per_tile; output always full
  - Given: Lumber Camp at (3,7), assigned storage at (8,2). Manhattan distance = 10
  - Then: carrier_travel_ticks = floor(10 × 3.0) = 30. Carrier takes 30 ticks one-way.
  - Then: production_output = 5 Wood (full base_output — distance does NOT reduce output)
  - Edge cases: distance = 0 → carrier_travel_ticks = 0 (instant pickup); distance = 25 → carrier_travel_ticks = 75; output always = 5 regardless of distance

**AC-13**: Production cycle always base_cycle_ticks
  - Given: Lumber Camp at any distance from storage
  - When: production cycle starts
  - Then: cycle_duration = 100 ticks (base_cycle_ticks) regardless of distance
  - Then: on cycle complete → buffered_output = 5 Wood, production_output_ready emitted
  - Edge cases: distance = 0, 5, 10, 25 — all produce cycle_duration = 100

**AC-14**: Pause stops timers
  - Given: Lumber Camp CONSTRUCTING, accumulated_ticks = 87/200
  - When: TickSystem pauses
  - Then: ticks_advanced(0) or not called; accumulated_ticks stays at 87
  - When: resumed → 87 → 200 transitions to OPERATING

**AC-22**: Residential House NPC spawn
  - Given: Residential House completes construction at tick T
  - When: tick fires
  - Then: first NPC spawns, npc_spawn_timer starts
  - When: npc_spawn_timer reaches 1000 → second NPC spawns, timer resets; no third NPC ever

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/building_system/production_cycles_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (buildings must be placed and in CONSTRUCTING/OPERATING state first)
- Unlocks: Story 004 (NPC assignment requires buildings to be in OPERATING state)
