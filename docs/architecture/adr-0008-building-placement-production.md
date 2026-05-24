# ADR-0008: Building Placement and Production System Architecture

## Status
Accepted

## Date
2026-05-13

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | HIGH — 4.4–4.6 beyond LLM training data |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — all APIs used are stable since Godot 1.0 (`_process`, `Tween`, `PackedScene`, `queue_free()`) |
| **Verification Required** | Verify PackedScene instantiation performance when 50+ buildings placed; verify Tween API compatibility for construction VFX in 4.6; test that `queue_free()` cleanup is deterministic |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (tick system — construction/production timer advancement), ADR-0004 (grid map — placement validation via GridMap interfaces already in registry), ADR-0005 (inventory system — resource consumption, deposit_output, storage capacity queries), ADR-0006 (save/load — building registry serialization), ADR-0007 (player character — placement energy cost deduction, initiate_build flow) |
| **Enables** | ADR-0009 (NPC state machine — building placement triggers NPC assignment, Residential House spawns NPCs), ADR-0010 (hunger system — building-spawned NPCs increase food requirement) |
| **Blocks** | NPC System (building placement is required before NPC assignment), Recipe Database execution, all building-specific gameplay stories |
| **Ordering Note** | Must be Accepted before any building-related stories can begin. ADR-0009 (NPC) depends on this for NPC assignment targets. |

## Context

### Problem Statement

The Building System is the player's primary interface with the game's spatial logic — where the village takes physical form on the 30×30 map. Every building is a deliberate, earned investment: resources hauled across the map by the player's own hands, energy spent, time counted in ticks. The system must manage:

1. **Placement validation** — checking grid bounds, impassable terrain, existing buildings, and resource tile clearability via GridMap (ADR-0004).
2. **Construction** — tick-based building process with per-building state machines (CONSTRUCTING → OPERATING).
3. **Operation** — production buildings run cycles (consume inputs, produce outputs), residential buildings spawn NPCs, storage buildings provide capacity.
4. **Failure states** — BLOCKED (missing input, no NPC, no carrier) and STALLED (output buffer full, no carrier collecting) with auto-recovery.
5. **Demolition** — irreversible removal with no refund, NPC release, and orphaned reference handling.
6. **Transport interface** — production output is held in a building-side buffer after cycle completion; a separate Transportation System (carrier NPCs) collects output and delivers inputs. The Building System emits `production_output_ready` and provides `collect_output()` / `deliver_input()` endpoints; it does NOT call `InventorySystem.deposit_output()` directly.

### Constraints

- **Foundation Autoload pattern** — the Building System uses an Autoload singleton (`BuildingRegistry`), consistent with ADR-0001, ADR-0002, ADR-0003, ADR-0005, ADR-0006, and ADR-0007.
- **GridMap is sole owner of BuildingLayer** — ADR-0004 established this. The Building System is the sole writer to BuildingLayer via `place_building()` and `remove_building()` interfaces already registered in the architecture registry.
- **Input context gating** — all player building input must pass through `InputContext` (ADR-0003). The Building System listens to `InputContext._unhandled_input()` for build mode tile clicks.
- **Tick-based timing** — construction and production timers advance via ADR-0001's `ticks_advanced()` signal. The Building Registry subscribes to this signal and iterates all buildings in a single loop (no per-scene `_process()` for tick logic).
- **PackedScene rendering** — each building is a `PackedScene` instantiated at the tile center position on the `MapRoot` node under a `Node2D` with `y_sort_enabled = true` for proper depth sorting. Building scene instances are pure visual targets — no independent game state lives in the scene. The Registry owns all state and syncs visuals on state transitions.
- **No TileMapLayer tiles** — buildings are NOT TileMapLayer tiles. They are PackedScene instances at tile centers.

### Requirements

- Must support 4 building types at Vertical Slice scope: Storage Area, Storage Building, Residential House, Lumber Camp.
- Must subscribe to Tick System `ticks_advanced()` for construction and production timer advancement.
- Must delegate placement validation to GridMap `validate_placement()` (interface already in registry).
- Must delegate resource operations to InventorySystem `try_consume()` and `deposit_output()` (interfaces already in registry).
- Must support building lifecycle: PLACE → CONSTRUCT → OPERATE → DEMOLISH.
- Must serialize building registry state for Save/Load (per ADR-0006).
- Must perform within 1.0ms/frame for 50 buildings (single loop iteration over registry).

