# Logistics System

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-05-19
> **Implements Pillar**: Pillar 1 (Earned Automation), Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)

## Overview

The Logistics System is the village's supply chain — it connects buildings via NPC carriers that physically move resources across the map. Production buildings use carriers to deliver inputs (bringing them upstream goods) and collect outputs (taking finished goods away). Storage buildings receive outputs from production buildings and provide inputs to production buildings. Extraction buildings (Lumber Camp, Quarry) operate on resources in their proximity — no input carriers needed — but still have output carriers that collect their processed goods. A building without the carriers it needs enters BLOCKED (missing inputs) or STALLED (output can't leave). Transport time is distance-based — Manhattan distance multiplied by `ticks_per_tile` (default 3.0) — so a building placed 10 tiles from its destination pays 30 ticks per one-way trip. This is the core spatial optimization puzzle: place buildings close together for throughput, far apart for variety.

The system supports three route types:
- **Storage → Production**: Carriers deliver raw/intermediate goods to buildings that need inputs
- **Production → Storage**: Carriers collect finished goods and deliver them to storage
- **Production → Production**: Multi-hop chains where one building's output feeds another building's input (e.g., Lumber Camp → Sawmill → Plank Storage)

The Logistics System does not simulate visible NPC movement as a visual spectacle — carriers are abstract entities whose routes are communicated through building status indicators and route lines. A carrier's journey is a mechanic, not a spectacle. This keeps the system debuggable (Pillar 2) and scoped for solo development.

**Scope note:** The Vertical Slice implements the carrier assignment loop (assign NPC → route → building produces) and building status feedback (BLOCKED/STALLED). Multi-hop chain planning, efficiency metrics (Formulas 3 and 4), and route optimization tools are MVP+ features that extend the core VS loop.

*Reference: Factorio's conveyor belt logic abstracted into human-scale NPC carriers; Anno's population-tier supply chains where buildings starve without resource delivery.*

**What would go wrong if this system is broken:** Buildings sit idle while the player doesn't know why — no one is transporting the resources. Or worse, the player assigned a carrier but the route is inefficient (too many tiles, too slow), so buildings produce half-speed. The core loop — identify bottleneck, route resources, watch production stabilize — breaks into "I built things but nothing is happening."

## Player Fantasy

**"The Village Works Because of You."**

Every carrier trip, every completed delivery, every optimized route is evidence that the player's decisions created something that runs without them. The logistics system is the proof that the player built something real.

**The first carrier** proves delegation works. The player assigns the first NPC to a Storage → Sawmill route. They watch it walk to the storage, grab a plank, and walk away. It's slow (12 tiles × 3 ticks = 36 ticks each way — about 3.6 seconds at 1x speed). But when the item drops into the Sawmill's input buffer and the building's status turns from yellow to green, the player feels a discrete, satisfying click of purpose fulfilled. This is the moment "I built things but nothing is happening" becomes "I built things and they work."

**The multi-hop chain** proves systemic thinking. The Lumber Camp delivers wood to the Sawmill, which produces planks, and a second carrier carries those planks to Plank Storage. Three buildings, three routes, one coherent flow. The player zooms out and watches resources move end-to-end. They didn't build a single machine — they built a *system*. This is the moment the player stops seeing individual buildings and starts seeing a production network.

**The optimized route** proves spatial mastery. The player spots that Plank Storage is 20 tiles from the Sawmill — 120 ticks per trip, 6 carriers needed for peak throughput. They rebuild the storage 5 tiles closer, reducing to 30 ticks per trip, requiring only 2 carriers. The efficiency gain is visible in the building status: the Sawmill goes from "2/3 carriers needed" to "saturated." The player optimized with spatial reasoning, not micromanagement.

All three moments are the same underlying emotion at different stages of progression. The logistics system is the emotional arc of the game made tangible: from "I can do things myself" to "I built a system that runs itself" to "I can read the village's health at a glance."

**What it serves:** Pillar 1 (Earned Automation — the player sees the direct result of every carrier assignment), Pillar 2 (Information Transparency — carrier routes are visible through building status, every delay is debuggable), Pillar 3 (Optimization Over Expansion — every tile of distance is a design tradeoff the player must solve).

## Detailed Design

### Core Rules

**1. Route Model**

A route is an explicit connection between two buildings that assigns an NPC carrier to transport resources. The Logistics System manages three route types:

| Route Type | Direction | Purpose |
|------------|-----------|---------|
| Storage → Production | Output from storage → Input to production | Deliver raw/intermediate goods to buildings that need them |
| Production → Storage | Output from production → Input to storage | Collect finished goods for storage |
| Production → Production | Output from production → Input to other production | Move intermediate goods in multi-hop chains |

Each route has these properties:
- `source_building_id`: The building where the carrier picks up items
- `destination_building_id`: The building where the carrier delivers items
- `npc_id`: The NPC assigned to this route (a single NPC serves one route at a time)
- `route_type`: INPUT or OUTPUT — which slot type on the source building this route fills
- `active`: Boolean — whether the route is active or toggled off

A building can have at most one carrier per slot type. A building with `output_slots = 1` can have at most one route with `route_type = OUTPUT`. If the player tries to assign a second carrier to that slot, the action is blocked with "This building has no free output slots."

**2. Route Creation**

The player creates routes through the Transportation Management UI (see `design/ux/transportation.md`). The UI presents two views:
- **Active Routes List**: Shows all existing routes with From → To, resource, NPC, status
- **Route Detail**: The player selects source building (map-select), destination building (map-select), and assigns an available NPC

Route creation is player-driven — no auto-assignment. This serves the Foreman fantasy: the player deliberately decides which NPC goes where.

Route discovery is organic — the player discovers multi-hop chains when they build a second production building that needs inputs from the first. There is no gating or unlock.

**3. Route Execution (Continuous Loop)**

Once a route is created and active, the assigned NPC loops continuously:

```
TRAVEL_TO_SOURCE → PICKUP → TRAVEL_TO_DESTINATION → UNLOAD → RETURN_HOME → (repeat)
```

