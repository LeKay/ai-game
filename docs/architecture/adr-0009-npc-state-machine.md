# ADR-0009: NPC State Machine and Movement

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
| **Post-Cutoff APIs Used** | None — all APIs used are stable since Godot 1.0 (`_process`, `Engine.get_singleton()`) |
| **Verification Required** | Verify Manhattan distance calculation consistency with GridMap; verify `ticks_advanced()` signal timing for NPC travel timers at 60fps and 144fps; verify Autoload initialization order when NPCSystem subscribes to TickSystem |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (tick system — `ticks_advanced()` signal for travel timer advancement), ADR-0004 (grid map — Manhattan distance calculation via `distance_between()`), ADR-0005 (inventory system — `try_deposit()`, `storage_changed`/`container_removed` signals), ADR-0008 (building system — `assign_npc()`, `release_npc()` APIs for NPC building assignments) |
| **Enables** | ADR-0010 (hunger system — NPC assignments increase food consumption; NPCSystem reports active assignments to HungerSystem), Building System GDD NPC-triggered production stories |
| **Blocks** | NPC assignment workflow stories, NPC travel/production cycle stories, NPC deposit/storage stories |
| **Ordering Note** | Must be Accepted before any NPC-related stories can begin. ADR-0010 (Hunger) reads NPC count from this system for food calculation. |

## Context

### Problem Statement

The NPC System governs the village workforce — recruited entities that the player assigns to production buildings to automate the manual-to-passive transition that defines the game's emotional core. Each NPC executes a deterministic task cycle driven by tick-based timers: travel to assigned building, work, travel to assigned storage, deposit output, return home. At Vertical Slice scope, NPCs have no visible sprites; their state is communicated entirely through building status indicators. The system must:

1. **Track NPC identities** — position (tile coords), home base (residential house), and assignment state.
2. **Manage task cycles** — a seven-state state machine (IDLE, TRAVEL_TO_BUILDING, WORK_AT_BUILDING, TRAVEL_TO_STORAGE, DEPOSIT, RETURN_TO_BASE, WAITING) with deterministic transitions. **Note:** With the introduction of the Transportation System, this state machine covers two NPC roles: (a) **Operator NPCs** — assigned to production buildings via the Building Detail panel; their active states are TRAVEL_TO_BUILDING, WORK_AT_BUILDING (repeating), and RETURN_TO_BASE on release. (b) **Carrier NPCs** — configured via the Transportation Management UI; their active states are the full cycle including TRAVEL_TO_STORAGE, DEPOSIT, and WAITING. Carrier NPC scheduling is owned by the Transportation System; this ADR governs the shared state machine mechanics. Full carrier specification is in `design/ux/transportation-management.md`.
3. **Advance travel timers** — tick-driven travel progress using Manhattan distance × ticks_per_tile (Formula 1).
4. **Coordinate with other systems** — Building System for assignments/release, Inventory/Storage System for deposits, GridMap for distance calculations.

### Constraints

- **Foundation Autoload pattern** — the NPC System uses an Autoload singleton (`NPCSystem`), consistent with ADR-0001 through ADR-0008.
- **Tick-driven movement** — all NPC timing (travel time, work duration) is tick-based via ADR-0001's `ticks_advanced()` signal. No `_process()` for timer advancement.
- **Manhattan distance** — movement uses Manhattan distance (consistent with GridMap system). Diagonal movement is not supported at VS scope. Travel time = Manhattan distance × `ticks_per_tile`.
- **No visible NPC sprites** — NPCs are abstract entities. All state communication is via building status indicators (green = producing, yellow = idle, red = blocked/stalled).
- **Centralized NPC registry** — `NPCSystem` owns all NPC state. No per-NPC scene nodes at VS scope.
- **No obstacle pathfinding at VS** — travel time is purely Manhattan distance. Obstacle detours are deferred to post-VS.

### Requirements

