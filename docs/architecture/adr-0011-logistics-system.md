# ADR-0011: Logistics System — Carrier FSM and Route Architecture

## Status

Accepted — **Amended 2026-06-13** (see "Amendment 2026-06-13: Shared-Carrier Model"
at the end of this document; the amendment supersedes the 1-NPC-per-route rule, the
waiting timeouts, and the flat travel-time constants in the original text)

## Last Verified

2026-06-13

## Date

2026-05-19

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (gameplay systems) |
| **Knowledge Risk** | HIGH — versions 4.4–4.6 are beyond LLM training data |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None — this ADR defines gameplay system architecture, not engine API usage |
| **Verification Required** | Carrier FSM tick-ordering correctness (carrier poll must fire after building production tick) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (tick-system), ADR-0004 (grid-map), ADR-0005 (inventory-system), ADR-0008 (building-placement-production), ADR-0009 (npc-state-machine) |
| **Enables** | None |
| **Blocks** | Transportation Management UI stories (`design/ux/transportation.md`) |
| **Ordering Note** | ADR-0008 and ADR-0009 must be Accepted first — both define interfaces this ADR consumes (building slots, NPC management) |

## Context

### Problem Statement

The Logistics System is the village's supply chain — connecting buildings via NPC carriers that physically move resources across the map. The GDD (`design/gdd/logistics-system.md`) specifies the carrier FSM, route types, and NPC/Logistics state machine contract. However, no architectural decision has formalized how the carrier FSM is implemented, how routes are stored and managed, and how the system integrates with existing systems through the registered architecture registry. This ADR establishes the architecture for implementing the Logistics System.

### Constraints

- The Logistics System must not write state directly to any system it doesn't own (forbidden pattern: `direct_cross_system_state_write`).
- All timing must be tick-based and driven by `TickSystem.ticks_advanced()` — no `_process()` timers.
- The carrier FSM is owned entirely by the Logistics System. The NPC System's task cycle is suspended during carrier assignment.
- Routes are saved and loaded as part of game state (ADR-0006 applies).
- Travel time uses tile-weighted A* path cost instead of flat Manhattan distance — see ADR-0013 for pathfinding architecture.
- A building can have at most one carrier per slot type.

### Requirements

- Support three route types: Storage → Production, Production → Storage, Production → Production.
- Each route assigns exactly one NPC to a continuous carrier loop.
- Building status integration: BLOCKED (no input carrier), STALLED (no output carrier or destination full), OPERATING (normal).
- Travel time = Manhattan distance × `ticks_per_tile` (Formula 1).
- Route efficiency and carrier count formulas (Formulas 3 and 4).
- Carrier state machine with 8 states (IDLE, TRAVEL_TO_SOURCE, AT_SOURCE, WAITING_SOURCE, TRAVEL_TO_DESTINATION, AT_DESTINATION, WAITING_DESTINATION, RETURN_HOME).
- Route lifecycle states (DRAFT, ACTIVE, PAUSED, DEACTIVATED).
- Save/load persistence of routes and carrier states.
- Route visualization (always-visible lines with hover highlights).

## Decision

### Carrier FSM Architecture

The Logistics System owns a **self-contained carrier FSM** that replaces the NPC System's task cycle for carrier-assigned NPCs. This is the model specified in the GDD (logistics-system.md Core Rules 5 and NPC System Rule 7a).

```
┌─────────────────────────────────────────────────────┐
│                 Logistics System                     │
│                                                      │
│  ┌──────────┐    ┌──────────┐    ┌──────────────┐   │
│  │RouteStore │    │CarrierFSM│    │ RouteLines   │   │
│  │ (routes,  │    │ (per-route │    │ (Node2D in   │   │
│  │  lifecycle)│    │  state    │    │  world tree) │   │
│  │           │    │  machine) │    │              │   │
│  └─────┬─────┘    └─────┬─────┘    └──────────────┘   │
│        │                │                               │
│        │                ├──→ Engine.get_singleton("NPCSystem")  │
│        │                │    set_carrier_state()   │
│        │                │    get_npc_position()    │
│        │                │    is_available()        │
│        │                │    release_npc()         │
│        │                │    on_npc_at_location()  │
│        │                │                               │
│        │                ├──→ Engine.get_singleton("BuildingRegistry") │
│        │                │    has_output_buffer()       │
│        │                │    collect_output()          │
│        │                │                               │
│        │                ├──→ Engine.get_singleton("InventorySystem")  │
│        │                │    try_deposit()             │
│        │                │    try_consume()             │
│        │                │    get_occupied_slots()      │
│        │                │                               │
│        │                ├──→ Engine.get_singleton("GridMap")  │
│        │                │    distance_between(a, b,    │
│        │                │        DistanceMetric.MANHATTAN)│
│        │                │                               │
│        │                └──→ Engine.get_singleton("TickSystem") │
│        │                           ticks_advanced signal│
└────────┴────────────────┴──────────────────────────────┘
```