## Decision

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                   BuildingRegistry (Autoload)                    │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │  BuildingRegistry│  │  VisualPool      │  │  BuildTime    │ │
│  │  - all_buildings:│  │  - recycled:     │  │  LookupTable  │ │
│  │    Array[BrldInst]│ │    [String,      │  │  (build_time  │ │
│  │  - build_counter:│ │       BrldInst]   │  │   per type)   │ │
│  │    int           │  │  (visual only,  │  └───────────────┘ │
│  │                  │  │   scene templates) │                      │
│  │  ┌────────────┐  │  └──────────────────┘  ┌───────────────┐ │
│  │  │ BrldInst 1 │  │                       │ Distance      │ │
│  │  │ BrldInst 2 │  │                       │ Calculator    │ │
│  │  │ ...        │  │                       │ (Formulas 3-5)│ │
│  │  └────────────┘  │                       └───────────────┘ │
│  └──────────────────┘                                       │
│                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │  TickSubscription│  │  SaveLoadHandler │  │  VFXSyncer │ │
│  │  (ticks_advanced)│  │  (serialize/     │  │  (scene    │ │
│  │                  │  │   deserialize)   │  │   state     │ │
│  │                  │  └──────────────────┘  │   sync)    │ │
│  └──────────────────┘                        └────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### Core Design

**BuildingRegistry** is registered as a Godot Autoload (project settings → AutoLoad → `building_registry.gd` → Path: `res://src/gameplay/building_registry.gd`). This matches the Foundation Autoload pattern established in ADR-0001 through ADR-0007.

The Autoload receives dependency-injected references to the other Foundation systems:

```gdscript
func _enter_tree() -> void:
	var tick := Engine.get_singleton("TickSystem")
	var inventory := Engine.get_singleton("InventorySystem")
	var grid := Engine.get_singleton("GridMap")
	var pc := Engine.get_singleton("PlayerCharacter")

# Null-check each reference — Autoload initialization order is not guaranteed.
# If a referenced Autoload is not yet loaded, get_singleton() returns null.
# _enter_tree() is the correct lifecycle hook (Autoloads are available by this point).
# If null is encountered, log a warning and defer operations until the dependency loads.
```

### BuildingRegistry

The central data structure. Owns all building state.

```
class BuildingRegistry:
    - all_buildings: Array[BuildingInstance]
    - build_counter: int  # unique id generator
    - build_time_table: Dictionary[BuildingType, int]  # static lookup

    Methods:
    - initiate_build(building_type: BuildingType, x: int, y: int) -> PlacementResult
    - iterate_tick_advanced(delta_ticks: int) -> void  # single loop, no per-scene _process
    - serialize() -> Dictionary  # keyed by building_id (matches ADR-0006 contract)
    - deserialize(Dictionary) -> void
    - get_building_count() -> int
    - get_all_building_ids() -> Array[String]

    initiate_build():
        # 1. Pre-check affordability via InventorySystem
        # 2. Query PC System for energy cost (Formula 7) and check/charge energy
        # 3. Call GridMap.place_building(x, y, building_id) — updates BuildingLayer
        # 4. Call InventorySystem.try_consume() — deducts build costs
        # 5. Create BuildingInstance in CONSTRUCTING state
        # 6. Instantiate PackedScene for visual rendering (under Node2D with y_sort_enabled)
        # 7. Connect tick subscription
        # 8. Add to all_buildings array sorted by building_id (ensures deterministic iteration)
```

### BuildingInstance

Per-building state machine. One instance per building on the map.

```
class BuildingInstance:
    enum State { CONSTRUCTING, OPERATING, BLOCKED, STALLED, DEMOLISHED }
    enum BuildingType { STORAGE_AREA, STORAGE_BUILDING, RESIDENTIAL_HOUSE, LUMBER_CAMP }

    - building_id: String
    - type: BuildingType
    - tile: Vector2i
    - state: State
    - accumulated_ticks: int  # construction or production progress
    - assigned_container_id: StringName?  # storage container reference
    - assigned_npc_id: StringName?  # NPC assignment (production buildings)
    - input_carrier_id: StringName?  # carrier assigned to deliver inputs (set by TransportSystem)
    - output_carrier_id: StringName?  # carrier assigned to collect outputs (set by TransportSystem)
    - buffered_output: Array[ResourcePin]?  # held output waiting for carrier pickup
    - input_buffer: Array[ResourcePin]?  # inputs delivered by carrier, consumed at cycle start
    - npc_spawn_timer: int  # Residential House only
    - production_cycle_ticks: int  # current cycle duration (always base_cycle_ticks — no distance modifier)

    Methods:
    - on_ticks_advanced(delta: int) -> void
    - try_start_production_cycle() -> ProductionStartResult
    - collect_output() -> Array[ResourcePin]  # called by carrier to collect buffered output
    - deliver_input(resource_id: StringName, quantity: int) -> bool  # called by carrier to stock input buffer
    - demolish() -> void
    - serialize() -> Dictionary
    - get_distance_to_storage() -> int  # via GridMap (used by TransportSystem for carrier scheduling)

    ProductionStartResult:
        - SUCCESS
        - BLOCKED_NO_INPUT
        - BLOCKED_NO_NPC
        - BLOCKED_NO_CARRIER
```