- Must manage 7 NPC states: IDLE, TRAVEL_TO_BUILDING, WORK_AT_BUILDING, TRAVEL_TO_STORAGE, DEPOSIT, RETURN_TO_BASE, WAITING.
- Must subscribe to TickSystem `ticks_advanced()` for travel timer advancement.
- Must delegate distance calculations to GridMap `distance_between()` (interface already in registry).
- Must delegate deposit operations to InventorySystem `try_deposit()` (interface already in registry).
- Must use BuildingSystem `assign_npc()` and `release_npc()` for assignment coordination (interfaces already in registry via ADR-0008).
- Must support NPC disconnection: building demolition releases NPC, storage demolition clears storage assignment, house demolition triggers player reassignment.
- Must track NPC position in tile coordinates.
- Must serialize NPC state for Save/Load (per ADR-0006).

## Decision

### Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                   NPCSystem (Autoload)                            │
│                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │  NPC Registry    │  │  Travel Manager  │  │  Task Cycle   │ │
│  │  - all_npcs:     │  │  - accumulated   │  │  Engine       │ │
│  │    Dictionary[   │  │    progress: int │  │  (state       │ │
│  │    StringName,   │  │    per NPC       │  │   transitions)│ │
│  │    NPCInstance]  │  └──────────────────┘  └───────────────┘ │
│  └──────────────────┘                                           │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │  TickSubscription│  │  SaveLoadHandler │  │  Assignment  │  │
│  │  (ticks_advanced)│  │  (serialize/     │  │  Coordinator │  │
│  │                  │  │   deserialize)   │  │  (building    │  │
│  │                  │  └──────────────────┘  │   integration)│  │
│  └──────────────────┘                        └──────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Core Design

**NPCSystem** is registered as a Godot Autoload (project settings → AutoLoad → `npc_system.gd` → Path: `res://src/gameplay/npc_system.gd`). This matches the Foundation Autoload pattern established in ADR-0001 through ADR-0008.

The Autoload receives dependency-injected references to the other Foundation systems:

```gdscript
func _enter_tree() -> void:
	var tick := Engine.get_singleton("TickSystem")
	var grid := Engine.get_singleton("GridMap")
	var inventory := Engine.get_singleton("InventorySystem")
	var building := Engine.get_singleton("BuildingRegistry")

# Null-check each reference — Autoload initialization order is not guaranteed.
# If a referenced Autoload is not yet loaded, get_singleton() returns null.
# _enter_tree() is the correct lifecycle hook (Autoloads are available by this point).
# If null is encountered, log a warning and defer operations until the dependency loads.
```

### NPCInstance

Per-NPC state container. One instance per NPC in the village. `NPCInstance` is a nested `class` (not `class_name`), appropriate for VS scope where NPCs have no editor-facing tools.

```
class NPCInstance:
    - npc_id: StringName
    - position: Vector2i  # current tile coordinates
    - home_base: Vector2i  # residential house tile (set at recruitment)
    - state: TaskState  # see TaskState enum below

    # Assignment data (set at assignment time)
    - assigned_building_id: StringName?
    - assigned_storage_id: StringName?

    # Travel progress (managed by Travel Manager)
    - travel_progress: int  # accumulated ticks during current travel segment
    - travel_destination: Vector2i?
    - travel_ticks_total: int  # pre-computed from Manhattan distance × ticks_per_tile

    # Task cycle data
    - work_cycle_complete: bool  # whether production cycle completed while at building

    enum TaskState {
        IDLE,
        TRAVEL_TO_BUILDING,
        WORK_AT_BUILDING,
        TRAVEL_TO_STORAGE,
        DEPOSIT,
        RETURN_TO_BASE,
        WAITING
    }

GDScript iteration order for all_npcs Dictionary follows insertion order (Godot 4.x standard), ensuring deterministic NPC processing.
```

### Task Cycle Engine

The state machine governs NPC behavior. Transitions are driven by tick accumulation (travel) and system signals (building/storage events).

