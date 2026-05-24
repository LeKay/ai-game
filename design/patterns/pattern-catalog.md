# Design Patterns Catalog: From Scratch

> Central reference for reusable, system-crossing patterns.
> Created: 2026-05-19
> Status: Draft

---

## Catalog

| # | Pattern Name | Category | Used In Systems | Page |
|---|--------------|----------|----------------|------|
| 1 | Tick-Driven Time | Core | Tick, Hunger, Logistics, HUD, Day Overview | 4 |
| 2 | Resource Flow Pipeline | Economy | Resource, Inventory, Building, Hunger, Recipe Database | 8 |
| 3 | Grid-Based Placement | Core | Grid/Map, Building, Camera, HUD | 12 |
| 4 | NPC State Machine | Gameplay | NPC, Hunger, Logistics | 16 |
| 5 | Supply Chain Transport | Gameplay | Logistics, Resource, Inventory | 20 |
| 6 | Hierarchical Storage | Economy | Inventory, Building, NPC, HUD | 24 |
| 7 | Distance-Based Travel | Gameplay | Logistics, Übermap, Camera | 28 |
| 8 | Consumption-Driven Need | Gameplay | Hunger, NPC, Tier | 31 |
| 9 | Data-Driven Recipes | Economy | Recipe Database, Building, Resource | 34 |
| 10 | HUD-Data Binding | UI | HUD, Resource, Inventory, Tick | 37 |

---

## Pattern 1: Tick-Driven Time

### Classification
Category: Core
Authority: Tick System (design/gdd/tick-system.md)

### Summary
All gameplay systems derive their time reference from a single centralized Tick System. No system maintains its own clock or uses wall-clock time. The Tick System owns `ticks_per_day`, variable simulation speed, and tick delivery to all registered systems.

### When to Use
- Any system that needs periodic updates (NPC hunger, building production, NPC movement)
- Any system that needs to react to day boundaries or time-of-day
- Any system that needs deterministic timing independent of frame rate