### Tick Subscription

The Registry subscribes to `TickSystem.ticks_advanced(delta)` once (not per-building). On each fire:

```
on_ticks_advanced(delta):
    for building in all_buildings:
        if building.state == DEMOLISHED:
            continue
        if building.state == CONSTRUCTING:
            building.accumulated_ticks += delta
            if building.accumulated_ticks >= build_time_table[building.type]:
                building.state = OPERATING
                sync_visual_to_state(building)
        elif building.state == OPERATING:
            if building.needs_production_cycle():
                result = building.try_start_production_cycle()
                if result == BLOCKED:
                    building.state = BLOCKED
                    sync_visual_to_state(building)
                elif result == SUCCESS:
                    # production cycle running...
                    pass
            if building.is_production_complete():
                # Output held in internal buffer — carrier will collect via collect_output()
                building.buffered_output = production_output
                emit_signal("production_output_ready", building.building_id, building.buffered_output)
                # Do NOT call InventorySystem.deposit_output() here.
                # If no carrier is assigned or buffer is already full → STALLED
                if building.output_carrier_id == null or building.output_buffer_full():
                    building.state = STALLED
                    sync_visual_to_state(building)
                else:
                    building.accumulated_ticks = 0
                    sync_visual_to_state(building)
```

### Residential House NPC Spawn

Residential House has a special `npc_spawn_timer` that increments during OPERATING state:

```
# In on_ticks_advanced loop:
if building.type == RESIDENTIAL_HOUSE and building.state == OPERATING:
    building.npc_spawn_timer += delta
    if building.npc_spawn_timer >= 1000 and building.npc_count == 1:
        # Defer NPC creation to ADR-0009 (NPC System).
        # Signal: on_npc_spawn_requested(building_id, tile, npc_count)
        # ADR-0009 must define and emit this signal.
        # BuildingRegistry does NOT directly reference NPCSystem.
        emit_signal("on_npc_spawn_requested", building_id, tile, 1)
        building.npc_spawn_timer = 0
    elif building.npc_spawn_timer >= 1000 and building.npc_count == 2:
        building.npc_spawn_timer = 0  # hard cap — emit no signal, no third NPC
```

### Distance Calculations

Building distance to assigned storage is computed using `GridMap.distance_between()` interface (already registered in architecture registry). Results are cached and only recalculated on storage assignment change or building move.

```
get_distance_to_storage():
    if assigned_container_id == null:
        return 0
    storage_tile = grid.find_nearest_storage(building.tile)
    return grid.distance_between(building.tile, storage_tile, DistanceMetric.MANHATTAN)
```

### Key Interfaces

#### Public API (called by other systems)

```
# Building lifecycle
initiate_build(building_type: BuildingType, x: int, y: int) -> PlacementResult
demolish_building(building_id: String) -> bool
assign_npc(building_id: String, npc_id: StringName) -> AssignmentResult
release_npc(building_id: String) -> void

# Transport interface (called by TransportationSystem carrier NPCs)
collect_output(building_id: String) -> Array  # carrier picks up buffered output
deliver_input(building_id: String, resource_id: StringName, quantity: int) -> bool  # carrier stocks input buffer

# Queries
get_building_state(building_id: String) -> BuildingInstance.State
get_building_count() -> int
get_all_building_ids() -> Array[String]
get_building_tile(building_id: String) -> Vector2i
is_building_at_tile(x: int, y: int) -> String?  # returns building_id or null
get_carrier_status(building_id: String) -> Dictionary  # {input_carrier_id, output_carrier_id}

# Save/Load integration
serialize() -> Dictionary  # keyed by building_id (matches ADR-0006 Dictionary contract)
deserialize(buildings_data: Dictionary) -> void
```