```
# Travel Manager handles all travel-related timer advancement
# via the single ticks_advanced() subscription.

func _on_ticks_advanced(delta: int) -> void:
	for npc in all_npcs.values():
		match npc.state:
			TaskState.TRAVEL_TO_BUILDING:
				npc.travel_progress += delta
				if npc.travel_progress >= npc.travel_ticks_total:
					_npc_arrived_at_building(npc)

			TaskState.TRAVEL_TO_STORAGE:
				npc.travel_progress += delta
				if npc.travel_progress >= npc.travel_ticks_total:
					_npc_arrived_at_storage(npc)

			TaskState.RETURN_TO_BASE:
				npc.travel_progress += delta
				if npc.travel_progress >= npc.travel_ticks_total:
					_npc_returned_home(npc)

			TaskState.WAITING:
				# NPC is waiting for storage space — no timer advancement.
				# The deposit happens immediately when storage_changed signal fires.
				pass

			_:
				# IDLE, WORK_AT_BUILDING, DEPOSIT states do not advance timers.
				# They are driven by signal callbacks or building system events.
				pass
```

### State Transitions

| Transition | Condition | Triggered By |
|------------|-----------|--------------|
| IDLE → TRAVEL_TO_BUILDING | NPC assigned, travel ticks computed | NPCSystem.assign_npc() direct call |
| TRAVEL_TO_BUILDING → WORK_AT_BUILDING | Travel progress >= travel ticks total | Travel Manager (tick advancement) |
| WORK_AT_BUILDING → TRAVEL_TO_STORAGE | **Carrier NPCs only** — output ready for pickup, carrier calls `collect_output()` and begins transit to storage. **Operator NPCs** stay in WORK_AT_BUILDING and loop — they do not travel to storage. | TransportationSystem signal (carrier dispatch) |
| TRAVEL_TO_STORAGE → DEPOSIT | Travel progress >= travel ticks total | Travel Manager (tick advancement) |
| DEPOSIT → RETURN_TO_BASE | Deposit successful | InventorySystem signal `storage_changed` (space available, deposit succeeded) |
| DEPOSIT → WAITING | Storage full | InventorySystem.try_deposit() returns FAILED_FULL |
| WAITING → RETURN_TO_BASE | Storage space available — NPCSystem calls try_deposit(), succeeds, continues cycle | InventorySystem.storage_changed signal (space opened) triggers NPCSystem to attempt deposit |
| Any → IDLE | Building demolished | BuildingRegistry signal `building_demolished` (via release flow) |
| Any → IDLE | Storage demolished | InventorySystem signal `container_removed` |
| Any → IDLE | Home base demolished (player confirmed removal) | Player input flow (handled externally) |

### Assignment Flow

```
# BuildingSystem calls NPCSystem.assign_npc() when the player assigns an NPC.
# This is the primary entry point — not the other way around.

func assign_npc(npc_id: StringName, building_id: StringName, storage_id: StringName) -> AssignmentResult:
	var npc := all_npcs.get(npc_id)
	if npc == null or npc.state != TaskState.IDLE:
		return AssignmentResult.INVALID_NPC_STATE

	var building_tile := building.get_building_tile(building_id)
	var storage_tile := inventory.find_storage_tile(storage_id)  # via GridMap
	var travel_ticks := _compute_travel_ticks(npc.position, building_tile)

	npc.assigned_building_id = building_id
	npc.assigned_storage_id = storage_id
	npc.travel_destination = building_tile
	npc.travel_ticks_total = travel_ticks
	npc.travel_progress = 0
	npc.state = TaskState.TRAVEL_TO_BUILDING

	npc_assigned.emit(npc_id, building_id)
	return AssignmentResult.SUCCESS

# BuildingSystem calls NPCSystem.release_npc() when a building is demolished
# or the player releases an NPC.

func release_npc(npc_id: StringName) -> void:
	var npc := all_npcs.get(npc_id)
	if npc == null:
		return

	var home_tile := npc.home_base
	var return_ticks := _compute_travel_ticks(npc.position, home_tile)

	# Clear assignment
	npc.assigned_building_id = null
	npc.assigned_storage_id = null

	# If not at home, return home first
	if npc.position != home_tile:
		npc.travel_destination = home_tile
		npc.travel_ticks_total = return_ticks
		npc.travel_progress = 0
		npc.state = TaskState.RETURN_TO_BASE
	else:
		npc.state = TaskState.IDLE

	npc_released.emit(npc_id)
```