### When NOT to Use
- Input handling (immediate response required, no tick buffering)
- Rendering (uses frame time, not tick time)
- Save/Load (saves tick counter, doesn't tick itself)

### Core Contract

```
Tick System owns:
- ticks_per_day: constant (e.g., 1000)
- simulation_speed: 1x, 2x, 3x, paused
- tick_interval_ms: derived from speed

Tick System provides:
- tick() signal each tick
- get_ticks_per_day() accessor
- is_day_boundary(tick_number) helper
- get_time_of_day() helper (0.0-1.0 normalized)
```

Each system registers with the Tick System and receives `tick(delta_ticks)` at a configurable rate (every tick, every 10 ticks, every day).

### Rules
1. **Single source of truth** -- no system creates its own timer or uses `_process(delta)` for game logic timing
2. **Deterministic** -- tick count is saveable and loadable; simulation speed changes do not corrupt state
3. **Batch delivery** -- systems registered at a rate receive accumulated ticks in one call (not per-tick)
4. **Day boundary** -- systems that need day transitions must listen for `day_changed` signal, not compute from tick count
5. **Pause isolation** -- paused systems must not advance; input/render systems continue

### Data Types
- Tick count: integer, can grow without bound (use modulo for wrapping)
- Tick rate: integer divisor (1 = every tick, 10 = every 10 ticks, 1000 = once per day)

### Dependencies
- **Required by:** Hunger, Building, NPC, Logistics, HUD, Day Overview
- **Depends on:** None (foundation system)

### Common Pitfalls
- Using `_process(delta)` for game logic instead of tick events
- Systems ticking at different rates causing off-by-one bugs at day boundaries
- Forgetting to unregister systems on scene exit

### Variants
- **Fast-forward safe** -- when speed changes from 1x to 3x, the system delivers 3 ticks at once, not 3 separate calls
- **Paused tick** -- on_pause() signal for systems that need to stop their own timers

---

## Pattern 2: Resource Flow Pipeline

### Classification
Category: Economy
Authority: Resource System (design/gdd/resource-system.md), Inventory System (design/gdd/inventory-storage-system.md)

### Summary
Resources flow through a deterministic pipeline: Source → Production → Storage → Consumption/Sale. Each resource has defined producers and consumers. Resources are never created or destroyed implicitly; every change has a source event.

### When to Use
- Any system that creates, transforms, or destroys resources
- Any system that tracks resource amounts (inventory, NPC consumption, building output)
- Designing new production chains or consumption rules

### Core Contract

```
Resource defined by:
- id: unique string key
- name: display name
- stack_size: max per container
- category: food, material, finished, currency
- spoil_rate: ticks until spoiled (0 = never)

Flow types:
- produce: resource is created (building, gathering)
- consume: resource is removed (crafting, eating, storage)
- transfer: resource moves between containers (logistics, belts)
```

### Flow Graph

```
[natural source] → [storage] → [production building] → [storage] → [consumer]
     (gather)          |              |                      |
     (spawn)           ↓              ↓                      ↓
                   inventory    recipe transform          consumed/spoiled
```

### Rules
1. **Every change is audited** -- resource amount changes must have a reason tag (produce, consume, transfer, spawn, adjust)
2. **No implicit creation** -- resources only appear through defined production chains or explicit debugging commands
3. **Atomic transfers** -- a transfer either fully completes or fully aborts; partial transfers are not persisted
4. **Spoilage is tick-driven** -- spoilage is checked per tick on spoiled resources, subtracted from the source container
5. **Categories gate usage** -- food resources can only be consumed as food; materials can only be used in recipes

### Data Types
- Amount: integer (no fractions of resources)
- Resource ID: string, globally unique
- Flow reason: enum {produce, consume, transfer, spoil, spawn, debug_adjust}

### Dependencies
- **Required by:** Building, Recipe Database, Hunger, Logistics, NPC
- **Depends on:** None (foundation system)

### Common Pitfalls
- Rounding errors when splitting resources across containers
- Spoilage calculating on old amounts instead of current
- Transfers lost when source or destination is destroyed mid-transfer

### Variants
- **Split transfer** -- when source has 7 wood and destination only has space for 3, transfer 3 and return remaining to source
- **Partial production** -- building produces what it can with available inputs, signals partial_output instead of complete

---

## Pattern 3: Grid-Based Placement

### Classification
Category: Core
Authority: Grid/Map System (design/gdd/grid-map-system.md), Building System (design/gdd/building-system.md)

### Summary
The game world is a 2D tile grid. All placement, movement, and visibility calculations reference grid coordinates. Grid cells are immutable until explicitly changed; terrain and tile data persist across gameplay. Buildings and entities occupy one or more contiguous grid cells.

### When to Use
- Placing buildings or entities in the world
- Pathfinding and distance calculations
- Visibility/range checks (e.g., "can NPC reach this building?")
- Map rendering and camera culling

### Core Contract

```
Grid owns:
- width, height: tile dimensions
- cells[x][y]: tile data (terrain, occupied_by, building_id)
- coordinate system: (0,0) at top-left, +x right, +y down

Grid provides:
- is_valid(x, y): bounds check
- is_empty(x, y): no building/entity blocking
- is_terrain_passable(x, y): terrain type check
- get_cell(x, y): tile data
- occupy(x, y, entity_id): mark cell occupied
- free(x, y): release cell
- get_rect_cells(x, y, width, height): all cells in rectangle
```

### Building Footprint Rules
1. Buildings must fit within grid boundaries
2. All cells in a building's footprint must be passable terrain
3. No two buildings can occupy the same cell
4. Buildings with rectangular footprints must occupy a contiguous rectangle
5. Placement preview shows occupied cells before confirming

### Rules
1. **Grid is authoritative** -- screen positions are always derived from grid positions, never the reverse
2. **Placement validation is atomic** -- all footprint cells are checked before any cell is marked occupied
3. **Cell state is immutable except through Grid API** -- no direct cell modification from outside
4. **Multi-cell entities** -- entities occupying multiple cells (large buildings) claim all cells simultaneously or none

### Data Types
- Grid coordinates: integer (x, y)
- Tile type: enum (grass, forest, water, etc.)
- Occupancy: string (entity_id or null)

### Dependencies
- **Required by:** Building, Camera, Player Character, Logistics, NPC movement
- **Depends on:** Resource System (terrain type)

### Common Pitfalls
- Off-by-one errors in footprint calculations
- Not accounting for building expansion tiles (e.g., foundation + walls)
- Camera culling using screen bounds instead of grid bounds

### Variants
- **Rotated footprint** -- buildings can be rotated, changing occupied cells
- **Terrain modification** -- some buildings alter terrain (e.g., clearing trees on placement)

---

## Pattern 4: NPC State Machine

### Classification
Category: Gameplay
Authority: NPC System (design/gdd/npc-system.md), Hunger System (design/gdd/hunger-system.md)

### Summary
Each NPC operates as a finite state machine with explicitly defined transitions. States are mutually exclusive (one active at a time). Transitions are triggered by conditions (internal state or external events). Each state defines an enter behavior, a per-tick behavior, and exit conditions.

### When to Use
- Any character with behavior (NPCs, player character)
- Systems that need to know "what is this entity doing?" for pathfinding or allocation
- Hierarchical behavior (NPC has sub-states within a work state)

### State Taxonomy

```
State types:
- Idle: waiting for a task or trigger
- Travel: moving between two grid positions
- Working: performing an action at a location
- Consuming: eating/drinking
- Panicking: reacting to a crisis (fire, starvation)
- Sleeping: rest cycle (future tier)

State properties:
- state_id: unique string
- enter_actions: executed on state entry
- tick_actions: executed every tick (configurable rate)
- exit_actions: executed on state exit
- transition_conditions: {condition -> next_state} map
- priority: higher-priority states preempt lower ones
```

### State Precedence
When multiple transition conditions are true simultaneously:

| Priority | State | Reason |
|----------|-------|--------|
| 0 (highest) | Panicking | Survival override |
| 1 | Consuming | Hunger cannot be deferred |
| 2 | Working | Assigned tasks |
| 3 | Travel | Between states |
| 4 (lowest) | Idle | Default state |

### Transition Rules
1. **Atomic transitions** -- an NPC is never in two states simultaneously
2. **Preemption** -- higher-priority states can interrupt lower ones (panic, consume)
3. **Re-entry** -- returning to the same state must clean up previous entry (no stale data)
4. **No self-transition without state change** -- idle → idle must only occur if something changed
5. **All states reachable from all others** -- no dead-end states

### Data Types
- State ID: string
- Transition condition: {type: "timer"|"resource"|"position"|"event", data: ...}
- NPC state: current_state + stack of pending transitions

### Dependencies
- **Required by:** Hunger, Logistics, Building interaction
- **Depends on:** Tick System, Grid/Map System, Inventory/Storage System

### Common Pitfalls
- State stack overflow (too many nested transitions)
- Forgotten cleanup on re-entry (NPC remembers old task data)
- Dead states where no exit condition is ever true

### Variants
- **Sub-states** -- a Work state can have sub-states (Gathering → Processing → Producing) without changing the parent state
- **Interruptible vs non-interruptible** -- certain work states (e.g., crafting) cannot be preempted

---

## Pattern 5: Supply Chain Transport

### Classification
Category: Gameplay
Authority: Logistics System (design/gdd/logistics-system.md)

### Summary
Material transport between buildings is modeled as a directed edge in a supply chain graph. Each edge has a defined source, destination, resource type, and transport method. Carriers (NPCs) or belts execute the transport. Transport time is calculated from the Manhattan distance between source and destination.

### When to Use
- Designing new building-to-building connections
- Adding transport methods (belts, carriers, tubes)
- Calculating production capacity based on transport bottlenecks
- Debugging why a building is starved of resources

### Graph Model

```
Supply Chain = Directed Graph
  Nodes = Buildings (sources and destinations)
  Edges = Transport connections (source → dest, resource, quantity_per_tick)
  Carriers = Flow along edges (NPCs or belts)
```

### Edge Definition
```
Edge properties:
- source_id: building id
- destination_id: building id
- resource_id: resource being transported
- output_rate: amount per tick at destination
- transport_type: carrier or belt
- max_carriers: max simultaneous transporters on this edge
- timeout_ticks: max wait time at source before aborting (default: 300)
```

### Transport Execution Cycle
1. **Check source** -- source building has the resource ready (output stockpile)
2. **Check destination** -- destination building can accept the resource (space)
3. **Assign carrier** -- find available carrier (for carrier transport)
4. **Calculate route** -- path from source output tile to destination input tile
5. **Calculate travel time** -- based on distance legs (see Pattern 7)
6. **Execute transport** -- carrier moves, unloads, returns
7. **Update production** -- destination building credits received resource

### Edge Cases
- Source has no output yet (production not finished)
- Destination is full (cannot accept more)
- Path is blocked (destroyed building, terrain change)
- Carrier is incapacitated (starvation, death)
- Source/dest relationship changes (building demolished)

### Rules
1. **Edges are declarative** -- the connection is defined; transport execution is automatic
2. **No circular transport** -- A→B→A with the same resource is blocked (waste loop)
3. **Transport is priority-ordered** -- starved critical paths (feeding Tier 2 housing) > luxury paths
4. **Abandoned edges are cleaned up** -- when a building is destroyed, all edges referencing it are removed

### Dependencies
- **Required by:** (none currently, but future: Trade, Overworld)
- **Depends on:** Grid/Map System, NPC System, Building System, Tick System, Resource System

### Common Pitfalls
- Circular dependencies creating infinite transport loops
- Over-provisioning carriers (too many waiting, wasting NPC capacity)
- Not handling partial output (building produces 3/5 needed items)

### Variants
- **Buffered transport** -- destination has a small stockpile; transport completes when buffer fills
- **Scheduled transport** -- transport only at specific times (e.g., once per day)

---

## Pattern 6: Hierarchical Storage

### Classification
Category: Economy
Authority: Inventory/Storage System (design/gdd/inventory-storage-system.md)

### Summary
Resources are stored in a hierarchy: world containers (silos, chests) hold items; individual NPCs and buildings have personal inventories. All storage nodes implement a uniform interface: `get_capacity()`, `get_amount(resource_id)`, `store(resource_id, amount)`, `withdraw(resource_id, amount)`. The storage hierarchy is traversed top-down (world containers before personal inventories) for resource distribution.

### When to Use
- Any entity that holds resources (NPCs, buildings, containers)
- Systems that need to allocate or distribute resources (logistics, hunger, crafting)
- UI that shows inventory contents

### Hierarchy

```
World Storage (shared)
├── Silo (bulk food, capacity 500)
├── Warehouse (general goods, capacity 1000)
└── Chest (small storage, capacity 100)

Personal Storage (private)
├── NPC inventory (carry capacity, capacity 20)
└── Building input/output slots (capacity varies)

Player inventory
└── Player carry (capacity 30)
```

### Interface Contract
```
All storage nodes implement:
- get_max_capacity(resource_id) -> int
- get_amount(resource_id) -> int
- get_total_capacity() -> int
- is_full(resource_id) -> bool
- is_empty(resource_id) -> bool
- store(resource_id, amount) -> stored_amount (may be partial)
- withdraw(resource_id, amount) -> withdrawn_amount (may be partial)
- get_resources() -> array of resource_ids
```

### Allocation Strategy
When multiple storage nodes can supply a resource (e.g., hunger system needs food):
1. **Priority order** -- personal inventories before world storage (NPCs eat what they carry first)
2. **Proportional distribution** -- if multiple NPCs need food, distribute from common pool proportionally
3. **FIFO for spoiled** -- older resources (closer to spoil) are consumed first

### Rules
1. **Uniform interface** -- all storage nodes share the same API regardless of type
2. **Partial withdrawals allowed** -- withdraw 10 when only 7 available returns 7
3. **No negative storage** -- amount can never go below 0
4. **Ownership is enforced** -- NPCs can only withdraw from world storage if authorized (logistics assignment)
5. **Capacity is per-resource** -- silo can hold 500 grain and 500 stone simultaneously

### Dependencies
- **Required by:** Hunger, NPC, Building, Logistics, HUD, Player Character
- **Depends on:** Resource System

### Common Pitfalls
- Forgetting to check capacity before storing
- Double-counting resources (same item in NPC inventory AND world storage)
- Allocation strategy favoring wrong nodes (giving NPC food from warehouse when they already carry food)

---

## Pattern 7: Distance-Based Travel

### Classification
Category: Gameplay
Authority: Logistics System (design/gdd/logistics-system.md), Camera System (design/gdd/camera-system.md)

### Summary
Travel time between any two points on the grid is calculated from the Manhattan distance. The distance is split into legs for multi-journey trips (home→source→dest→home). Travel time = distance / movement_speed. This model is used for NPC carriers, NPC home-sickness, and future Übermap travel.

### When to Use
- Calculating how long a transport trip takes
- Determining if an NPC is "too far" from home (happiness/speed penalty)
- Pathfinding between two grid positions
- Camera travel animation time

### Distance Calculation

```
Manhattan distance:
  distance = abs(x2 - x1) + abs(y2 - y1)

Travel time (ticks):
  travel_ticks = ceil(distance / max_speed_per_tick)

Multi-leg journey:
  total_ticks = leg_1_ticks + leg_2_ticks + ... + leg_n_ticks

Example: Home(0,0) → Woodcutter(30,0) → Builder(60,0) → Home(0,0)
  leg_1 = 30 tiles
  leg_2 = 30 tiles
  leg_3 = 60 tiles
  total = 120 tiles / 1 tile_per_tick = 120 ticks
```

### Travel State Machine

```
[Idle] → (assigned task) → [Travel to Source]
                                  ↓ (arrive, load)
                         [Travel to Destination]
                                  ↓ (arrive, unload)
                         [Travel to Home / Return to Task]
                                  ↓
                               [Idle / Work]
```

### Speed Modifiers
- Base speed: configurable per NPC type
- Terrain modifiers: grass = 1.0x, forest = 0.7x, water = 0.0x (impassable)
- Load modifier: carrying weight = 0.8x speed
- Home distance modifier: > 40 tiles from home = 0.9x speed (homesickness)

### Rules
1. **Manhattan distance only** -- no diagonal distance; movement is tile-by-tile orthogonal
2. **Distance is from center tile** -- building positions use their center tile for distance calculations
3. **Travel is point-to-point** -- no dynamic rerouting mid-journey (path can be recalculated on new tick)
4. **Timeout on stuck** -- if an NPC hasn't changed position for N ticks, the trip is aborted and a new path is computed

### Dependencies
- **Required by:** Logistics, Hunger, NPC State Machine
- **Depends on:** Grid/Map System, NPC System

### Common Pitfalls
- Using Euclidean distance instead of Manhattan (causes time mismatches)
- Not handling impassable terrain (straight-line distance when path is blocked)
- Travel time rounding errors accumulating over many short trips

---

## Pattern 8: Consumption-Driven Need

### Classification
Category: Gameplay
Authority: Hunger System (design/gdd/hunger-system.md), NPC System (design/gdd/npc-system.md)

### Summary
Entities (NPCs, player character) have a consumption meter that drains over time. When the meter drops below a threshold, the entity enters a consuming state. Consumption deducts from the entity's personal inventory first, then from shared storage. Different consumption tiers (food, shelter, clothing) unlock at different population levels. Starvation is the consequence of unmet consumption.

### When to Use
- Any system that consumes resources over time
- Designing population tier requirements
- Implementing the player character's needs
- Balancing resource economy (how many resources do N entities consume per day?)

### Consumption Model

```
Entity consumption:
  consumption_rate: amount per tick (e.g., 0.001 food per tick)
  consumption_threshold: below this amount, entity is unhappy (e.g., < 50% capacity)
  starvation_rate: consequence of unmet consumption (e.g., -1 health per day)

Consumption tiers (population-based):
  Tier 1: food only
  Tier 2: food + shelter + clothing
  Tier 3: food + shelter + clothing + luxury goods
```

### Consumption Cycle
1. **Per tick** -- drain consumption_amount from available storage
2. **Per day boundary** -- check if total daily consumption was met
3. **Unmet consumption** -- apply penalty (unhappiness, health loss, productivity loss)
4. **Full consumption** -- entity is satisfied, no penalty

### Consumption Priority
When resources are scarce, which consumption is met first:
1. Food (survival, cannot be skipped)
2. Shelter (housing requirement, affects spawning)
3. Clothing (tier advancement requirement)
4. Luxury (no penalty if unmet, only affects happiness)

### Rules
1. **Consumption is continuous** -- resources drain per tick, not as a daily lump sum
2. **No consumption debt** -- unmet consumption does not carry over as "owed" amount; penalties are applied per cycle instead
3. **Personal inventory priority** -- entities consume from carried inventory before requesting from storage
4. **Tier gates are hard** -- a tier requirement cannot be partially met; all required resources must be available

### Dependencies
- **Required by:** NPC, Population Tier, Player Character
- **Depends on:** Inventory/Storage System, Tick System, Resource System

### Common Pitfalls
- Daily lump-sum consumption causing sudden starvation (too harsh)
- Per-tick drain causing floating-point accumulation errors (use integer tick counts)
- Not handling consumption when entity count changes (new NPCs spawn mid-consumption cycle)

---

## Pattern 9: Data-Driven Recipes

### Classification
Category: Economy
Authority: Recipe Database System (design/gdd/recipe-database.md)

### Summary
All crafting and production transformations are defined as data objects, not hardcoded logic. A recipe specifies input resources, output resources, production time, and the building type required. The production system reads recipes at runtime and applies transformations without needing code changes for new recipes.

### When to Use
- Adding new craftable items or producible buildings
- Balancing production costs or yields
- Designing new production chains
- Adding moddable content

### Recipe Schema
```
Recipe properties:
- id: unique string
- name: display name
- category: craft, produce, refine
- inputs: {resource_id: amount, ...}
- outputs: {resource_id: amount, ...}
- production_time_ticks: integer
- required_building: building_type_id
- unlocked_by: prerequisite recipe or tier (optional)
```

### Recipe Resolution Flow
1. **Lookup** -- player or building requests a recipe by ID
2. **Validation** -- inputs are available, required building exists, prerequisites met
3. **Execution** -- inputs are consumed, production timer starts
4. **Completion** -- outputs are added to building output slot
5. **Notification** -- relevant systems (HUD, inventory) are updated

### Recipe Dependency Rules
1. **No circular recipes** -- recipe A producing B cannot require B as input
2. **All outputs must be defined** -- output resource IDs must exist in the Resource System
3. **Input amounts are absolute** -- no percentage-based inputs (always exact amounts)
4. **Production time is constant** -- no variable production time based on conditions (tunable via building upgrades)

### Dependencies
- **Required by:** Building, Resource System
- **Depends on:** Resource System, Building System

### Common Pitfalls
- Recipes producing 0 net resources (inputs == outputs, waste of production time)
- Missing prerequisite unlocks (recipe available before its ingredients exist)
- Hardcoded building requirements (should be referenceable by building type ID)

---

## Pattern 10: HUD-Data Binding

### Classification
Category: UI
Authority: HUD System (design/gdd/hud-system.md)

### Summary
The HUD displays game state through data-bound UI elements. Each HUD element subscribes to one or more data sources (Resource System, Tick System, Inventory System) and updates when the source changes. The HUD does not poll game state; it reacts to change events. This ensures the HUD always reflects current state without performance cost from constant polling.

### When to Use
- Any player-facing display of game state
- Resource counters, production indicators, time display
- Dynamic feedback (warnings, notifications, alerts)

### Data-Source Mapping
```
HUD Element          → Data Source(s)
─────────────────────────────────────────
Resource counters    → Resource System, Inventory System
Play/Pause button    → Tick System
Day counter          → Tick System
Production status    → Building System (current recipe, progress)
NPC count            → NPC System (alive, working, idle)
Logistics network    → Logistics System (active edges, pending transports)
Hunger status        → Hunger System (met/unmet consumption)
```

### Update Model
```
Change-driven:
  data_source.on_change(signal) → hud_element.update()

No polling:
  HUD does NOT read game state in _process() or _physics_process()

Update rates:
  Real-time (every change): resource amounts, tick counter
  Throttled (every N ticks): production progress bars, NPC status grid
  Event-only: notifications, warnings
```

### Rules
1. **Subscribe, don't poll** -- HUD elements connect to data source signals
2. **Coalesce rapid updates** -- resource changes happening 10x per tick are batched into one HUD update
3. **Decouple from game state** -- HUD elements receive immutable snapshots, not live references
4. **Graceful degradation** -- if a data source is unavailable (scene not loaded), HUD shows placeholder or hidden

### Dependencies
- **Required by:** (player-facing display only)
- **Depends on:** Resource System, Tick System, Inventory System, Building System, NPC System, Logistics System, Hunger System

### Common Pitfalls
- Polling in `_process()` causing frame drops with many HUD elements
- Race condition: HUD reads state between a withdraw and a signal
- Memory leaks: HUD not disconnecting signals on scene exit

---

## Pattern Usage Reference

### Cross-Reference Matrix

Which patterns are used by which systems:

| Pattern \ System | Tick | Resource | Input | Recipe DB | Grid | Player | Camera | Inventory | Building | NPC | Hunger | Logistics | HUD |
|------------------|------|----------|-------|-----------|------|--------|--------|-----------|----------|-----|--------|-----------|-----|
| Tick-Driven Time | 1 | 2 | — | 1 | 1 | 1 | — | 1 | 1 | 1 | 1 | 1 |
| Resource Flow | — | 1 | — | 2 | — | 1 | — | 2 | 2 | 1 | 2 | 1 |
| Grid-Based Placement | 1 | — | 1 | — | 1 | 1 | 2 | — | 2 | 1 | — | 1 | — |
| NPC State Machine | — | — | — | — | 1 | 1 | — | 1 | 1 | 1 | 1 | — | — |
| Supply Chain Transport | — | 1 | — | — | 1 | — | — | 1 | 2 | 2 | — | 1 | — |
| Hierarchical Storage | — | 1 | — | — | — | 1 | — | 1 | 1 | 1 | 1 | 1 | 1 |
| Distance-Based Travel | 1 | — | — | — | 1 | 1 | 1 | — | 1 | 1 | 1 | 1 | — |
| Consumption-Driven Need | 1 | — | — | — | — | 1 | — | 1 | 1 | 1 | 1 | — | — |
| Data-Driven Recipes | — | 1 | — | 1 | — | — | — | — | 1 | — | — | — | — |
| HUD-Data Binding | 1 | 1 | — | — | — | — | — | 1 | 1 | 1 | 1 | 1 | 1 |

Usage intensity: 1 = required, 2 = primary dependency

### Pattern Evolution Guidance

When adding a new system, check this catalog first:
1. **Does an existing pattern cover this?** -- adapt before inventing
2. **If extending a pattern** -- document the extension as a variant under the existing pattern
3. **If creating a new pattern** -- add to the catalog table, define all sections, cross-reference with existing patterns
4. **Review existing patterns** -- new systems may reveal that old patterns need refinement