#### Signals emitted

```
# Building lifecycle
building_placed(building_id: String, type: BuildingType, tile: Vector2i)
building_construction_complete(building_id: String, type: BuildingType)
building_demolished(building_id: String)
building_state_changed(building_id: String, new_state: State, reason: String)

# Production
building_blocked(building_id: String, missing_input: String)
building_unblocked(building_id: String)
building_stalled(building_id: String, reason: String)  # reason: "no_output_carrier" or "buffer_full"
building_destalled(building_id: String)
production_output_ready(building_id: String, output: Dictionary)
	# Emitted when a production cycle completes and output is buffered for carrier pickup.
	# Consumed by TransportationSystem to trigger carrier NPC dispatch.
	# Note: NOT consumed directly by NPCSystem anymore — the operator NPC stays at the building.

# Residential
building_npc_spawned(building_id: String, npc_count: int)

# Orphaned reference
building_container_removed(building_id: String)

# Carrier assignment (received from TransportationSystem)
carrier_assigned(building_id: String, carrier_id: StringName, direction: String)   # direction: "input" | "output"
carrier_unassigned(building_id: String, carrier_id: StringName, direction: String)
```

#### Signals subscribed to

```
# From TickSystem
ticks_advanced(delta: int)  # advance all building timers (single subscription)

# From InventorySystem
storage_changed(container_id: StringName)  # may resolve STALLED buildings
on_container_removed(container_id: StringName)  # triggers BLOCKED for affected buildings
# Note: on_container_removed is a NEW signal on InventorySystem defined by this ADR.
# ADR-0005 must be updated to include this signal in its contract.
# InventorySystem emits this when a storage container is demolished/removed.

# From PlayerCharacterSystem
energy_changed(current: int, max: int)  # for placement energy cost preview
food_consumed(food_type: StringName, energy_restored: int)  # not used by building system

# From HungerSystem (if ADR-0010 is implemented)
# hunger_debuff_active — building reads this on production cycle start

# From PlayerCharacterSystem
energy_changed(current: int, max: int)  # for placement energy cost preview
food_consumed(food_type: StringName, energy_restored: int)  # not used by building system

# From HungerSystem (if ADR-0010 is implemented)
# hunger_debuff_active: bool — building reads this on production cycle start
# to apply 2× tick cost modifier (see hunger-system.md Formula 2).
# Polling at cycle start (not per-frame) keeps cost negligible.

# From InputContext (via _unhandled_input)
# Build mode tile clicks → initiate_build flow
# Building click/hover → query interface for HUD display
```

#### External interface usage (registry-cross-referenced)

| Interface | Direction | How Used |
|-----------|-----------|----------|
| `GridMap.validate_placement(tile, building_type)` | Building → Grid | Placement validation before CONSTRUCTING |
| `GridMap.place_building(tile, building_type)` | Building → Grid | Updates BuildingLayer on successful placement |
| `GridMap.remove_building(tile)` | Building → Grid | Removes from BuildingLayer on demolition |
| `GridMap.distance_between(a, b, metric)` | Building → Grid | Distance calculation for Formula 3 (carrier travel time); exposed to TransportationSystem |
| `InventorySystem.try_consume(container_id, resource_id, quantity)` | Building → Inventory | Deducts build costs at construction start |
| `InventorySystem.get_resource(container_id, resource_id)` | Building → Inventory | Build menu "have/need" preview |
| `PlayerCharacter.get_current_energy()` | Building → PC | Checks energy before placement |
| `PlayerCharacter.consume_energy(amount)` | Building → PC | Deducts placement energy cost |
| `TransportationSystem.get_carrier_status(building_id)` | Building → Transport | Query carrier assignment for UI display |

## Alternatives Considered

### Alternative A: Per-Scene `_process()` for Building Timers

**Description**: Each building scene node runs its own `_process()` to advance its construction/production timer independently.

**Pros**:
- Each building is self-contained — no central registry iteration needed
- Natural Godot pattern (nodes manage their own state)

**Cons**:
- O(n) `_process()` calls every frame for n buildings (performance risk at 50+ buildings)
- Violates the GDD's explicit requirement: "The Building Registry subscribes to `on_ticks_advanced` and iterates all buildings in a single loop (no per-scene `_process()` for tick logic)"
- Tied to frame rate — tick advancement would need delta-based conversion
- Harder to pause (would need to freeze each node individually)