### NPC Disconnection (Rule 8)

When assigned buildings/structures are demolished, the NPC handles disconnection as follows:

```
# Building demolition — NPC abandons current task, returns home
func _on_building_demolished(building_id: StringName) -> void:
	for npc in all_npcs.values():
		if npc.assigned_building_id == building_id:
			release_npc(npc.npc_id)
			break

# Storage demolished — NPC returns home, storage assignment cleared
func _on_container_removed(container_id: StringName) -> void:
	for npc in all_npcs.values():
		if npc.assigned_storage_id == container_id:
			npc.assigned_storage_id = null
			release_npc(npc.npc_id)
			break
```

### Serialization

Per ADR-0006, each system serializes its own state to a plain Dictionary (not Array[Dictionary]):

```
func serialize() -> Dictionary:
	var data := {}
	for npc_id in all_npcs:
		var npc := all_npcs[npc_id]
		data[npc_id] = {
			"position": [npc.position.x, npc.position.y],
			"home_base": [npc.home_base.x, npc.home_base.y],
			"state": npc.state,
			"assigned_building_id": npc.assigned_building_id,
			"assigned_storage_id": npc.assigned_storage_id,
			"travel_progress": npc.travel_progress,
			"travel_ticks_total": npc.travel_ticks_total,
			"work_cycle_complete": npc.work_cycle_complete,
		}
	return data

func deserialize(saved_data: Dictionary) -> void:
	all_npcs.clear()
	for npc_id in saved_data:
		var d := saved_data[npc_id]
		var npc := NPCInstance.new()
		npc.npc_id = npc_id
		npc.position = Vector2i(d.get("position", [0, 0]))
		npc.home_base = Vector2i(d.get("home_base", [0, 0]))
		npc.state = d.get("state", TaskState.IDLE)
		npc.assigned_building_id = d.get("assigned_building_id")
		npc.assigned_storage_id = d.get("assigned_storage_id")
		npc.travel_progress = d.get("travel_progress", 0)
		npc.travel_ticks_total = d.get("travel_ticks_total", 0)
		npc.work_cycle_complete = d.get("work_cycle_complete", false)
		all_npcs[npc_id] = npc
```


### Key Interfaces

#### Public API (called by other systems)

```
# Assignment
assign_npc(npc_id: StringName, building_id: StringName, storage_id: StringName) -> AssignmentResult
release_npc(npc_id: StringName) -> void
recruit_npc(home_base: Vector2i) -> StringName  # returns generated npc_id

# Queries
get_npc_state(npc_id: StringName) -> TaskState
get_npc_position(npc_id: StringName) -> Vector2i
get_available_npcs() -> Array[StringName]  # all NPC IDs in IDLE state
get_npc_count() -> int
get_assigned_npc(building_id: StringName) -> StringName?
find_nearest_idle_npc(target_tile: Vector2i) -> StringName?
```

#### Signals emitted

```
# Assignment lifecycle
npc_assigned(npc_id: StringName, building_id: StringName)
npc_released(npc_id: StringName)
npc_recruited(npc_id: StringName, home_base: Vector2i)

# Task cycle events
npc_travel_started(npc_id: StringName, destination: Vector2i, ticks_total: int)
npc_travel_completed(npc_id: StringName, destination: Vector2i)
npc_production_ready(npc_id: StringName, building_id: StringName)
npc_deposit_completed(npc_id: StringName, storage_id: StringName)
npc_storage_full(npc_id: StringName, storage_id: StringName)
npc_returned_home(npc_id: StringName)
```