- **TRAVEL_TO_SOURCE**: NPC moves from home to the source building. Travel time = Manhattan distance × `ticks_per_tile` (Formula 1).
- **PICKUP**: If the source building has output in its buffer, the carrier picks up `min(buffer_amount, carrier_capacity)` items. If the buffer is empty, the carrier enters WAITING_SOURCE (see EC-L6).
- **TRAVEL_TO_DESTINATION**: NPC moves to the destination building. Travel time = Manhattan distance × `ticks_per_tile`.
- **UNLOAD**: If the destination has space (storage has free slots or the destination building's input buffer is available), the carrier unloads immediately. If the destination is full, the carrier enters WAITING_DESTINATION (see EC-L5).
- **RETURN_HOME**: NPC returns home. Travel time = Manhattan distance from destination to home × `ticks_per_tile`. On arrival, the NPC enters IDLE and immediately starts the next trip by traveling back to the source.

The carrier always returns home between trips. This maintains the spatial connection to the village and makes trip time visible to the player.

**4. Slot-Based Assignment**

Each building type has defined carrier slots:

| Building Type | Input Slots | Output Slots | Notes |
|---------------|-------------|--------------|-------|
| Storage | 1 | 1 | Receives output from production; delivers stored goods to production |
| Extraction (Lumber Camp, Quarry) | 0 | 1 | Operates on resources in proximity; no input carriers needed |
| Processing (Sawmill, Mill) | 1 | 1 | Receives upstream goods; delivers processed output |

A route with `route_type = INPUT` fills an input slot on the destination building. A route with `route_type = OUTPUT` fills an output slot on the source building. Slot definitions are hard limits — the Logistics System blocks route creation if no free slots exist.

**5. Carrier State Machine**

The NPC's carrier state (managed by the Logistics System, executed through the NPC System) defines these states:

| State | Description | Transitions |
|-------|-------------|-------------|
| IDLE | Not actively transporting; at home base | → TRAVEL_TO_SOURCE (route starts) |
| TRAVEL_TO_SOURCE | Moving to source to pick up | → AT_SOURCE (arrived), → IDLE (route deactivated) |
| AT_SOURCE | At source building; attempting pickup | → TRAVEL_TO_DESTINATION (picked up), → WAITING_SOURCE (empty buffer), → IDLE (route deactivated) |
| WAITING_SOURCE | Source has nothing to carry | → TRAVEL_TO_DESTINATION (item produced), → IDLE (route deactivated) |
| TRAVEL_TO_DESTINATION | Moving to destination to deliver | → AT_DESTINATION (arrived), → IDLE (route deactivated) |
| AT_DESTINATION | At destination; attempting unload | → TRAVEL_TO_HOME (unloaded), → WAITING_DESTINATION (destination full), → IDLE (route deactivated) |
| WAITING_DESTINATION | Destination is full; waiting | → TRAVEL_TO_HOME (space opens), → IDLE (route deactivated) |
| RETURN_HOME | Traveling back to home base | → IDLE (arrived, next trip begins) |

The Logistics System calls `npc_system.set_carrier_state(npc_id, state)` to transition. The NPC System tracks the NPC's position and physical state. The two systems share the carrier state as their interface.

**6. Building State Integration**

The Logistics System communicates with the Building System through slot assignment status:

| Condition | Building State | Cause |
|-----------|---------------|-------|
| Building needs input carrier, has none | BLOCKED | No carrier on any input slot |
| Building has output, no carrier assigned | STALLED | Output buffer fills, production halts |
| Output carrier assigned but destination full | STALLED | Carrier in WAITING_DESTINATION state |
| Building is producing, carriers assigned and functioning | OPERATING (green) | Normal operation |

When a route is deleted or deactivated, the corresponding slot is freed. If this causes the building to lose all its input carriers, the building transitions to BLOCKED. If the building loses all output carriers, it transitions to STALLED once the buffer fills.

**7. Route Persistence**

Routes are saved and loaded as part of game state. Each route is tied to a specific NPC. If the NPC is removed (house demolished, player confirmation), the route is deactivated but not deleted — the player can reassign a new NPC. Route data is preserved to allow quick re-establishment.

Route data model:
```
route {
    id: string
    source_building_id: string
    destination_building_id: string
    npc_id: string
    route_type: INPUT | OUTPUT
    active: bool
}
```

### States and Transitions

**Route Lifecycle States:**

| State | Description | Transitions |
|-------|-------------|-------------|
| DRAFT | Route is being configured (player selecting source/destination) | → ACTIVE (player confirms), → DELETED (player cancels) |
| ACTIVE | Route is executing; NPC is looping | → PAUSED (player toggles off), → DELETED (player deletes) |
| PAUSED | Route exists but NPC is idle at home | → ACTIVE (player toggles on), → DELETED (player deletes) |
| DEACTIVATED | Route is broken (source/destination demolished, NPC removed) | → ACTIVE (player reconfigures), → DELETED (player deletes) |

### Interactions with Other Systems

**NPC System** — Primary dependency. The Logistics System treats NPCs as carriers. It calls `npc_system.set_carrier_state(npc_id, state)` and `npc_system.get_npc_position(npc_id)` to track carrier movement.

**State Machine Contract (NPC System ↔ Logistics System):**
The NPC System and the Logistics System each own a state machine. They operate at different abstraction levels:

| Layer | Owner | What it tracks |
|-------|-------|----------------|
| NPC Task Cycle | NPC System | Where the NPC is physically, what building they work at, where they deposit |
| Carrier State | Logistics System | Which route they serve, whether they are transporting a resource |

**Precedence rules:**
- When an NPC is assigned to a route, the Logistics System's carrier FSM **fully replaces** the NPC System's task cycle for that NPC. The NPC System still tracks position, but the Logistics System dictates the NPC's work behavior.
- When an NPC has no active route, the NPC System's task cycle runs normally (IDLE → WORK → RETURN).
- The Logistics System does **NOT** call `npc_system.set_carrier_state()` every tick. It only calls it on state *transitions* (e.g., when a carrier completes a trip and the NPC returns home idle). The NPC System's internal simulation loop transitions the carrier between logistics states using the state table in Core Rules 5.

**Interface methods (defined by the NPC System, called by Logistics System):**
| Method | Called By | When |
|--------|-----------|------|
| `npc_system.set_carrier_state(npc_id, state)` | Logistics System | On carrier FSM transition |
| `npc_system.get_npc_position(npc_id)` | Logistics System | On route creation for distance calculation |
| `npc_system.is_available(npc_id)` | Logistics System | During route creation |
| `npc_system.release_npc(npc_id)` | Logistics System | When route is deleted/deactivated |
| `npc_system.on_npc_at_location(npc_id, building_id)` | NPC System → Logistics System | Carrier arrives at source or destination building |

**Building System** — Provides building slot definitions (`input_slots`, `output_slots`), building positions (for distance calculation), and building state (BLOCKED/STALLED transitions). The Logistics System calls `building_system.has_output_buffer(building_id)` and `building_system.get_free_input_slots(building_id)` to validate carrier actions. When the building produces output, the Logistics System's carrier picks it up. When the carrier delivers to a building, the Building System deposits it via `building_system.accept_input(building_id, resource_type, quantity)`.

**Grid/Map System** — Provides Manhattan distance calculation: `grid_map.get_manhattan_distance(pos_a, pos_b)`. Used by Formula 1. Buildings are transparent to carrier pathfinding (carriers move along grid axes, no obstacle avoidance at MVP scope).

**Tick System** — All carrier timing is tick-based. Carriers advance only when time is RUNNING. On day transition, carriers continue their loop across day boundaries without interruption.

**Inventory/Storage System** — Provides capacity checks (`storage.has_free_slots()`, `storage.get_current_count()`). When a carrier unloads at a storage building, the Inventory System deducts from the building's capacity. When a carrier picks up from storage, the Inventory System removes the item.

**Transportation Management UI** (`design/ux/transportation.md`) — Player-facing interface for route creation, editing, and deletion. The Logistics System provides data queries (`get_active_routes()`, `get_route_status(npc_id)`) and receives commands (`create_route()`, `delete_route(npc_id)`, `toggle_route(npc_id, active)`).

## Formulas

### Formula 1: Round-Trip Time

The carrier_round_trip_ticks formula is defined as:

`carrier_round_trip_ticks = (dist_home_source + d + dist_dest_home) × ticks_per_tile + loading_ticks + unloading_ticks`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Home → source distance | `dist_home_source` | int | 0–750 | Manhattan distance from the NPC's home base to the source building. For carriers whose home base is at the source building, this is 0. |
| Source → destination distance | `d` | int | 0–750 | Manhattan distance between source and destination buildings. Maximum for 30×30 grid: 58 (corner to corner). |
| Dest → home distance | `dist_dest_home` | int | 0–750 | Manhattan distance from destination back to the NPC's home base. For carriers whose home base is at the source building, this equals `d`. |
| Ticks per tile | `tpt` | float | 1.0–10.0 | Default: 3.0. Shared with NPC Movement constant (see NPC System GDD). |
| Loading ticks | `lt` | int | 1–10 | Ticks for the loading phase. Default: 1. Scales with carrier_capacity in future. |
| Unloading ticks | `ut` | int | 1–10 | Ticks for the unloading phase. Default: 1. |

**Output Range:** [2, ∞) ticks — minimum 2 ticks (all distances = 0, 1 tick load, 1 tick unload).

**Planning shortcut (home at source):** When the NPC's home base is at or adjacent to the source building (`dist_home_source = 0`), then `dist_dest_home = d`, and the formula simplifies to:
`carrier_round_trip_ticks = floor(d × ticks_per_tile × 2) + loading_ticks + unloading_ticks`

**Example (full):** Home at (0, 0), source at (3, 7), destination at (8, 2). `dist_home_source = 10`, `d = 10`, `dist_dest_home = 13`. `ticks_per_tile = 3.0`.
`carrier_round_trip_ticks = (10 + 10 + 13) × 3.0 + 1 + 1 = 105 + 2 = 107 ticks`

**Example (planning shortcut, home at source):** Source at (3, 7), destination at (8, 2). Distance = 10. Home at source. `ticks_per_tile = 3.0`.
`carrier_round_trip_ticks = floor(10 × 3.0 × 2) + 1 + 1 = 60 + 2 = 62 ticks`

At 1x speed (10 ticks/real second), this is 6.2 seconds of real time per round trip.

### Formula 2: Route Throughput Per Day

The route_throughput_per_day formula is defined as:

`route_throughput_per_day = floor(TICKS_PER_DAY / carrier_round_trip_ticks) × carrier_capacity`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Ticks per day | `TPD` | int | 1000 | Fixed constant. 1 day = 1000 ticks (see Tick System GDD). |
| Round-trip ticks | `carrier_round_trip_ticks` | int | 2–∞ | From Formula 1. |
| Carrier capacity | `cap` | int | 1–∞ | Items per trip. Default: 1. |

**Output Range:** [0, ∞) items/day. If `carrier_round_trip_ticks > TICKS_PER_DAY`, throughput is 0 (carrier never completes a trip in one day).

**Example:** `carrier_round_trip_ticks = 62`, `carrier_capacity = 1`.
`route_throughput_per_day = floor(1000 / 62) × 1 = floor(16.13) × 1 = 16 items/day`

With `carrier_capacity = 1`, a 10-tile route delivers 16 items per day. At distance 30 (round trip = 182 ticks): `floor(1000 / 182) × 1 = 5 items/day`.

### Formula 3: Route Efficiency Score

The route_efficiency formula is defined as:

`route_efficiency = (route_throughput_per_day × cycle_ticks) / (TICKS_PER_DAY × production_output)`

This measures whether a route can keep up with a building's production rate. Value = 1.0 means the route perfectly matches production. < 1.0 means the route is the bottleneck. > 1.0 means the route has excess capacity.

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Route throughput per day | `route_throughput_per_day` | int | 0–∞ | From Formula 2. |
| Production cycle duration | `cycle_ticks` | int | 1–∞ | Building's production cycle time in ticks. Lumber Camp: 100. |
| Ticks per day | `TPD` | int | 1000 | Fixed constant. |
| Production output per cycle | `base_output` | int | 1–∞ | Building's base output per production cycle. Lumber Camp: 5. |

**Output Range:** [0, ∞). Value = 1.0 means perfect match.

**Example:** Lumber Camp produces 5 Wood/cycle (cycle_ticks = 100). Route at distance 10 delivers 16 items/day (Formula 2).
`route_efficiency = (16 × 100) / (1000 × 5) = 1600 / 5000 = 0.32`

The route delivers 32% of what the building produces. The player needs 4 carriers (or a shorter route) to achieve efficiency ≥ 1.0.

**UI interpretation:**
- Efficiency ≥ 1.0: green indicator — route can handle production
- 0.5 ≤ efficiency < 1.0: yellow — route is strained
- Efficiency < 0.5: red — route is severely undersized

### Formula 4: Number of Carriers Needed

The carriers_needed formula is defined as:

`carriers_needed = ceil((base_output × TICKS_PER_DAY) / (route_throughput_per_day × cycle_ticks))`

This is the inverse of Formula 3. Given a building's production rate and a route's throughput, how many carriers does the player need?

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Production output per cycle | `base_output` | int | 1–∞ | Building's base output per cycle. |
| Ticks per day | `TPD` | int | 1000 | Fixed constant. |
| Route throughput per day | `route_throughput_per_day` | int | 0–∞ | From Formula 2. |
| Production cycle duration | `cycle_ticks` | int | 1–∞ | Building's production cycle time. |

**Output Range:** [1, ∞) carriers. When `route_throughput_per_day = 0` (carrier never completes a trip), the formula returns `∞` — displayed to the player as "Infinite carriers needed" or "Route too long for any carrier." The player must reduce distance or increase carrier_capacity.

**Example:** Lumber Camp: `base_output = 5`, `cycle_ticks = 100`. Route at distance 10: `route_throughput_per_day = 16`.
`carriers_needed = ceil((5 × 1000) / (16 × 100)) = ceil(5000 / 1600) = ceil(3.125) = 4`

The player needs 4 carriers on this route to keep up with production.

## Edge Cases

**EC-L1: Carrier arrives at source, buffer is empty, building not yet producing**

The carrier enters WAITING_SOURCE state. It waits on the same tick for the building to produce — if the building's production cycle just completed this tick, the carrier picks up immediately. Otherwise, the carrier polls once per tick. A maximum wait of 300 ticks (default `carrier_waiting_timeout`) is enforced: if no item appears within 300 ticks, the carrier returns home and the route transitions to DEACTIVATED. This prevents a carrier from blocking an NPC indefinitely when a production cycle is misconfigured.

**EC-L2: Carrier arrives at destination, storage is full**

The carrier enters WAITING_DESTINATION state. It polls once per tick for free space. When space opens (a downstream carrier picks up items, or the player manually removes items), the carrier unloads immediately on the same tick. A maximum wait of 300 ticks (default `carrier_waiting_timeout`) is enforced: if the destination does not free space within 300 ticks, the carrier returns home with the item and the route transitions to DEACTIVATED.

**EC-L3: Route created between two buildings at the same position**

Route creation is blocked with the message "Source and destination cannot be the same building." This check occurs during route DRAFT → ACTIVE transition, before any NPC is assigned.

**EC-L4: Source or destination building is demolished while a carrier is en route**

The route is DEACTIVATED. If the carrier is holding an item, it returns home and deposits the item at the source building's storage. If the carrier is not holding an item, it returns home IDLE. The route record is preserved (not deleted) so the player can reassign it once a new building is placed.

**EC-L5: NPC is removed (house demolished) while assigned to a route**

The route is DEACTIVATED. Any item the NPC is carrying is returned home and deposited at the source building's storage. The player is shown a confirmation dialog to reassign a different NPC. If reassigned, the route activates on the same tick. If the player cancels or no NPC is available, the route record remains DEACTIVATED until manually deleted.

**EC-L6: Player deletes a route while the NPC is mid-trip**

The route is immediately PAUSED. If the carrier is holding an item, it completes the current leg to its destination, unloads there, then returns home IDLE. If the carrier is not holding an item, it returns home immediately and enters IDLE. The route record is preserved in DEACTIVATED state for potential reassignment.

**EC-L7: Production cycle completes but carrier is still waiting at source**

This cannot happen. The WAITING_SOURCE state only occurs when the buffer is empty (no item produced). A production cycle completing adds to the buffer, which the carrier detects on its next poll tick and picks up immediately. No special action required.

**EC-L8: Same building used as both source and destination via different slot types**

This is allowed and represents a self-loop (e.g., a building that has both input and output slots, where the output is routed back as input for another processing step). The carrier picks up from the output buffer and delivers to the input buffer. If the building produces 5 items per cycle and the carrier delivers them all back, the system operates as designed. The player is responsible for ensuring this creates a productive loop, not a deadlock.

**EC-L9: Carrier waiting timeout exceeded at both source and destination**

If a carrier hits the timeout at WAITING_SOURCE, it returns home (EC-L1). If it later arrives at a destination that is also full, it hits the timeout at WAITING_DESTINATION (EC-L2). The carrier returns home with the item, the route is DEACTIVATED, and the player sees both source and destination buildings with red indicators. The player must investigate: is the source not producing? Is the destination not draining?

## Dependencies

### Hard Dependencies

| System | Direction | Interface | Rationale |
|--------|-----------|-----------|-----------|
| NPC System | Reads | `npc_system.set_carrier_state(npc_id, state)`, `npc_system.get_npc_position(npc_id)` | NPCs ARE carriers. The Logistics System drives carrier state; the NPC System tracks position. |
| Building System | Reads/Writes | `building_system.get_free_input_slots()`, `building_system.get_free_output_slots()`, `building_system.has_output_buffer()`, `building_system.accept_input()` | Buildings define carrier slot capacity and receive/surrender resources via carrier actions. |
| Grid/Map System | Reads | `grid_map.get_manhattan_distance(pos_a, pos_b)` | Distance calculation for travel time. Manhattan distance, no pathfinding. |
| Tick System | Reads | `ticks_advanced(delta)`, `day_transition(days)` | All carrier timing is tick-based. Carriers only advance when time is RUNNING. |
| Inventory/Storage System | Reads/Writes | `storage.has_free_slots()`, `storage.get_current_count()`, `storage.deposit(resource, qty)`, `storage.withdraw(resource, qty)` | Carriers check capacity, pick up, and unload through the inventory system. |

### Soft Dependencies

| System | Direction | Interface | Rationale |
|--------|-----------|-----------|-----------|
| Transportation Management UI | Written by | Data queries: `get_active_routes()`, `get_route_status(npc_id)`, `get_route_efficiency(route_id)` | Player-facing UI displays route state, efficiency, and allows creation/editing. |
| Building System (UI-5 hover) | Written by | `building.get_carrier_status(building_id)` | Hover tooltips show carrier assignment state alongside building status. |

### Upstream Dependencies (already designed)

All hard dependencies have completed GDDs. No undesigned upstream dependencies.

### Downstream Dependents (not yet designed)

| System | Depends on Logistics | Rationale |
|--------|---------------------|-----------|
| Bevölkerungstier System | Indirectly | Higher-tier NPC consumption requires higher production throughput, which logistics efficiency enables. |
| Trading System | Yes | Trading uses carriers for caravan dispatch to the Übermap. |
| Übermap System | Yes | Overworld travel uses similar carrier mechanics. |
| Save/Load System | Yes | Route state must be serialized. |

---

## Tuning Knobs

| Knob | Default | Safe Range | Effect | What breaks at extremes |
|------|---------|------------|--------|------------------------|
| `ticks_per_tile` | 3.0 | 1.0–10.0 | Ticks spent per tile of carrier movement. Controls how much distance matters. | 1.0 = distance is negligible, players ignore placement. 10.0 = even short routes dominate production time, player feels stuck. |
| `carrier_capacity` | 1 | 1–∞ | Items carried per trip. | 1 = slow but simple. 10+ = carriers become conveyor belts, distance loses meaning. |
| `loading_ticks` | 1 | 1–∞ | Ticks to load items onto carrier. | 1 = instant, feels snappy. 10+ = loading bottleneck dominates travel time. |
| `unloading_ticks` | 1 | 1–∞ | Ticks to unload items from carrier. | Same as loading. |
| `max_carriers_per_slot` | 1 | 1–∞ | Maximum carriers per slot type per building. | 1 = simple, one carrier per route. 3+ = complex routing, harder to debug visually. |
| `TICKS_PER_DAY` | 1000 | 500–2000 | Ticks in one day. | Lower = faster game, more trips per "day". Higher = slower, carriers feel lazy. |
| `carrier_waiting_timeout` | 300 | 100–1000 | Ticks before a waiting carrier abandons the trip and returns home. Applies to both WAITING_SOURCE and WAITING_DESTINATION states. | 100 = carrier gives up too fast, player loses items on transient full states. 1000 = carrier is stuck for a full day, player can't diagnose why. |

## Visual/Audio Requirements

**Route visualization**: Carrier routes are communicated through building status indicators, not visible NPC sprites. A green indicator means the building has carriers assigned and is producing. A yellow indicator means a carrier is in transit (informational). A red pulsing indicator means the building is STALLED — no carrier assigned or destination full.

**Carrier route lines (always-visible)**: A subtle semi-transparent (30% opacity) line connecting source and destination buildings, visible for all active routes on the map. The line is colored by status: green (active), yellow (carrier in transit), red (destination full). Line thickness encodes carrier count on the route. Hovering over a route line highlights it at 60% opacity and shows the route detail tooltip (NPC name, distance, round-trip time, efficiency). Inactive/deactivated routes show a dim gray line at 10% opacity. This is a diagnostic tool that fulfills Pillar 2 — players must be able to scan the map and immediately see which buildings are connected and whether routes are healthy.

**Audio feedback**:
- **Carrier departure**: A faint "whoosh" (low volume, 0.3s) when an NPC carrier starts a trip. Only played once per carrier per departure (not every trip). Used for the player's awareness, not looped.
- **Carrier arrival**: A soft "clink" (0.2s) when the carrier deposits items at the destination. Volume proportional to resource value.
- **Building status change**: When a building goes from BLOCKED to OPERATING due to a carrier arriving, play the building's standard "activation" sound (same as production start). This is the primary feedback that the bottleneck was resolved.
- **No audio for return trips**: The NPC returning home is a passive state with no audible feedback. This keeps audio clutter low when many carriers are in transit.

**Art Bible alignment**: Visual style follows "Functional Clarity" (game-concept.md). Carrier routes use the same high-contrast palette as building status indicators — green (#4CAF50), yellow (#FFC107), red (#F44336). No additional assets needed beyond existing building status sprites.

**📌 Asset Spec Flag**: After the art bible is approved, run `/asset-spec system:logistics` to produce per-asset visual descriptions.

**Colorblind accessibility**: Route line colors use non-red/green-only distinction: active = solid line, transit = dashed line, full = dotted line. Colors are supplementary. This satisfies WCAG 2.1 Level AA (no color-only encoding).

---

## UI Requirements

**📌 UX Flag — Logistics System**: This system has UI requirements. The Transportation Management UI (`design/ux/transportation.md`) defines the player-facing route configuration interface. In Phase 4 (Pre-Production), stories referencing transport should cite `design/ux/transportation.md`, not the GDD directly.

**Building detail panel additions** (on top of existing building-detail spec):
- **Carrier status section**: Shows input carrier status (assigned NPC → source building, or "No input carrier") and output carrier status (assigned NPC → destination, or "No output carrier"). Includes distance and round-trip time for active routes.
- **Efficiency indicator**: Route efficiency score (Formula 3 UI interpretation: green ≥ 1.0, yellow 0.5–1.0, red < 0.5). Shown as a small badge next to the carrier status.

**Hover tooltip additions** (on top of existing UI-5):
- Carrier assignment: "Carrier: [NPC name] → [Destination] ([distance] tiles, [round_trip] ticks)"
- If blocked: "No output carrier" or "No input carrier" with resource name

**Transportation Management UI** (separate spec — `design/ux/transportation.md`):
- Route list view showing all active routes
- Route detail view for creating/editing routes
- Map-select interaction for source/destination building selection

---

| ID | Acceptance Criterion | Verification |
|----|---------------------|--------------|
| AC-1 | A production building with output in its buffer and an assigned carrier on its output slot transitions to OPERATING (green indicator) within 1 tick of the carrier completing its first delivery | Automated: create route with known output → simulate carrier delivery → assert building.state == OPERATING within 1 tick |
| AC-2 | A carrier assigned to a Storage → Production route delivers the first item to the destination building within `dist × tpt + lt + ut` ticks of route activation | Automated: create route → record time_of_first_delivery → assert `time_of_first_delivery - activation_time <= dist × tpt + lt + ut` |
| AC-3 | A production building with no carrier on its output slot that completes a production cycle holds the output in its buffer and transitions to STALLED when the buffer reaches capacity | Automated: produce output without carrier → assert `building.buffer_count == production_output` and `building.state == STALLED` after buffer fills |
| AC-4 | A carrier in WAITING_DESTINATION state transitions to AT_DESTINATION and unloads within 1 tick of the destination gaining free space | Automated: fill destination storage → send carrier → assert state == WAITING_DESTINATION → remove items from storage → assert unload occurred within 1 tick |
| AC-5 | A carrier in WAITING_SOURCE state picks up an item within 1 tick of the source building's buffer receiving output | Automated: empty source buffer → send carrier → assert state == WAITING_SOURCE → produce item at source → assert pickup within 1 tick |
| AC-6 | When the player deletes an active route, the carrier's state transitions to IDLE within 1 tick and any item the carrier was holding is deposited at the source building's storage | Automated: create route → assign carrier → delete route → assert `carrier.state == IDLE` and `source_storage.get_count() includes deposited item` within 1 tick |
| AC-7 | When a route's source building is demolished, the route transitions to DEACTIVATED within 1 tick and the carrier (regardless of current state) begins returning home | Automated: demolish source building → assert `route.active == false` and `route.lifecyle_state == DEACTIVATED` within 1 tick |
| AC-8 | Attempting to create a second route on a building whose output slot is already filled results in the action being rejected and no route being created | Automated: create route 1 on building → attempt route 2 on same output slot → assert `get_active_routes().count() == 1` |
| AC-9 | Formula 1: For a route with distance 10 tiles, home at source, `ticks_per_tile = 3.0`, `loading_ticks = 1`, `unloading_ticks = 1`, `carrier_round_trip_ticks` equals 62 | Automated: call formula with inputs → assert result == 62 |
| AC-10 | Formula 2: With `carrier_round_trip_ticks = 62` and `carrier_capacity = 1`, `route_throughput_per_day` equals 16 | Automated: call formula with inputs → assert result == 16 |
| AC-11 | Formula 3: With `route_throughput_per_day = 16`, `cycle_ticks = 100`, `TICKS_PER_DAY = 1000`, `base_output = 5`, `route_efficiency` equals 0.32 | Automated: call formula with inputs → assert result ≈ 0.32 (within 0.01 tolerance) |
| AC-12 | Formula 4: With `base_output = 5`, `cycle_ticks = 100`, `route_throughput_per_day = 16`, `carriers_needed` equals 4 | Automated: call formula with inputs → assert result == 4 |
| AC-13 | A carrier saved during TRAVEL_TO_DESTINATION with `remaining_ticks = 30` resumes travel from its saved position with `remaining_ticks = 30` after game reload | Automated: save game mid-travel → load → assert `carrier.remaining_ticks == 30` and `carrier.state == TRAVEL_TO_DESTINATION` |
| AC-14 | Creating a route where source and destination are the same building is blocked and the UI displays "Source and destination cannot be the same building." | Manual: select same building as source and destination → click confirm → assert error message displayed and no route created |
| AC-15 | When `carrier_waiting_timeout = 300` and a carrier is in WAITING_DESTINATION for 300 consecutive ticks, the carrier transitions to RETURN_HOME and the route to DEACTIVATED | Automated: fill destination → send carrier → assert state == WAITING_DESTINATION → advance 300 ticks → assert `carrier.state == RETURN_HOME` and `route.active == false` |
| AC-16 | Route lines are visible on the map for all active routes, colored by status (green/yellow/red), and hovering over a line displays the route detail tooltip | Manual: create route → verify line visible on map → hover → verify tooltip shows NPC name, distance, round-trip time |

---

## Open Questions

1. **Tool delivery**: Should tool delivery to extraction buildings be handled through the carrier system (Storage → Lumber Camp route) or stay as internal consumption? Currently deferred to internal consumption for MVP scope. Making it a carrier route adds a new route type that players must manage for the simplest production chain.

2. **Roads as a future feature**: The game concept mentions "roads reduce transport time." Should the Logistics System reserve an interface for road-based travel time reduction? Or defer entirely until the feature is designed?

3. **NPC effectiveness (Perk System)**: At Core Experience, Perk System will modify NPC effectiveness. Should the Logistics System have an interface like `npc.get_effectiveness(npc_id) -> float` that modifies `ticks_per_tile` per NPC? Or is this a Perk System concern?

4. **Route priority/urgency**: Should carriers have a concept of priority? If an NPC can serve multiple routes, should they prioritize high-efficiency routes (critical bottlenecks) over low-efficiency ones? Or is this purely a manual player decision?