**Rejection Reason**: The GDD explicitly requires a single-loop tick subscription pattern for performance. Per-scene `_process()` scales linearly with frame rate × building count, which is unacceptable at 60fps with 50+ buildings.

### Alternative B: ECS Architecture

**Description**: Use an Entity Component System (Godot's built-in ECS or a plugin like Archery) for building state management.

**Pros**:
- Cache-friendly memory layout for iterating buildings
- Natural fit for state machines

**Cons**:
- Godot 4.6 has no built-in ECS — requires a plugin (adds dependency)
- Overkill for 50 buildings at VS scope
- Steep learning curve for team members unfamiliar with ECS
- No performance benefit at VS scale (50 buildings × single loop iteration is ~0.01ms)

**Rejection Reason**: 50 buildings in a single array iteration takes microseconds, not milliseconds. ECS is premature optimization at VS scope. Revisit in Core Experience if building count exceeds 500.

## Consequences

### Positive

- **Centralized state** — BuildingRegistry owns all building state. Scene instances are pure visual targets. Easy to serialize, debug, and modify.
- **Single-loop tick iteration** — all timers advance in one `_process()`-free loop. No frame-rate dependency, clean pause handling.
- **Consistent with Foundation pattern** — Autoload singleton matches ADR-0001 through ADR-0008.
- **Clear state machine** — four building states (CONSTRUCTING, OPERATING, BLOCKED, STALLED) with deterministic transitions.
- **Transport decoupled from production** — The BuildingRegistry emits `production_output_ready` and exposes `collect_output()` / `deliver_input()` endpoints. The Transportation System owns carrier scheduling. Distance (Formula 3) informs carrier travel time but does NOT modify production output or cycle duration.

### Negative

- **Autoload global state** — the BuildingRegistry is a global singleton, making isolated unit testing harder. Tests must mock or stub the Autoload.
- **Scene-scene coupling for visuals** — the Registry must know about PackedScene instantiation and Node2D.y_sort_enabled to sync visuals. This is an engine-specific dependency.
- **No undo for demolition** — irreversible by design, but this limits player experimentation.
- **Single-loop iteration is order-dependent** — deterministic ordering (building_id ascending) is required for concurrent operations (EC-M2). Changing the iteration order would change behavior.

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| PackedScene instantiation at scale | If 50+ buildings placed over a session, repeated `instantiate()` + `add_child()` may cause memory pressure or scene tree depth issues. | Use object pooling for BuildingInstance data (scene instances are created once per building — only one instance per building exists). Reuse scene templates. |
| Tick iteration performance at high tick rates | If 144fps + fast-forward, `ticks_advanced()` fires frequently. Single-loop iteration over 50 buildings must be O(1) per building. | Loop only checks state flags and adds integer deltas. No allocations. ~0.01ms for 50 buildings. |
| Orphaned storage references | When a storage building is demolished, all dependent buildings must receive the signal. If the signal fails to fire, buildings silently hold invalid container references. | InventorySystem must emit `on_container_removed` on demolition. BuildingRegistry iterates `all_buildings` to find matches. Log a warning if a building is found without a valid container after the signal. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| building-system.md | Rule 1: Four-stage lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH) | BuildingInstance state machine with explicit State enum and transitions |
| building-system.md | Rule 2: Four building types (VS scope) + placement validation chain | initiate_build() delegates to GridMap.validate_placement() |
| building-system.md | Rule 4: Construction via tick accumulation | ticks_advanced() subscription, single-loop accumulator |
| building-system.md | Rule 5: Production cycle with NPC assignment | try_start_production_cycle() with NPC check, deposit_output() |
| building-system.md | Rule 7: BLOCKED and STALLED failure states | State enum includes BLOCKED and STALLED, auto-recovery on input availability |
| building-system.md | Rule 8: Demolition with no refund | demolish() removes from registry, calls grid.remove_building(), releases NPC |
| building-system.md | Rule 9: Multiple buildings of same type | VisualPool recycles scene instances, each BuildingInstance tracks state independently, each tracks state independently |
| building-system.md | Formula 1-8: Build cost, construction time, distance modifier, production output | DistanceCalculator class, build_time_table lookup, production formula implementation |
| building-system.md | EC-H1: Save/load construction progress | serialize()/deserialize() with accumulated_ticks field |
| building-system.md | EC-H2: Stalled output never discarded | stalled_output field persists until deposit succeeds or building demolished |
| building-system.md | EC-H5: Orphaned storage reference handling | on_container_removed signal subscription, BLOCKED state transition |
| building-system.md | Single-loop tick iteration requirement | ticks_advanced() subscribed once, iterates all_buildings in single loop |
| hunger-system.md | Formula 2: Building reads hunger debuff | Building reads hunger_debuff_active from HungerSystem to modify production cycle |