### Key Interfaces

#### Route Model (top-level `class_name`)

`LogisticsRoute` is a top-level `class_name` in its own file (`logistics_route.gd`) so that `Array[LogisticsRoute]` compiles with static typing.

```gdscript
# logistics_route.gd
class_name LogisticsRoute

var id: StringName
var source_building_id: StringName
var destination_building_id: StringName
var npc_id: StringName
var route_type: RouteType       # INPUT or OUTPUT
var active: bool                # true = executing, false = paused/deactivated
var lifecycle_state: int        # 0=DRAFT, 1=ACTIVE, 2=PAUSED, 3=DEACTIVATED
var carrier_state: int          # CarrierState enum values

# --- Factory (called by LogisticsSystem) ---
static func create(source: StringName, destination: StringName,
                   npc: StringName, route_type: RouteType) -> LogisticsRoute:
    var route = LogisticsRoute.new()
    route.id = StringName("route_" + npc)
    route.source_building_id = source
    route.destination_building_id = destination
    route.npc_id = npc
    route.route_type = route_type
    route.active = true
    route.lifecycle_state = 1  # ACTIVE
    route.carrier_state = 0   # IDLE
    route.cargo = 0
    route.cargo_resource = null
    route.remaining_ticks = 0
    route.wait_ticks = 0
    return route
```

#### NPC System Contract (defined by ADR-0009, called via `Engine.get_singleton`)

| Method (via singleton) | Purpose | Called When |
|------------------------|---------|-------------|
| `Engine.get_singleton("NPCSystem").set_carrier_state(npc_id, state)` | Transition carrier FSM | On carrier state transitions only (not per-tick) |
| `Engine.get_singleton("NPCSystem").get_npc_position(npc_id)` | Get carrier position | Route creation, travel time calculation |
| `Engine.get_singleton("NPCSystem").is_available(npc_id)` | Check if NPC can be assigned | Route creation validation |
| `Engine.get_singleton("NPCSystem").release_npc(npc_id)` | Release NPC on route deletion | Route deletion/deactivation |
| `Engine.get_singleton("NPCSystem").on_npc_at_location(npc_id, building_id)` | Notify arrival at source/dest | Carrier FSM AT_SOURCE or AT_DESTINATION transition |

#### Tick-Driven Carrier Loop (internal simulation)

**Tick Ordering Enforcement.** The entire simulation uses a single coordinated tick dispatcher (`TickSystem`) that calls system advance methods in a fixed order each tick. This avoids the non-determinism of Godot signal connection ordering. The `TickSystem._process()` accumulator fires `on_tick_complete()` (a direct method call, not a signal) which iterates through registered systems in priority order:

```
on_tick_complete():
    _system_order[i]._advance_tick(delta_ticks)
```

The registered order (defined in TickSystem, ADR-0001):
1. HungerSystem
2. BuildingRegistry (production, buffer management)
3. **LogisticsSystem** (carrier FSM poll)
4. InventorySystem (in-transit timer countdown)
5. DayTransition events

This guarantees that building production completes *before* carriers poll for output, and carriers poll *before* inventory advances transit timers.

On `on_tick_complete()`, the Logistics System's `_advance_tick()` processes all active carriers:

```gdscript
func _advance_tick(delta_ticks: int) -> void:
    for route in _active_routes:
        if not route.active:
            continue
        _process_carrier(route)
```

Carrier state transitions:

```
for each active carrier (route):
    switch route.carrier_state:
        IDLE:
            // Waiting for route activation
            pass

        TRAVEL_TO_SOURCE:
            route.remaining_ticks -= 1
            if route.remaining_ticks <= 0:
                route.carrier_state = AT_SOURCE
                Engine.get_singleton("NPCSystem").on_npc_at_location(
                    route.npc_id, route.source_building_id)

        AT_SOURCE:
            var br = Engine.get_singleton("BuildingRegistry")
            if br.has_output_buffer(route.source_building_id):
                pickup_quantity = min(
                    br.get_output_buffer(route.source_building_id),
                    carrier_capacity
                )
                br.collect_output(route.source_building_id)
                route.cargo = pickup_quantity
                route.carrier_state = TRAVEL_TO_DESTINATION
                route.remaining_ticks = calc_travel_time(route.destination_building_id)
            else:
                route.carrier_state = WAITING_SOURCE
                route.wait_ticks = 0

        WAITING_SOURCE:
            route.wait_ticks += 1
            if route.wait_ticks >= CARRIER_WAITING_TIMEOUT:
                route.carrier_state = RETURN_HOME
                route.remaining_ticks = calc_travel_time(home_position)
                deactivate_route(route, "timeout at source")
                return
            var br2 = Engine.get_singleton("BuildingRegistry")
            if br2.has_output_buffer(route.source_building_id):
                pickup_quantity = min(
                    br2.get_output_buffer(route.source_building_id),
                    carrier_capacity
                )
                br2.collect_output(route.source_building_id)
                route.cargo = pickup_quantity
                route.carrier_state = TRAVEL_TO_DESTINATION
                route.remaining_ticks = calc_travel_time(route.destination_building_id)

        TRAVEL_TO_DESTINATION:
            route.remaining_ticks -= 1
            if route.remaining_ticks <= 0:
                route.carrier_state = AT_DESTINATION
                Engine.get_singleton("NPCSystem").on_npc_at_location(
                    route.npc_id, route.destination_building_id)

        AT_DESTINATION:
            var inv = Engine.get_singleton("InventorySystem")
            if inv.get_occupied_slots(route.destination_container_id)
               < inv.get_slot_count(route.destination_container_id):
                var deposit_result = inv.try_deposit(
                    route.destination_container_id,
                    route.cargo_resource,
                    route.cargo)
                if deposit_result.success:
                    route.cargo = 0
                    route.carrier_state = RETURN_HOME
                    route.remaining_ticks = calc_travel_time(home_position)
            else:
                route.carrier_state = WAITING_DESTINATION
                route.wait_ticks = 0

        WAITING_DESTINATION:
            route.wait_ticks += 1
            if route.wait_ticks >= CARRIER_WAITING_TIMEOUT:
                route.carrier_state = RETURN_HOME
                route.remaining_ticks = calc_travel_time(home_position)
                deactivate_route(route, "timeout at destination")
                return
            var inv2 = Engine.get_singleton("InventorySystem")
            if inv2.get_occupied_slots(route.destination_container_id)
               < inv2.get_slot_count(route.destination_container_id):
                var deposit_result = inv2.try_deposit(
                    route.destination_container_id,
                    route.cargo_resource,
                    route.cargo)
                if deposit_result.success:
                    route.cargo = 0
                    route.carrier_state = RETURN_HOME
                    route.remaining_ticks = calc_travel_time(home_position)

        RETURN_HOME:
            route.remaining_ticks -= 1
            if route.remaining_ticks <= 0:
                route.carrier_state = IDLE
                Engine.get_singleton("NPCSystem").release_npc(route.npc_id)
                // Next trip begins: player must reactivate route
```

**Carrier ↔ NPC TaskState mapping.** When the carrier FSM replaces the NPC task cycle, `set_carrier_state()` overwrites the NPC System's internal TaskState:

| CarrierState | Overwrites NPC TaskState to |
|---|---|
| IDLE | IDLE |
| TRAVEL_TO_SOURCE | TRAVEL_TO_BUILDING (reused for travel) |
| AT_SOURCE | WORK_AT_BUILDING (reused for pickup) |
| WAITING_SOURCE | WAITING |
| TRAVEL_TO_DESTINATION | TRAVEL_TO_STORAGE (reused for travel) |
| AT_DESTINATION | DEPOSIT (reused for unload) |
| WAITING_DESTINATION | WAITING |
| RETURN_HOME | RETURN_TO_BASE |