#### Signals subscribed to

```
# From TickSystem
ticks_advanced(delta: int)  # advance travel timers (single subscription)

# From BuildingRegistry
building_demolished(building_id: StringName)  # triggers NPC release
production_output_ready(building_id: StringName, output: Dictionary)  # NPC moves to deposit phase

# From InventorySystem
container_removed(container_id: StringName)  # triggers NPC storage assignment clear + return
storage_changed(container_id: StringName)  # may resolve WAITING NPCs
```

#### External interface usage (registry-cross-referenced)

| Interface | Direction | How Used |
|-----------|-----------|-----------|
| `GridMap.distance_between(a, b, metric)` | NPC → Grid | Manhattan distance for travel tick calculation |
| `InventorySystem.try_deposit(container_id, resource_id, quantity)` | NPC → Inventory | Deposit produced output at assigned storage |
| `BuildingRegistry.get_building_tile(building_id)` | NPC → Building | Get building tile for travel destination |
| `BuildingRegistry.assign_npc(building_id, npc_id)` | NPC → Building | Confirm assignment after BuildingRegistry accepts |

## Alternatives Considered

### Alternative A: Per-Scene NPC Nodes with Independent State Machines

**Description**: Each NPC is a scene node with its own state machine, `_process()` loop, and independent travel progress.

**Pros**:
- Each NPC is self-contained — no central registry iteration needed
- Natural Godot pattern (nodes manage their own state)
- Easier to add visible sprites later (each NPC node has a Sprite2D)

**Cons**:
- O(n) `_process()` calls every frame for n NPCs (performance risk at scale)
- Violates the GDD's implicit requirement: NPC timing is tick-based, not frame-based
- Harder to serialize (would need to iterate scene tree + collect state)
- Breaks the Foundation pattern: all game logic is data-driven, not scene-driven
- State synchronization between scene node and registry is error-prone

**Rejection Reason**: The GDD's tick-based timing model and the Foundation Autoload pattern (ADR-0001) both point to a centralized approach. Per-scene nodes would need their own time accumulator, violating the single-truth tick system.

### Alternative B: Building-Owned NPC Behavior

**Description**: Instead of a central NPCSystem, each production building owns the NPC assigned to it. The building's state machine governs the NPC's travel, work, and return cycle.

**Pros**:
- NPC behavior is co-located with the building it serves
- Demolition-triggered NPC release is trivial (building dies, NPC dies)
- No cross-system registration needed

**Cons**:
- BuildingRegistry already manages NPC assignment state (ADR-0008). Splitting NPC lifecycle between BuildingRegistry and per-building nodes creates authority ambiguity.
- Travel progress is shared across building/production/deposit — it's not purely building-owned.
- No central place to answer "which NPCs are idle?" (needed for UI assignment flow).
- Serialization complexity: BuildingRegistry + each building would need to track NPC state independently.
- NPC recruitment (Residential House spawn) would need to communicate with building nodes — more coupling.

**Rejection Reason**: The NPC lifecycle is fundamentally about the worker, not the workplace. The NPC travels, waits, deposits, and returns — none of which are building-specific. A central NPCSystem is the natural home.

### Alternative C: Event Queue (deferred travel, batch processing)

**Description**: Instead of ticking travel progress each frame, NPCs enter an event queue. A "travel complete" event is scheduled at the target tick count, and the NPC transitions only when the event fires.

**Pros**:
- Zero CPU cost for NPCs that are idle or waiting
- Event-driven is clean for discrete transitions

**Cons**:
- More complex: requires an event scheduler on top of the tick system
- Travel progress display (if added later) requires interpolation from event times
- At VS scope with max ~8 NPCs (4 houses × 2), the performance benefit is zero
- The `ticks_advanced()` signal already fires every ~100ms — iterating 8 NPCs is ~0.01ms, well under budget

**Rejection Reason**: Premature optimization. The single-loop iteration pattern used by the Building System (ADR-0008) is sufficient for NPC scale. An event queue adds complexity without meaningful benefit at VS scope.