## Performance Implications

- **CPU**: 1.0ms/frame for 50 buildings (single loop over registry). Per-building work: ~20µs (state check, tick increment, formula evaluation if applicable). No per-scene `_process()` calls. At 144fps fast-forward, the loop still runs once per `ticks_advanced()` event (driven by TickSystem, not frame rate).
- **Memory**: ~256 bytes per BuildingInstance (id, state, vectors, enums). 50 buildings = ~12KB. PackedScene instances add ~50KB for sprites. Total: < 100KB at VS scope.
- **Load Time**: Minimal — registry deserializes building data from JSON (ADR-0006). Instantiation of PackedScene instances is one-time cost per building. 50 buildings: < 50ms.
- **Network**: N/A — single-player game.

## Migration Plan

This ADR creates a new Foundation system. No migration from existing code is needed — the Building System has not yet been implemented. Implementation should begin after ADR-0001 (Tick System), ADR-0004 (Grid Map), ADR-0005 (Inventory System), and ADR-0007 (Player Character) are accepted, as the Building System depends on all of them.

### Implementation Order

1. **BuildingInstance** — standalone state machine. Unit testable with mock GridMap and InventorySystem.
2. **BuildingRegistry (core)** — build_time_table, initiate_build(), demolish(). Depends on GridMap and InventorySystem stubs.
3. **Tick Subscription** — single-loop timer advancement. Depends on TickSystem.
4. **Distance Calculator** — depends on GridMap.distance_between().
5. **Save/Load Integration** — depends on WorldSaveManager (ADR-0006).
6. **VFXSyncer** — scene instantiation and visual state sync. Depends on PackedScene setup from GridMap architecture.
7. **BuildingRegistry (full)** — ties everything together.

## Validation Criteria

| # | Criteria | Method |
|---|----------|--------|
| 1 | Storage Area (0 cost, 0 ticks) enters OPERATING immediately on placement | Automated: initiate_build(STORAGE_AREA) → assert state = OPERATING |
| 2 | Lumber Camp (15W+3S, 200 ticks) enters CONSTRUCTING, transitions to OPERATING at 200 ticks | Automated: fire ticks_advanced(200) → assert state = OPERATING |
| 3 | Production blocked when inputs missing | Automated: set inputs = 0, fire ticks → assert state = BLOCKED |
| 4 | Production blocked resolves when inputs available | Automated: set BLOCKED, add inputs, fire ticks → assert state = OPERATING |
| 5 | Stalled when storage full, unstalls when space available | Automated: fill storage, complete production → assert STALLED; drain storage, fire ticks → assert OPERATING |
| 6 | Demolition removes building, no refund, NPC released | Automated: place building, assign NPC, demolish → assert building not in registry, NPC unassigned |
| 7 | Residential House spawns 1 NPC on construction complete | Automated: fire ticks to completion → assert npc_count = 1 |
| 8 | Residential House spawns 2nd NPC at 1000 ticks | Automated: advance 1000 ticks from OPERATING → assert npc_count = 2 |
| 9 | Carrier travel time follows distance formula | Automated: distance 10, ticks_per_tile 3.0 → assert carrier_travel_ticks = 30; production_output = 5 (full, no reduction) |
| 10 | Serialization preserves construction progress | Automated: place building, advance 100 ticks, serialize, deserialize → assert state = CONSTRUCTING, accumulated = 100 |

## Related Decisions

- ADR-0001: Tick System Design and Time Management (tick accumulation, signal subscription)
- ADR-0004: Grid Map Data Model and TileMapLayer Rendering (placement validation, building layer)
- ADR-0005: Inventory and Item State Machine (resource consumption, deposit)
- ADR-0006: Save and Load Format and Serialisation Order (building registry serialization)
- ADR-0007: Player Character Energy Model and Manual Action System (placement energy cost)
- GDD: design/gdd/building-system.md (full mechanical specification, 1183 lines)
- GDD: design/gdd/grid-map-system.md (placement validation, building layer)
- GDD: design/gdd/hunger-system.md (building reads hunger debuff for production modification)