### Travel Time Calculation

Travel time uses `GridMap.distance_between()` with `DistanceMetric.MANHATTAN` (ADR-0004):

```gdscript
func calc_travel_time(from: Vector2i, to: Vector2i) -> int:
    var gm = Engine.get_singleton("GridMap")
    var distance = gm.distance_between(from, to, GridMap.DistanceMetric.MANHATTAN)
    return floor(distance * TICKS_PER_TILE)
```

The full round-trip formula (Formula 1 from logistics-system.md GDD):

```
carrier_round_trip_ticks = (dist_home_source + d + dist_dest_home)
    × ticks_per_tile + loading_ticks + unloading_ticks
```

### Building Status Integration

The Logistics System drives building status through the BuildingRegistry API. Status writes execute during `_advance_tick()` (step 3 of tick ordering), after building production completes (step 2), preventing race conditions:

```gdscript
func _update_building_status(route: LogisticsRoute):
    var br = Engine.get_singleton("BuildingRegistry")
    match route.carrier_state:
        IDLE, TRAVEL_TO_SOURCE, TRAVEL_TO_DESTINATION, RETURN_HOME:
            // Carrier in transit — building stays at current status
            pass
        WAITING_DESTINATION:
            // Destination full — building is STALLED
            br.set_status(route.destination_building_id,
                BuildingRegistry.Status.STALLED)
        _:
            // Active transit — building OPERATING
            br.set_status(route.destination_building_id,
                BuildingRegistry.Status.OPERATING)

func _on_route_active_changed(route: LogisticsRoute):
    var br = Engine.get_singleton("BuildingRegistry")
    if not route.active:
        if route.route_type == RouteType.INPUT:
            br.set_status(route.destination_building_id,
                BuildingRegistry.Status.BLOCKED)
        elif route.route_type == RouteType.OUTPUT:
            br.set_status(route.source_building_id,
                BuildingRegistry.Status.STALLED)
    else:
        // Carrier active — building system evaluates production independently
        pass
```

### Save/Load Integration

Routes are serialized as part of the save/load pipeline (ADR-0006 applies). Uses `Dictionary.get(key, default)` for safe deserialization of older saves:

```gdscript
func serialize() -> Dictionary:
    var routes = []
    for route in _active_routes:
        routes.append({
            "id": route.id,
            "source_building_id": route.source_building_id,
            "destination_building_id": route.destination_building_id,
            "npc_id": route.npc_id,
            "route_type": route.route_type,
            "active": route.active,
            "lifecycle_state": route.lifecycle_state,
            "carrier_state": route.carrier_state,
            "cargo": route.cargo,
            "cargo_resource": route.cargo_resource,
            "remaining_ticks": route.remaining_ticks,
            "wait_ticks": route.wait_ticks,
        })
    return {"logistics_routes": routes}

func deserialize(data: Dictionary) -> void:
    var routes_data = data.get("logistics_routes", [])
    for route_data in routes_data:
        var route = LogisticsRoute.create(
            route_data.get("source_building_id"),
            route_data.get("destination_building_id"),
            route_data.get("npc_id"),
            route_data.get("route_type", RouteType.OUTPUT))
        route.id = route_data.get("id", "route_" + route.npc_id)
        route.active = route_data.get("active", true)
        route.lifecycle_state = route_data.get("lifecycle_state", 3)  # DEACTIVATED
        route.carrier_state = route_data.get("carrier_state", 0)     # IDLE
        route.cargo = route_data.get("cargo", 0)
        route.cargo_resource = route_data.get("cargo_resource")
        route.remaining_ticks = route_data.get("remaining_ticks", 0)
        route.wait_ticks = route_data.get("wait_ticks", 0)
        _active_routes.append(route)
```

### Route Visualization