## Consequences

### Positive

- **Centralized NPC authority** — NPCSystem owns all NPC state. No ambiguity about which system controls position, assignment, or travel progress.
- **Consistent with Foundation pattern** — Autoload singleton matches ADR-0001 through ADR-0008.
- **Tick-driven movement** — travel timers advance in lockstep with all other tick-based systems. No frame-rate dependency.
- **Clear state machine** — seven states with explicit transitions. Easy to debug and test.
- **Disconnection safety** — building/storage/house demolition signals are handled by centralized listeners, ensuring no NPC is orphaned.

### Negative

- **Autoload global state** — the NPCSystem is a global singleton, making isolated unit testing harder. Tests must mock or stub the Autoload.
- **Single-loop iteration is order-dependent** — deterministic iteration order is required for concurrent operations (multiple NPCs responding to the same building demolition).
- **No visual representation** — at VS scope, NPCs are invisible. All state is communicated via building status indicators. This is by design but means playtesting visibility is limited.

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Signal spam on `ticks_advanced()` | NPCSystem subscribes to ticks_advanced which fires every ~100ms. At 8 NPCs, that's 8 state checks per fire — ~80 checks/sec at 1x speed. | Each check is a single integer comparison + state match. ~0.01ms total for 8 NPCs. Well under budget. |
| Stale travel destination reference | If a building is demolished mid-travel, the NPC's `travel_destination` points to a non-existent tile. | Demolition signal triggers immediate `release_npc()` which recomputes the home destination. The current travel progress is discarded. |
| Storage assignment cleared mid-cycle | If storage is demolished while NPC is at the building working, the NPC finishes work, finds no storage, and must be redirected. | `_on_container_removed()` checks all NPCs. If an NPC's storage is demolished, `release_npc()` is called — the NPC abandons their current cycle and returns home. This matches GDD Rule 8. |
| Autoload dependency not ready | `Engine.get_singleton()` returns null if a dependency Autoload is not yet loaded. | `_enter_tree()` null-checks each dependency. If null, operations are deferred. VS scope starts with all Autoloads already loaded, so this is a development-time safety net. |
| Nested class not editor-friendly | `NPCInstance` as a nested `class` (not `class_name`) cannot be used as a typed inspector property. | Acceptable at VS scope. If NPC editor tools are needed later, migrate to `class_name NPCInstance` with a scene. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| npc-system.md | Rule 1: NPC Identity and Assignment | NPCInstance tracks npc_id, position, home_base, assignment state |
| npc-system.md | Rule 2: Recruitment | `recruit_npc()` method, NPC spawned with IDLE state at home base |
| npc-system.md | Rule 3: Task Assignment | `assign_npc(building_id, storage_id)` with travel computation |
| npc-system.md | Rule 4: Task Cycle (7 states) | TaskState enum with all 7 states, Travel Manager for timer advancement |
| npc-system.md | Rule 5: Movement and Pathfinding | Manhattan distance via GridMap.distance_between(), `ticks_per_tile` formula |
| npc-system.md | Rule 8: NPC Disconnection | `_on_building_demolished()`, `_on_container_removed()` listeners, `release_npc()` flow |
| npc-system.md | Formula 1: Travel Time | `_compute_travel_ticks()` = manhattan_distance × ticks_per_tile |
| npc-system.md | EC-1: No Production Buildings Available | NPC remains IDLE at home — no auto-assignment |
| npc-system.md | EC-3: Storage Full — NPC Waits | WAITING state with `storage_changed` signal resumption |
| npc-system.md | AC-5: Travel time proportional to Manhattan distance | Travel Manager computes and tracks travel_progress against travel_ticks_total |
| npc-system.md | AC-6: Full task cycle execution | State machine ensures travel → work → travel → deposit → return sequence |
| npc-system.md | AC-7: WAITING state on full storage | WAITING state + storage_changed signal triggers deposit |

## Performance Implications

- **CPU**: 0.05ms/frame for 8 NPCs (single loop over registry on `ticks_advanced()` event). Per-NPC work: ~2µs (state match + integer increment + comparison). At 144fps fast-forward, `ticks_advanced()` is driven by TickSystem, not frame rate. Idle NPCs in IDLE/WORK_AT_BUILDING/DEPOSIT/WAITING states: zero timer work (state match returns immediately).
- **Memory**: ~300 bytes per NPCInstance (StringName, 3 Vector2i, int, 2 StringName?, bool, enum). 8 NPCs = ~2.4KB. Negligible.
- **Load Time**: NPCSystem deserializes NPC data from WorldSaveManager (ADR-0006). 8 NPCs: < 1ms.
- **Network**: N/A — single-player game.

## Migration Plan

This ADR creates a new Foundation system. No migration from existing code is needed — the NPC System has not yet been implemented. Implementation should begin after ADR-0001 (Tick System), ADR-0004 (Grid Map), ADR-0005 (Inventory System), and ADR-0008 (Building Registry) are accepted, as the NPC System depends on all of them.

### Implementation Order

1. **NPCInstance** — standalone state container. Unit testable with mock GridMap.
2. **NPCSystem core** — NPC registry, `recruit_npc()`, `assign_npc()`, `release_npc()`. Depends on GridMap stub.
3. **Tick Subscription** — travel timer advancement. Depends on TickSystem.
4. **Assignment Coordinator** — building/storage integration. Depends on BuildingRegistry and InventorySystem stubs.
5. **Save/Load Integration** — depends on WorldSaveManager (ADR-0006).
6. **NPCSystem (full)** — ties everything together, signal subscriptions.

## Validation Criteria

| # | Criteria | Method |
|---|----------|--------|
| 1 | Recruiting an NPC creates an IDLE NPC at the house tile | Automated: recruit_npc((10,10)) → assert state = IDLE, position = (10,10) |
| 2 | Assigning an NPC to a building triggers TRAVEL_TO_BUILDING | Automated: assign_npc() → assert state = TRAVEL_TO_BUILDING, travel_ticks_total computed |
| 3 | Travel progress advances correctly with ticks | Automated: fire ticks_advanced(3) per tile × 5 tiles = 15 ticks → assert arrived at building |
| 4 | NPC transitions to WORK_AT_BUILDING after travel | Automated: advance travel ticks → assert state = WORK_AT_BUILDING |
| 5 | NPC transitions to TRAVEL_TO_STORAGE when production ready | Automated: emit production_output_ready → assert state = TRAVEL_TO_STORAGE |
| 6 | NPC enters WAITING when storage is full | Automated: deposit fails (full) → assert state = WAITING |
| 7 | NPC resumes from WAITING when space available | Automated: emit storage_changed → assert deposit succeeds → state = RETURN_TO_BASE |
| 8 | Building demolition releases NPC to IDLE (or RETURN_TO_BASE if away) | Automated: emit building_demolished → assert NPC returns home, state = IDLE |
| 9 | Storage demolition clears storage assignment and returns NPC | Automated: emit container_removed → assert assigned_storage_id = null, NPC returns home |
| 10 | Travel time = Manhattan distance × ticks_per_tile | Automated: distance 10, ticks_per_tile 3.0 → assert travel_ticks_total = 30 |

## Related Decisions

- ADR-0001: Tick System Design and Time Management (tick accumulation, signal subscription)
- ADR-0004: Grid Map Data Model and TileMapLayer Rendering (Manhattan distance, tile coordinates)
- ADR-0005: Inventory and Item State Machine (deposit_output, storage capacity queries)
- ADR-0006: Save and Load Format and Serialisation Order (NPC registry serialization)
- ADR-0008: Building Placement and Production System (NPC assignment/release APIs)
- GDD: design/gdd/npc-system.md (full mechanical specification, 237 lines)
- GDD: design/gdd/building-system.md (building status indicators, assignment slots)