Route lines are rendered via a `RouteLines` node (extends `Node2D`, placed in the world scene tree under the camera's parent, **not** a `CanvasLayer`). This ensures lines pan and zoom with the world camera. The `Line2D` API is used directly as a `Node2D` child of `RouteLines`:

- **Always-visible** lines at 30% opacity for active routes.
- Color encodes status: green = active, yellow = carrier in transit, red = destination full.
- Line thickness encodes carrier count.
- Hover highlights to 60% opacity and shows route detail tooltip (NPC name, distance, round-trip time, efficiency). Tooltips are rendered in a `CanvasLayer`-based HUD overlay.
- Inactive/deactivated routes show a dim gray line at 10% opacity.
- Line patterns (solid/dashed/dotted) provide colorblind accessibility (WCAG 2.1 AA).
- Dirty-flag updates: lines only redraw when state changes, not per-frame.

## Alternatives Considered

### Alternative A: NPC-Driven Logistics

The NPC System's state machine is extended with logistics-specific states (TRAVEL_TO_SOURCE, AT_SOURCE, etc.). The Logistics System only signals route goals and the NPC System executes the movement.

- **Pros**: Single FSM source of truth; simpler state management.
- **Cons**: Tight coupling — the NPC System would need to know about routes, building slots, and carrier states. Violates the separation of concerns established in ADR-0009. The NPC System is a general-purpose worker manager; logistics is a supply-chain concern.
- **Rejection Reason**: The NPC System ↔ Logistics System contract in the GDD explicitly states that the Logistics System's carrier FSM fully replaces the NPC task cycle. This alternative contradicts that design.

### Alternative B: Signal-Driven Decoupled FSM

The Logistics System drives carrier state via signals rather than direct method calls. Each carrier FSM emits `state_changed` signals that the NPC System and Building System subscribe to.

- **Pros**: Maximum decoupling; systems react to events without knowing about each other.
- **Cons**: Signal ordering is not deterministic in Godot — this creates race conditions in the carrier loop (e.g., building status must update before the carrier polls the next state). The tick-driven model requires deterministic ordering that signals cannot guarantee.
- **Rejection Reason**: The Logistics System's carrier loop processes deterministically on every tick. Signal ordering would break this guarantee. The direct method call pattern (used by all other cross-system integrations in the registry) is more appropriate.

### Alternative C: Autonomous Route Planning (Post-MVP)

The Logistics System automatically plans multi-hop chains (Production → Production → Production) without player intervention.

- **Pros**: Reduces player micromanagement; more "automated" feel.
- **Cons**: Out of MVP/VS scope. The GDD explicitly scopes this to MVP+. The emotional core of the game is deliberate player choice (Foreman fantasy).
- **Rejection Reason**: Scope. Documented as MVP+ in the GDD Overview.

## Consequences

### Positive

- **Clear ownership**: The Logistics System owns the carrier FSM. No ambiguity about which system drives what.
- **Separation of concerns**: The NPC System remains a general-purpose worker manager. The Logistics System is the supply-chain specialist.
- **Tick-driven determinism**: All carrier logic fires on `ticks_advanced()` with a defined processing order. No race conditions from signal ordering.
- **Precedence model**: The carrier FSM fully replaces the NPC task cycle — simple, unambiguous state transitions.
- **Debuggable**: Building status indicators (BLOCKED/STALLED/OPERATING) give the player immediate visual feedback on what's wrong.

### Negative

- **API surface growth**: The Logistics System adds 5 methods to the NPC System interface. Three (`set_carrier_state`, `is_available`, `on_npc_at_location`) are new registrations for this ADR; two (`get_npc_position`, `release_npc`) were already in ADR-0009.
- **Per-tick cost**: Every active carrier requires a state evaluation each tick. At 10 active carriers and ~10 ticks/sec (1x speed, 60fps × 60fps accumulator), this is ~100 evaluations/sec. Each evaluation is O(1) — direct method call via singleton. Estimated cost: ~0.01ms per carrier per tick. At 10 carriers × 10 ticks/sec × 0.01ms = ~1ms/sec, well within the tick-driven systems budget.
- **Complexity**: 8 carrier states + 4 route lifecycle states = 32 state combinations to test. The edge case table (9 ECs) demonstrates the complexity is real.

### Risks

| Risk | Mitigation |
|------|-----------|
| Carrier loop tick ordering conflict with building production tick | Processing order: (1) hunger, (2) building production, (3) carrier poll, (4) day-transition. Buildings produce before carriers poll — a carrier waiting at source picks up the item on the same tick it's produced (AC-5). |
| Route visualization performance with many routes | Route lines use batched `Line2D` rendering. 30 routes at 60fps = ~1.8ms draw calls. Test at higher counts. |
| Carrier timeout starvation (carrier stuck indefinitely) | 300-tick default timeout prevents indefinite blocking. Route DEACTIVATED with clear diagnostic (source vs. destination timeout). |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| logistics-system.md | Three route types (Storage→Production, Production→Storage, Production→Production) | Route model with `route_type` field; `RouteType` enum (INPUT/OUTPUT) |
| logistics-system.md | Carrier FSM with 8 states | `CarrierFSM` with all 8 states defined in the tick-driven loop |
| logistics-system.md | Slot-based assignment (max 1 carrier per slot type) | `create_route()` validates slot availability before assigning |
| logistics-system.md | Travel time = Manhattan distance × ticks_per_tile | `calc_travel_time()` uses `GridMap.distance_between(a, b, DistanceMetric.MANHATTAN)` |
| logistics-system.md | Building status integration (BLOCKED/STALLED/OPERATING) | `_on_carrier_state_changed()` and `_on_route_active_changed()` drive building status |
| logistics-system.md | Carrier waiting timeout (300 ticks) | `CARRIER_WAITING_TIMEOUT` constant; `wait_ticks` counter in WAITING_SOURCE/WAITING_DESTINATION |
| logistics-system.md | NPC ↔ Logistics precedence contract | Carrier FSM fully replaces NPC task cycle; `set_carrier_state()` called on transitions only |
| logistics-system.md | Save/load persistence | `serialize()` and `deserialize()` methods with full state preservation |
| logistics-system.md | Route visualization (always-visible lines, hover highlight) | `RouteLines` Node2D in world tree (not CanvasLayer) with opacity, color, thickness, and pattern encoding |
| logistics-system.md | Route efficiency and carrier count formulas | Formulas 3 and 4 addressed by `get_route_efficiency()` method (implementation detail) |
| npc-system.md | Carrier assignment (Rule 7a) | `release_npc()` called on route deletion; carrier FSM replaces task cycle |
| npc-system.md | NPC management interface contract | All 5 interface methods listed in ADR-0009 registry entry are consumed |
| inventory-storage-system.md | Carrier deposit/withdraw operations | `InventorySystem.try_deposit()` at AT_DESTINATION, `try_consume()` at AT_SOURCE (per ADR-0005) |
| building-system.md | Building slot definitions | Slot validation in `create_route()` |

## Performance Implications

- **CPU**: ~0.01ms per carrier per tick (state evaluation + method calls). At 10 carriers and ~10 ticks/sec (1x speed), this is ~1ms/sec total. Well within the combined tick-driven systems budget.
- **Memory**: Each route stores ~10 fields. 100 routes = ~10KB. Negligible.
- **Load Time**: Route deserialization is O(N) where N = number of routes. At VS scale (10-20 routes), < 1ms.
- **Network**: N/A (single-player).

## Migration Plan

This is a new system with no existing code to migrate. The Logistics System will be added as a new `LogisticsSystem` autoload singleton (following ADR-0007's autoload access pattern). No backward compatibility concerns.

## Validation Criteria

- **Unit test**: All 8 carrier states and 4 route lifecycle states transition correctly given valid inputs.
- **Unit test**: Formula 1 (round-trip ticks) produces correct values for all distance combinations.
- **Unit test**: Formula 2 (throughput per day) returns 0 when round-trip exceeds TICKS_PER_DAY.
- **Unit test**: Slot validation blocks duplicate carrier assignment to the same slot type.
- **Integration test**: Carrier delivers item from storage to production building end-to-end within expected tick budget.
- **Integration test**: Building status transitions correctly (BLOCKED → OPERATING when carrier arrives, STALLED when destination fills).
- **Integration test**: Save/load preserves carrier state and remaining ticks accurately.
- **Manual test**: Route visualization lines are visible, colored correctly, and tooltips show on hover.

## Related Decisions

- ADR-0001: Tick System — carrier timing driver
- ADR-0004: Grid Map — distance calculation
- ADR-0005: Inventory/Storage — carrier deposit/withdraw
- ADR-0006: Save/Load Format — route serialization
- ADR-0008: Building Placement — slot definitions, building status
- ADR-0009: NPC State Machine — carrier state contract
- GDD: logistics-system.md — full mechanical specification
- GDD: npc-system.md — NPC task cycle (suspended during carrier assignment)

---

## Amendment 2026-06-13: Shared-Carrier Model

**Trigger:** Balance finding B3 (`tools/balance/balance-findings.md`) — the original
"1 input carrier + 1 output carrier per route, 1 NPC per route" architecture required
~13 NPCs for a 4-building village. Expansion was blocked by carrier bookkeeping
instead of layout optimization (violating Pillar 3). Implemented 2026-06-12 in
`src/systems/logistics/logistics_system.gd`.

### Decisions

1. **Shared carriers.** One NPC may be the carrier for several routes but serves ONE
   at a time. `LogisticsSystem` keeps `_carrier_active_route: npc_id → route_id`; all
   other routes of that carrier are dormant and skipped by the tick loop.
   - Route IDs changed from `route_<npc>` to `route_<npc>_<source>_<destination>`
     (unique per carrier+pair; the old scheme collided for multi-route carriers).
   - Carrier candidates = idle non-workers PLUS existing carriers
     (`NPCSystem.get_carrier_candidates()`).
2. **Switch after each delivery.** When the carrier has no cargo in hand (after a
   deposit, or at an empty source), it picks the next of its routes **round-robin
   starting after the current one** that *has work* (source has cargo AND destination
   has space), and travels there **from its current tile** (no return home between
   trips).
3. **Wait in place.** If no route has work, the carrier idles at its current tile
   (active route → IDLE) and is re-evaluated every tick batch (`_service_carriers`).
4. **Waiting timeouts removed.** `WAITING_SOURCE` is a legacy state (old saves are
   routed through the decision point); `WAITING_DESTINATION` holds cargo
   **indefinitely** until space frees — switching would destroy held cargo.
   `carrier_waiting_timeout` survives only as a serialized field for save
   compatibility.
5. **Travel constants re-anchored + F4 wired.** `TICKS_PER_TILE` = **5.0** (base at
   100% carrier efficiency; identical constant in LogisticsSystem, NPCSystem,
   BuildingRegistry). Effective leg ticks = `floor(base / carrier_efficiency)`
   (`EfficiencyFormulas.calculate_effective_travel_ticks`, applied once per
   travel-leg transition in `_set_carrier_state`; `current_leg_total_ticks` records
   the effective duration for overlay animation).
6. **`CARRIER_CAPACITY` = 2** items/trip (was 1) so one fed carrier keeps pace with
   one producer at typical distances. Intended to become a per-carrier upgradeable
   stat.
7. **Deletion semantics.** Deleting a route releases the NPC home only when it was
   the carrier's last route; otherwise the carrier keeps serving its remaining
   routes.
8. **Persistence.** On `deserialize()`, each carrier's active route is reconstructed
   as its first non-IDLE route; remaining routes stay dormant.
9. **Singleton access correction.** The original diagram and interface tables show
   `Engine.get_singleton("...")` — that pattern is **forbidden** for GDScript
   Autoloads (returns null silently; see `.claude/rules/godot-singletons.md`). The
   implementation acquires Autoloads by their global names (`NPCSystem`,
   `BuildingRegistry`, `InventorySystem`, `TickSystem`, `PathSystem`) in
   `_ready()`/`_enter_tree()`, with injectable fields for tests. Read the original
   text's `Engine.get_singleton("X")` as "the X Autoload".

### Consequences

- NPC budget for a 4-building village drops from ~13 to ~5–6 (4 workers + 1–2 shared
  carriers).
- Route throughput is now demand-driven; the closed-form per-route throughput
  formulas (original Formulas 2–4) only bound the single-route case. The route
  efficiency score remains a lifecycle stub (story 007).
- UI: overlays must query `get_active_route_for_npc()` so the carrier icon follows
  the one active route; dormant route lines render dimmed.

### Validation

Refactor is implemented and exercised manually in-game; dedicated unit tests for the
scheduler (`_carrier_pick_next` round-robin, wait-in-place, hold-cargo) are still
open — tracked as tech debt with the logistics test suite update.
