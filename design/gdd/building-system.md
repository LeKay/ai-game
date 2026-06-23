# Building System

> **Status**: Implemented — synced against `src/gameplay/building_registry.gd` (2026-06-16)
> **Author**: [user + agents]
> **Last Updated**: 2026-06-13
> **Implements Pillar**: [from context]
> **Sync note**: This document was reverse-synced to the implementation after the
> balancing pass of 2026-06-11/12 (`tools/balance/balance-findings.md`). Time values
> use the pacing anchor **1 tick ≈ 1 in-game minute, 1440 ticks = 1 day**.

## Overview

The Building System is the player's primary interface with the game's spatial logic — where the village takes physical form on the map. Every building is a deliberate, earned investment: resources hauled across the map by the player's own hands, energy spent, time counted in ticks. A lumber camp isn't just a structure; it's the culmination of a production chain decision — "I chose to put the lumber camp here, near the forest and close to storage, because I've solved wood but need to free up my energy for stone." The Building System owns building placement validation, construction cost consumption, build-time progression, and building lifecycle (place, operate, demolish). It is a state machine per building instance — idle, under construction, producing, blocked, paused — and a spatial operation that respects the Grid/Map System's layers and the Inventory/Storage System's resource constraints. Without it, the player has a map but nothing to put on it.

> **Design level note:** The Building System operates at the behavior/interaction layer. Implementation decisions (PackedScene architecture, TileMapLayer rendering, YSort depth ordering) are established in the Grid/Map System GDD and enforced by the Engine Architecture ADR. This GDD describes what the system does, not how Godot nodes are wired to do it.

## Player Fantasy

**The Spatial Chessboard.**

Every building is a commitment that ripples outward. Place the storage near the forest, and every resource you gather costs less Energy. Place the lumber camp across the map, and your NPC will spend half its production cycle just walking. This is not a checklist of buildings — it is a map becoming an engine, and every placement is a move in a spatial puzzle where the pieces are timber, stone, and time.

The building system rewards foresight. A smart placement creates positive feedback: close to resources, close to storage, close to housing means minimal transport and maximum output. A poor placement creates drag that compounds — the building produces, but slowly, because its NPC wastes time on the road. The map tells you if you got it right: idle tiles near the building show resource gaps, and the production rate drops to yellow.

This fantasy anchors to the moment you see your first automated building complete its production cycle and notice — in the numbers — that your placement choice made a measurable difference. That moment is quiet. No fanfare. Just a faint click in your brain: "I see it. The distance between the camp and the storage is the bottleneck." The satisfaction comes from solving a puzzle you designed yourself.

The building system is where the player stops playing the game and starts understanding it. Before placement, they react to the map. After placement, they author it. Every tile they choose becomes a sentence in the story of their village — and by the time the map is full, the village tells the story of their thinking: "Here I was solving wood, here I was planning for population growth, here I optimized for transport efficiency."

**What it serves:** Pillar 1 (Earned Automation — every building is a deliberate investment, not an abstract toggle), Pillar 2 (Information Transparency — ghost overlay shows placement validity and cost before committing, production rates are visible), Pillar 3 (Optimization Over Expansion — compact, efficient layouts beat sprawling ones, and the building system makes spatial tradeoffs tangible through transport costs and resource proximity).

## Detailed Design

### Core Rules

**1. Building Lifecycle**

Every building follows a four-stage lifecycle:

```
PLACE → CONSTRUCT → OPERATE → (optional) DEMOLISH
```

Each stage has strict preconditions and transitions. A building cannot skip stages or reverse stages (except DEMOLISH, which exits the lifecycle entirely).

**2. Placement**

The player places a building by selecting it from the Building Menu UI and confirming on a tile. The Building System is the **sole system responsible for building placement** — this responsibility was removed from the Player Character System (PC System GDD, revision B8).

Placement procedure:
1. Building System queries the Grid System's `validate_placement(x, y, building_id)`.
2. If result is `SUCCESS`, the Building System deducts build costs from storage, deducts placement energy from the player's energy pool (per Formula 7), marks the building as CONSTRUCTING, and spawns the visual PackedScene at the tile center.
3. If result is `BLOCKED_BY_*`, the placement preview shows a red ghost with the blocking reason. No resources are deducted. Placement does NOT proceed.

**Placement validation chain** (executed in order, short-circuit on first failure):

```
func validate_placement(x, y, building_id) -> PlacementResult:
    if out_of_bounds(x, y):              return BLOCKED_BY_BOUNDS
    if is_impassable(x, y):              return BLOCKED_BY_IMPASSABLE
    if has_building(x, y):               return BLOCKED_BY_BUILDING
    if resource_tile_exists(x, y):
        if not resource_tile_is_clearable(x, y):
            return BLOCKED_BY_RESOURCE_TILE
    return SUCCESS
```

The Grid System GDD is the authoritative source for these rules. The Building System does NOT duplicate or reimplement validation logic — it delegates to the Grid System and displays the result.

**Resource tile clearing:** When placement succeeds on a tile with a clearable resource (TREE, BERRY, GRASS), the Grid System removes the resource from ResourceLayer upon `place_building()`. Non-clearable resources (STONE, IRON) block placement entirely.

**Pre-placement resource check:** Before confirming placement, the Building System queries the Inventory System to verify build costs are available in the designated storage container. If insufficient, the placement is blocked and the preview shows a red X with a tooltip listing missing resources. Resources are deducted atomically with the placement — either both succeed or both fail.

**4. Construction**

After placement succeeds, the building enters the CONSTRUCTING state. Construction is a tick-based process:

- **Resource consumption:** Build costs are deducted from the player's storage at the moment construction starts. If insufficient resources are available, placement is blocked (see Rule 2).
- **Tick accumulation:** Construction progress is measured in ticks. Construction advances only when time is RUNNING (not PAUSED). The player is **NOT** occupied during construction — they can perform other actions while buildings construct.
- **Completion:** When accumulated ticks reach the building's build time threshold, the building enters the OPERATING state and becomes functional.

**Construction time table (current code values, `BUILD_COST` / `BUILD_TIME`):**

| Building | Build Cost | Build Time | ≈ Days (1440 t/day) |
|----------|-----------|------------|----------------------|
| Collection Point (starter depot) | Free (0 resources) | 0 ticks (instant — no construct phase) | — |
| Road | Free (0 resources) | 0 ticks (instant) | — |
| Storage Building | 8 Wood + 2 Stone | 960 ticks | ~0.7 |
| Residential House | 10 Wood + 3 Stone | 1200 ticks | ~0.8 |
| Gathering Hut | 5 Wood + 2 Stone | 640 ticks | ~0.4 |
| Lumber Camp | 15 Wood + 3 Stone | 1600 ticks | ~1.1 |
| Stone Mason | 10 Wood + 5 Stone | 1600 ticks | ~1.1 |
| Tool Workshop | 10 Wood + 5 Stone | 3000 ticks | ~2.1 |
| Weaver | 8 Wood + 3 Stone | 1200 ticks | ~0.8 |
| Tailor | 10 Wood + 5 Stone | 1600 ticks | ~1.1 |
| Sawmill | 8 Wood + 3 Stone | 1200 ticks | ~0.8 |
| Farm | 8 Wood + 2 Stone | 480 ticks | ~0.3 |
| Mill | 10 Wood + 5 Stone | 800 ticks | ~0.6 |
| Bakery | 10 Wood + 5 Stone | 900 ticks | ~0.6 |
| Clay Pit | 8 Wood + 3 Stone | 800 ticks | ~0.6 |
| Pottery Kiln | 5 Wood + 8 Stone + 5 Clay | 900 ticks | ~0.6 |
| Tannery | 8 Wood + 3 Stone | 700 ticks | ~0.5 |
| Bowyer's Workshop | 8 Wood + 3 Fiber + 2 Stone | 700 ticks | ~0.5 |
| Rope Maker | 8 Wood + 3 Fiber | 700 ticks | ~0.5 |

> Build times were rescaled ×8–12 in the 2026-06-11 balancing pass so construction
> takes hours-to-days of in-game time and the day becomes a real planning unit
> (source: `tools/balance/balance-findings.md`).

**Adjacency requirements (placement gate `BLOCKED_BY_ADJACENCY`):** Some buildings
require at least one neighboring tile (cardinal or diagonal) of a specific terrain type:

| Building | Required adjacent terrain |
|----------|---------------------------|
| Lumber Camp | TREE |
| Stone Mason | STONE |
| Gathering Hut | BERRY or GRASS |
| Farm | WHEAT |
| Clay Pit | CLAY |

The count of satisfying neighbor tiles also drives the building's adjacency efficiency
(Formula F6, see Efficiency System / ADR-0012) and — for the Gathering Hut — which
resources it harvests per cycle (`TERRAIN_HARVEST_OUTPUT`: BERRY → 4 Berries,
GRASS → 2 Fiber; one output entry per distinct adjacent terrain type).

**5. Operation**

A building in OPERATING state is functional. Its behavior depends on building type:

- **Storage types** (Storage Area, Storage Building): Passive — they provide capacity and do not produce. They have no operation cycle.
- **Residential House**: Spawns 1 NPC immediately upon entering OPERATING. After 1000 further ticks (`NPC_SPAWN_INTERVAL`, ≈ 0.7 in-game days) in OPERATING state, spawns a 2nd NPC. Maximum capacity: 2 NPCs (`MAX_HOUSE_NPCS`).
- **Production buildings** (Lumber Camp): Enter a production cycle. At the start of each cycle, the building checks whether required inputs are available at the building's input buffer (delivered by an assigned input carrier). If all inputs are available, the cycle begins. When the production cycle completes, the building holds the output in its output buffer. An assigned output carrier collects the output and transports it to the assigned storage container. Input wares must be transported to the building by an input carrier; output wares must be transported away by an output carrier. Transportation is configured via the Transportation UI (see `design/ux/transportation.md`). A building with no carrier assigned for inputs or outputs enters BLOCKED state — production cannot start without inputs, and completed output cannot leave without an output carrier.

**Production table (current code values, `PRODUCTION_TABLE`):**

| Building | Input per cycle | Output per cycle | Base Cycle | Output Cap | Input Cap | NPC Required |
|----------|-----------------|------------------|-----------|------------|-----------|--------------|
| Gathering Hut | — | terrain-driven (4 Berry and/or 2 Fiber) | 250 ticks | 20 | — | Yes (1) |
| Lumber Camp | Axe, 1/30 charge | 5 Wood | 250 ticks | 20 | 5 | Yes (1) |
| Stone Mason | Pickaxe, 1/30 charge | 5 Stone | 250 ticks | 20 | 5 | Yes (1) |
| Tool Workshop (Axe) | 3 Wood + 2 Stone | 1 Axe | 375 ticks | 10 | 10 | Yes (1) |
| Tool Workshop (Pickaxe) | 3 Stone + 1 Wood | 1 Pickaxe | 375 ticks | 10 | 10 | Yes (1) |
| Tool Workshop (Spindle) | 2 Wood + 2 Fiber | 1 Spindle | 375 ticks | 10 | 10 | Yes (1) |
| Tool Workshop (Knife) | 2 Wood + 1 Stone | 1 Knife | 375 ticks | 10 | 10 | Yes (1) |
| Weaver (main) | 3 Fiber + 1 Spindle | 2 Cloth | 250 ticks | 20 | 10 | Yes (1) |
| Weaver (fallback) | 5 Fiber | 1 Cloth | 750 ticks | 20 | 10 | Yes (1) |
| Tailor (main) | 2 Cloth + 1 Spindle | 2 Clothing | 300 ticks | 20 | 10 | Yes (1) |
| Tailor (fallback) | 2 Cloth | 1 Clothing | 900 ticks | 20 | 10 | Yes (1) |
| Tailor (leather) | 2 Leather + 1 Spindle | 2 Clothing | 300 ticks | 20 | 10 | Yes (1) |
| Tannery (main) | 2 Hide + 1 Knife | 3 Leather | 250 ticks | 20 | 10 | Yes (1) |
| Tannery (fallback) | 2 Hide | 1 Leather | 750 ticks | 20 | 10 | Yes (1) |
| Hunting Lodge (with bow) | 1 Hunting Bow | 3 Meat + 2 Hide | 300 ticks | 20 | 5 | Yes (1) |
| Hunting Lodge (bare hands) | — | 2 Meat + 1 Hide | 450 ticks | 20 | 0 | Yes (1) |
| Bowyer's Workshop | 2 Wood + 3 Fiber | 1 Hunting Bow | 375 ticks | 10 | 10 | Yes (1) |
| Sawmill | 2 Wood + 1 Axe | 3 Plank | 250 ticks | 20 | 10 | Yes (1) |
| Farm | — | 5 Wheat (terrain-driven, WHEAT adjacency) | 250 ticks | 20 | — | Yes (1) |
| Mill | 2 Wheat | 3 Flour | 250 ticks | 20 | 10 | Yes (1) |
| Bakery | 2 Flour | 4 Bread | 300 ticks | 20 | 10 | Yes (1) |
| Clay Pit | 1 Pickaxe | 5 Clay | 250 ticks | 20 | 5 | Yes (1) |
| Pottery Kiln (main) | 2 Clay + 1 Pickaxe | 3 Pottery | 300 ticks | 20 | 10 | Yes (1) |
| Pottery Kiln (fallback) | 2 Clay | 1 Pottery | 900 ticks | 20 | 10 | Yes (1) |
| Rope Maker (main) | 3 Fiber + 1 Spindle | 2 Rope | 250 ticks | 20 | 10 | Yes (1) |
| Rope Maker (fallback) | 4 Fiber | 1 Rope | 750 ticks | 20 | 10 | Yes (1) |
| Weaver (rope nets) | 2 Rope | 2 Fishing Net | 250 ticks | 10 | 10 | Yes (1) |
| Bowyer (rope bow) | 2 Wood + 1 Rope | 2 Hunting Bow | 300 ticks | 10 | 10 | Yes (1) |

> **Tool as capital good (2026-06-11):** A delivered tool adds 1.0 charge to the
> building's input buffer; each cycle consumes only **1/30** charge, so one tool
> powers **30 production cycles** (≈ 5 in-game days at base speed). This replaces
> the old per-cycle tool consumption that made the tool chain a treadmill
> (rationale: `tools/balance/balance-findings.md`, finding B1/E1).
>
> **Effective cycle time:** The base cycle is divided by the building's efficiency
> (Formula F3, ADR-0012) — see Formula 5 below. At ~5–6 cycles/day for the basic
> producers, feeding workers and good placement directly buy throughput.

**6. NPC Assignment**

Production buildings require an NPC to be assigned to operate. The building cannot start a production cycle without an NPC. NPC assignment is performed via the building's interaction UI (click the building → "Assign NPC" → select available NPC).

NPC assignment is bidirectional: both the Building System and the NPC System track the assignment. The canonical record is in the NPC System (NPCs are the owned resource); the Building System stores the assignment as a reference. The Building System queries `get_available_npcs()` to show assignable NPCs and calls `assign_npc(npc_id, building_id)` to make the assignment.

**7. Production Buildings: Blocked and Output-Full Idle**

Production buildings have two distinct failure modes (as implemented in
`BuildingRegistry._try_start_production_cycle`):

- **BLOCKED** (explicit state): The building cannot START producing because it lacks a required condition — no NPC assigned (`No NPC assigned`), inputs missing AND no input carrier assigned (`No carrier assigned (inputs)`), inputs missing despite a carrier (`Missing required input`), or — Gathering Hut only — no harvestable terrain adjacent. Recovery is automatic: a BLOCKED building retries the cycle start on every tick (`_try_recover_blocked`) and emits `building_unblocked` when it resumes.
- **Output-full idle** (not a separate state): When the output buffer holds ≥ `output_capacity` items, the building simply does not start a new cycle. It stays in OPERATING, the completed output remains in `buffered_output`, and production resumes automatically as soon as a carrier (or manual drag) removes items. Output is **never discarded**.

> **Design history:** Earlier drafts specified a dedicated STALLED state with a red
> pulsing indicator. The implementation merged this into "OPERATING, but no cycle
> running because output is full" — the player-visible signal is the idle status
> indicator plus the full output buffer in the building detail panel.

Visual distinction: BLOCKED = yellow indicator, tooltip shows what's missing ("No NPC assigned", "No carrier assigned (inputs)", "Missing required input"). Output-full = building idles with a full output bar.

**Mid-cycle block rule:** If inputs become unavailable mid-cycle (e.g., storage demolished via EC-H5, or resource stack fully consumed by a second building), the current production cycle completes — the building already committed to work and has already consumed its inputs. The building enters BLOCKED on the *next* cycle start when it finds no inputs and cannot begin a new cycle. This prevents the "my building just stopped halfway" frustration and preserves player agency.

**8. Demolition**

The player may demolish a building via the building's interaction UI. Demolition procedure:

1. The building transitions to DEMOLISHED from any state.
2. The building's PackedScene is destroyed (`queue_free()`).
3. The building is removed from the Grid System's BuildingLayer.
4. **No resource refund.** All build costs are permanently lost.
5. Any pending production cycles are cancelled.
6. **Buffered items are dropped, not destroyed:** everything in the input buffer
   (rounded up per resource), the output buffer, and — for storage buildings — the
   attached inventory container is emitted via `building_items_dropped(tile, items)`
   so the scene layer spawns world pickups on the tile.
7. Any NPC assigned to the building is released (`release_npc`) and returns home.
8. Resource tiles beneath the building remain cleared (they are not restored).

**Rationale:** No refund reinforces "earned automation" — buildings are real investments. The player decides to demolish knowing the cost is sunk.

**9. Multiple Buildings of the Same Type**

The player may place multiple buildings of the same type (e.g., two Residential Houses, two Lumber Camps). Each building instance tracks its own state independently. Buildings do NOT share production queues or NPC pools — each Lumber Camp needs its own NPC and tool input, its own output, and its own production timer.

**10. Building Representation**

Each building is a `PackedScene` instantiated at the tile center position (`tile_coord * TILE_SIZE + TILE_SIZE / 2`) on the `MapRoot` node, which is a child of a `YSort` node for proper depth sorting. Buildings are NOT represented as TileMapLayer tiles. Each building instance has:

- A visual sprite (the building's appearance)
- A status indicator (idle/producing/blocked/stalled — shown as colored overlay)
- A reference to its tile coordinates and building type

**Data ownership:** The Building Registry (a centralized system) is the sole source of truth for all building state data. Building scene instances are pure visual targets — they do NOT own independent game state. The registry spawns the visual scene and syncs its visual state (sprite, overlay) on every state transition.

**Authority boundary with NPC System:** The Building Registry is authoritative for building state (lifecycle, construction progress, production cycle, assigned storage). The NPC System is authoritative for NPC state (assignment, availability, hunger, position). On any discrepancy (e.g., Building Registry read returns different assignment than NPC System), NPC System is authoritative. The Building System must always validate assignment state against the NPC System before executing NPC-dependent operations (production cycle start, release on demolition).

### States and Transitions

Each building instance has its own state machine. The Building Registry tracks the state of every building on the map.

**Building States:**

| State | Description | Visual | Entering From | Exiting To |
|-------|-------------|--------|---------------|------------|
| **CONSTRUCTING** | Building placed, resources consumed, build timer running | Scaffolding overlay, hammer animation swings | Player confirms placement on valid tile (Grid validates) | OPERATING (timer complete) |
| **OPERATING** | Building functional and ready to produce. Sub-phases: **IDLE** (waiting for inputs or output space) and **PRODUCE** (`cycle_running == true`). Output-buffer-full keeps the building here without starting a new cycle. | Normal sprite, green status indicator | CONSTRUCTING (timer complete) | OPERATING (cycle complete), BLOCKED (missing input, no NPC, or no carrier assigned), DEMOLISHED (player action) |
| **BLOCKED** | Building ready but missing a required condition (input not delivered, NPC not assigned, no input carrier, no harvestable adjacency) | Yellow indicator overlay, tooltip shows what's missing | OPERATING (cycle start failed) | OPERATING (condition resolved, auto-retry each tick), DEMOLISHED (player action) |
| **DEMOLISHED** | Building removed from map | N/A (scene destroyed) | Any state | Terminal — no transitions out |

**Placement validation (PLACE_VALIDATING) is a transient UI phase, not a building state.** The building does not exist as an entity until placement succeeds. PLACE_VALIDATING is initiated by player mouse input and transitions directly to CONSTRUCTING (on success) or stays in PLACE_VALIDATING (re-hovering).

**State Transition Table:**

| From | To | Trigger | Conditions |
|------|-----|---------|------------|
| *(creation)* | CONSTRUCTING | Player confirms placement | Grid `validate_placement()` returns SUCCESS, build costs deducted from storage |
| CONSTRUCTING | OPERATING | Build timer reaches threshold | Accumulated ticks >= build_time |
| CONSTRUCTING | CONSTRUCTING | Tick System `on_ticks_advanced()` | Pause — time does not advance, no progress, no new events. Pausing simply means ticks stop accumulating. |
| OPERATING | BLOCKED | Cycle start fails | `_try_start_production_cycle` returns BLOCKED_NO_NPC, BLOCKED_NO_CARRIER, or BLOCKED_NO_INPUT |
| BLOCKED | OPERATING | Condition resolved | Building re-checks every tick (`_try_recover_blocked`). Input delivered by carrier, NPC assigned, carrier assigned. Auto-transition — no player action required. |
| OPERATING | OPERATING (idle) | Output buffer full | Cycle start returns OUTPUT_FULL; no state change, no new cycle until output is removed. |
| Any | DEMOLISHED | Player initiates demolition via building UI | Confirmed by player (no undo). Resources not refunded. Buffered input/output items are dropped onto the tile (`building_items_dropped`). |

**Production buildings only:** The BLOCKED state and the output-full idle behavior apply to production buildings. Collection Point and Road skip construction (instant OPERATING). Residential House transitions CONSTRUCTING → OPERATING → triggers NPC spawn.

**Output-full idle is indefinite:** There is no discard timer. The building holds buffered output until a carrier (or the player) collects it, or until demolition drops it onto the tile. Output is never silently lost.

### Interactions with Other Systems

**Grid/Map System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Building → Grid** | `validate_placement(x, y, building_id) -> PlacementResult` | Pre-placement validation (bounds, impassable, existing building, resource tile clearability) |
| **Building → Grid** | `place_building(x, y, building_id) -> PlacementResult` | Place building, update BuildingLayer, clear resource tile |
| **Building → Grid** | `remove_building(x, y) -> bool` | Demolish building, update BuildingLayer |
| **Grid → Building** | `get_tile_view(x, y) -> TileView` | Build preview tooltip (shown when hovering with ghost) |

**Data contract:** The Grid System is the **sole owner** of the BuildingLayer. The Building System is the **sole writer** to the BuildingLayer. No other system may modify the BuildingLayer.

**Inventory/Storage System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Building → Inventory** | `try_consume(container_id, resource_id, quantity) -> {success, remaining_deficit}` | Deduct build costs at construction start; deduct whole-item production inputs at cycle start (inputs delivered to building by carrier, consumed from input buffer) |
| **Building → Inventory** | `try_consume_charge(container_id, resource_id, charge_cost) -> {success, remaining_deficit}` | Deduct fractional charge from a slot at cycle start (for inputs with `charge_cost`) |
| **Building → Inventory** | `get_resource(container_id, resource_id) -> {quantity_available}` | Build menu preview: "Have X, need Y" |
| **Inventory → Building** | `on_container_removed(container_id)` | Notify dependent buildings when their assigned storage is demolished (see EC-H3) |

**Note on output deposit:** Production output is no longer deposited directly by the Building System. When a production cycle completes, the Building System emits `production_output_ready(building_id, output, cycle_ticks)` and holds the output in an internal buffer (`cycle_ticks` is the nominal cycle length, used by the Experience System for time-based work XP). The Transportation System's output carrier NPC picks up the buffered output and calls `InventorySystem.try_deposit()` at the storage container. This separation keeps the Building System decoupled from storage transport logistics.

**Transportation System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Building → Transport** | `get_carrier_status(building_id) -> {input_carrier, output_carrier}` | Query which carriers are assigned to this building (for UI display) |
| **Transport → Building** | `on_carrier_assigned(building_id, carrier_id, direction)` | Notify building when a carrier route is configured (direction: INPUT or OUTPUT) |
| **Transport → Building** | `on_carrier_unassigned(building_id, carrier_id, direction)` | Notify building when a carrier route is removed — building enters BLOCKED if carrier was required |
| **Transport → Building** | `collect_output(building_id) -> {success, output_items}` | Carrier NPC collects buffered output from building |
| **Transport → Building** | `deliver_input(building_id, resource_id, quantity) -> {success}` | Carrier NPC delivers input wares to building's input buffer |

**Data contract:** The Transportation System is the sole owner of carrier routing configuration. The Building System does NOT know the details of carrier schedules — it only knows whether a carrier is assigned (from signal) and whether its buffers are stocked (input) or need pickup (output). Full carrier configuration is done via the Transportation UI (`design/ux/transportation.md`).

**Data contract:** Buildings never access tiles or player inventory directly. All resource operations flow through the Inventory/Storage System's API. First-fit stacking (Inventory System GDD, Formula 3) governs all deposits and withdrawals.

**Recipe Database System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Building → Recipe DB** | `get_recipe(building_id) -> RecipeDef` | Look up production recipe (inputs, outputs, tick_cost) for a building type |

**Data contract:** The Building System owns the full production loop — lifecycle (place, construct, activate, demolish) AND recipe execution (input consumption, cycle timing, output deposit). The Recipe Database is a pure data source; the Building System reads from it and executes the cycle internally. There is no separate Production System.

**Tick System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Tick → Building** | `on_ticks_advanced(delta_ticks)` | Decrement build timers and production cycle timers |
| **Tick → Building** | `on_day_transition(days_elapsed)` | Residential House NPC spawn timer (1 day after construction complete) |

**Data contract:** Building timers are driven exclusively by Tick System events. The Building Registry subscribes to `on_ticks_advanced` and iterates all buildings in a single loop (no per-scene `_process()` for tick logic).

**NPC System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Building → NPC** | `assign_npc(npc_id, building_id)` | Assign an NPC to this building |
| **Building → NPC** | `release_npc(npc_id)` | Release NPC when building is demolished or BLOCKED |
| **NPC → Building** | `get_available_npcs(building_id) -> Array[NPC]` | Building UI shows assignable NPCs |
| **NPC → Building** | `get_assigned_building(npc_id) -> building_id?` | Validate assignment (prevent double-assignment) |

**Data contract:** Assignment is bidirectional — both systems track it. Canonical record: NPC System (NPCs are the owned resource). Building System stores reference.

**Player Character System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **PC → Building** | `initiate_build(building_id, x, y)` | Player selects building type + clicks tile → triggers placement flow |
| **Building → PC** | `on_construction_complete(building_id, x, y)` | Notify player when construction finishes |

**Note:** Building placement was moved from PC System to the Building System (PC System GDD, revision B8). The PC System initiates the placement flow but does NOT execute the placement itself. The Building System owns all placement, construction, and operation logic.

**Resource System:**

| Direction | Interface | Purpose |
|-----------|-----------|---------|
| **Building → Resource** | `get_resource(resource_id) -> ResourceDef` | Read resource attributes (stack_limit, max_charge, category) for build cost validation and production definitions |

**Data contract:** The Building System only **reads** from the Resource System. It does not modify resource definitions.

## Formulas

All formulas below use the Tick System as their time source (1 tick = 1 game tick; see Tick System GDD for tick rate and pause behavior). All integer outputs are truncated toward zero (floor for positive values).

---

### Formula 1: Build Cost Validation

Determines whether the player's storage containers contain sufficient resources to begin construction. This is a boolean check — no calculation, just comparison against each building type's cost table.

The `build_cost_valid` formula is defined as:

`build_cost_valid = (∀ i : storage_qty(resource_i) ≥ build_qty(resource_i))`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Storage resource quantity | `storage_qty(r)` | int | 0–∞ | Current count of resource `r` across all storage containers. Read via `Inventory.get_resource(container_id, resource_id)`. |
| Build cost quantity | `build_qty(r)` | int | 1–∞ | Number of units of resource `r` required to build this building type. Looked up from the build cost table. |
| Number of distinct resources | `n` | int | 0–3 | Number of distinct resource types in the build cost. Storage Area has n=0. Storage Building has n=2. Residential House has n=2. Lumber Camp has n=2. |
| Universal quantifier | `∀` | bool logic | — | "For all" — every resource in the cost table must satisfy the inequality. |

**Output Range:** `true` or `false` (boolean)

**Degeneracy checks:**
- `n = 0` (Storage Area): All-zero cost. Formula returns `true` trivially — the universal quantifier over an empty set is vacuously true. Construction is instant.
- `storage_qty(r) = build_qty(r)`: Exactly sufficient. Returns `true`. The full amount is consumed; storage_qty becomes 0.
- `storage_qty(r) < build_qty(r)` for any `r`: Returns `false`. Placement is blocked. The UI must show which specific resource is insufficient.

**Example:** Player has 7 Wood in storage. Building a Storage Building which costs 8 Wood + 2 Stone.
- `storage_qty(Wood) = 7`, `build_qty(Wood) = 8` → `7 ≥ 8` is **false**
- Short-circuit: the universal quantifier fails at the first resource.
- Result: `build_cost_valid = false`. Placement blocked. UI tooltip: "Need 1 more Wood."

---

### Formula 2: Construction Time Lookup

Construction time is not calculated from variables — it is a direct lookup from the building type's cost table. The formula formalizes the lookup and enforces a sanity bound.

The `construction_time` formula is defined as:

`construction_time(building_type) = lookup(build_time_table, building_type)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Building type enum | `building_type` | enum | {STORAGE_AREA, STORAGE_BUILDING, RESIDENTIAL_HOUSE, LUMBER_CAMP, ...} | The building being constructed. Matches the row key in the build time table. |
| Construction time | `construction_time(bt)` | int | 0–∞ | Number of ticks required for this building to complete construction. 0 means instant (no construction phase). |
| Build time table | `build_time_table` | map | — | Static lookup table. See table below. |

**Build time table (Vertical Slice):**
| Building Type | `building_type` | Construction Time (`ticks`) |
|---------------|-----------------|----------------------------|
| Storage Area | `STORAGE_AREA` | 0 (instant) |
| Storage Building | `STORAGE_BUILDING` | 120 |
| Residential House | `RESIDENTIAL_HOUSE` | 150 |
| Lumber Camp | `LUMBER_CAMP` | 200 |

**Output Range:** `0` to `∞` (int), though practical maximum in Vertical Slice is 200 ticks.

**Degeneracy checks:**
- `construction_time = 0`: Building has no construction phase. Transitions directly from PLACE_VALIDATING → OPERATING upon successful placement. Resource costs are still deducted (if any; Storage Area costs 0).
- Unknown `building_type`: Returns `null`. This is a data error — the Building Registry should never attempt construction with an unknown type. The engine should crash or log a hard error.

**Example:** Player places a Lumber Camp. `construction_time(LUMBER_CAMP) = 200`. The building enters CONSTRUCTING with 200 ticks of progress required. Ticks accumulate via `Tick.on_ticks_advanced()` until 200 is reached, then the building transitions to OPERATING.

---

### Formula 3: Carrier Travel Time

Calculates how many ticks a carrier NPC requires to travel between a production building and its assigned storage container. This replaces the old distance-modifier output penalty: distance no longer reduces output quantity but instead determines the carrier's round-trip schedule. A building far from storage will have longer carrier round trips, reducing effective throughput if the output buffer fills before the carrier returns.

The `carrier_travel_ticks` formula is defined as:

`carrier_travel_ticks = floor(distance × ticks_per_tile)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Manhattan distance | `distance` | int | 0–∞ | Number of tiles between the production building and its assigned storage container, measured in Manhattan (grid) distance. `distance = |x_building - x_storage| + |y_building - y_storage|`. Calculated by querying the Grid/Map System. When the A* pathfinder is available, the actual path cost (Σ tile movement costs, roads = 0.5) replaces the raw Manhattan distance. |
| Ticks per tile | `ticks_per_tile` | float | 1.0–10.0 | Base ticks a carrier spends traversing one tile **at 100% efficiency**. Default: **5.0** (anchored 2026-06-12 so a 50%-efficient carrier travels at 10 ticks/tile). Shared constant across LogisticsSystem, NPCSystem, and BuildingRegistry. The base travel time is then divided by the carrier's food-efficiency (Formula F4, ADR-0012). |

**Output Range:** `0` to `∞` (int). A distance of 0 means carrier is at the building immediately (same tile). No upper clamp — at extreme distances, round trips take proportionally longer.

**Degeneracy checks:**
- `distance = 0`: `floor(0 × 5.0) = 0`. Carrier arrives and departs instantly — no travel overhead. Ideal placement.
- `distance = 10`, `ticks_per_tile = 5.0`, carrier efficiency 1.0: `floor(10 × 5.0) = 50`. Carrier takes 50 ticks one-way; 100 ticks for a full pick-up + return round trip.
- Same trip at carrier efficiency 0.5 (unfed): F4 doubles it — `floor(50 / 0.5) = 100` ticks one-way. Feeding carriers directly buys logistics throughput.
- `distance = 25`: `floor(25 × 5.0) = 125` at full efficiency. Long one-way trip. If effective cycle time is 250 ticks, the carrier still keeps pace; an unfed carrier (250 ticks one-way) does not — output buffer accumulates.

**Example:** Lumber Camp at (3, 7), assigned Storage Building at (8, 2). Distance = |3-8| + |7-2| = 10 tiles.
`carrier_travel_ticks = floor(10 × 5.0) = 50` base ticks one-way, divided by the carrier's efficiency (F4).
A fully fed carrier (efficiency 1.0) needs 50 ticks per leg; an unfed one (0.5) needs 100.

**Cross-reference:** Distance is calculated using Manhattan distance from the Grid/Map System. The Transportation System calls `Grid.get_manhattan_distance(building_x, building_y, storage_x, storage_y)`. Full carrier scheduling (round-trip timing, multiple carriers, buffer overflow) is defined in the Transportation System spec (`design/ux/transportation.md`).

**Design note — Why this replaces the old output modifier:** The old Formula 3 penalized output quantity to create a spatial incentive for compact layouts. The new transport system creates the same incentive through **carrier round-trip time**: a building placed far from storage must either accept lower effective throughput (output piles up while waiting for the carrier) or assign more carriers to compensate. The spatial puzzle is preserved; the mechanism is honest (real transport delay, not phantom output loss).

---

### Formula 4: Production Output

Calculates the actual amount of resources produced by a building per production cycle. With the carrier transport model, distance no longer reduces output — the full base output is always produced and held at the building for carrier collection.

The `production_output` formula is defined as:

`production_output = base_output`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Base production quantity | `base_output` | int | 1–∞ | The building type's standard output per cycle. Looked up from the production table. For Lumber Camp: 5 Wood per cycle. |

**Output Range:** `base_output` (int). Always the full recipe quantity — no distance modifier. The carrier is responsible for physically moving the output; the building always produces the full amount.

**Degeneracy checks:**
- `base_output = 5`: Always produces 5, regardless of distance. Full output deposited into the output buffer each cycle.
- `base_output = 1`: Always produces 1. Even at extreme distances, the building produces its full quantity.

**Example:** Lumber Camp completes a production cycle. `production_output = 5` Wood placed in output buffer, regardless of distance to storage.

**Design note:** Distance no longer causes output loss. A Lumber Camp at distance 10 and distance 1 both produce 5 Wood per cycle. The difference is how fast the carrier can deliver it to storage — which affects effective throughput if the output buffer is limited.

---

### Formula 5: Production Cycle Duration (efficiency-driven, F3)

Calculates how many ticks a production cycle takes. Distance does not affect the cycle
(the operator NPC stays at the building), but **building efficiency does** — this is
Formula F3 from the Efficiency System (ADR-0012), wired into production in the
2026-06-11 balancing pass.

The `production_cycle_duration` formula is defined as:

`production_cycle_duration = max(1, floor(base_cycle_ticks / building_efficiency))`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Base cycle time | `base_cycle_ticks` | int | 1–∞ | The building type's standard production cycle time from the production table (250 for Gathering Hut / Lumber Camp / Stone Mason, 375 for Tool Workshop). |
| Building efficiency | `building_efficiency` | float | 0.0–1.0 | From F2 (worker-based) or F6 × worker efficiency (adjacency buildings). Capped at 1.0 (`BUILDING_EFFICIENCY_MAX`) — buildings never run faster than base. `<= 0` returns the frozen sentinel (INT_MAX). |

**Output Range:** `base_cycle_ticks` (at efficiency 1.0) to INT_MAX (frozen at efficiency 0).

**Live recalculation:** The effective duration is recomputed from the CURRENT
efficiency every tick while a cycle runs (`_advance_production_cycle`), so feeding a
worker or clearing/adding adjacent terrain affects the in-progress cycle immediately —
not only the next one.

**Degeneracy checks:**
- `efficiency = 1.0`: cycle = base (250 → 250 ticks).
- `efficiency = 0.5` (unfed worker): cycle = 2 × base (250 → 500 ticks).
- `efficiency = 0.25` (starving): cycle = 4 × base (250 → 1000 ticks).
- `efficiency = 0.0`: INT_MAX sentinel — building is effectively frozen.

**Example:** Lumber Camp with a fully fed worker (efficiency 1.0): 250-tick cycles,
~5.7 cycles/day. The same camp with an unfed worker (0.5): 500-tick cycles. The carrier
handles output transport on its own independent schedule.

---

### Formula 6: Demolition Refund

Calculates the resource refund when a player demolishes a building. Currently set to 0.00 — no refund — but formalized as a formula so it can be changed (e.g., for a "guilt-free trial" mode or different game modes).

The `demolition_refund` formula is defined as:

`demolition_refund(resource) = floor(build_cost(resource) × refund_rate)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Build cost of resource | `build_cost(r)` | int | 0–∞ | Number of units of resource `r` that were spent to build this structure. Stored in the building registry at construction time. |
| Refund rate | `refund_rate` | float | 0.00–1.00 | Fraction of build cost refunded on demolition. Default: 0.00 (no refund). Tuning knob — see Tuning Knobs section. |

**Output Range:** `0` to `build_cost(resource)` (int). Floor-rounded. Minimum is 0.

**Degeneracy checks:**
- `refund_rate = 0.00` (default): `floor(0 × 0.00) = 0` for all resources. Zero refund — consistent with current design.
- `refund_rate = 1.00` (full refund): `floor(build_cost × 1.00) = build_cost`. Full refund.
- `refund_rate = 0.50` (half refund): `floor(build_cost × 0.50)`. Partial refund. E.g., `floor(15 × 0.50) = 7` Wood refunded from a 15 Wood cost.
- `build_cost = 0` (Storage Area): `floor(0 × 0.00) = 0`. Nothing to refund.

**Example:** Player demolishes a Lumber Camp. Build cost was 15 Wood + 3 Stone. Refund rate is 0.00.
- Wood: `floor(15 × 0.00) = 0`
- Stone: `floor(3 × 0.00) = 0`
- Result: No resources returned. Build costs are permanently lost.

---

### Formula 7: Placement Energy Cost

Calculates the energy consumed by the player when confirming a building placement. Energy is drawn from the Player Character System's Energy pool (same pool used for manual labor actions). This is a secondary constraint layered on top of resource costs — the player may have enough resources but insufficient energy to place a building.

The `placement_energy_cost` formula is defined as:

`placement_energy_cost = floor(Σᵢ build_qty(resource_i) × energy_per_resource)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Build cost quantity | `build_qty(r)` | int | 0–∞ | Number of units of resource `r` required to build this building type. Looked up from the build cost table. Summed across all distinct resources in the cost. |
| Energy per resource unit | `energy_per_resource` | float | 0.00–1.00 | Energy cost per resource unit placed. Default: 0.10. Tuning knob — see Tuning Knob T7. |

**Output Range:** `0` to `∞` (float, floor-rounded to int for deduction from PC Energy pool).

**Degeneracy checks:**
- `Σ build_qty = 0` (Storage Area, free build): `floor(0 × 0.10) = 0`. No energy consumed — consistent with the free build cost.
- `energy_per_resource = 0.00`: Always returns 0. Energy is not a constraint for placement. Placement is limited only by resource availability.
- `building = Lumber Camp (15 Wood + 3 Stone)`: `floor((15 + 3) × 0.10) = floor(1.8) = 1`. Costs 1 energy unit.

**Example:** Player has 100 Energy. Places a Residential House costing 10 Wood + 3 Stone.
`placement_energy_cost = floor((10 + 3) × 0.10) = floor(1.3) = 1`
Player's energy drops to 99. The PC System decrements its energy pool by 1.

**Note on energy granularity:** At default `energy_per_resource = 0.10`, the floor rounding means all non-free buildings cost exactly 1 energy (Storage Building: floor(10×0.10)=1, Residential House: floor(13×0.10)=1, Lumber Camp: floor(18×0.10)=1). Energy is intentionally a binary gate — "can I afford to place this building?" — not a graded constraint. This is by design: resource cost provides the graded constraint; energy provides a secondary safety net that becomes meaningful in Core Experience when resource abundance increases.

**Cross-reference:** Energy pool is owned by the Player Character System (PC System GDD). The Building System calls `PCSystem.consume_energy(placement_energy_cost)` as part of the placement commit. If energy is insufficient, placement is blocked and the preview shows "Not enough energy."

---

### Formula 8: NPC Spawn Timer (Residential House)

Controls NPC spawning for Residential Houses. The first NPC spawns immediately on construction completion (no formula needed — it's an event trigger). The second NPC spawns after a fixed timer expires.

The `npc_spawn_2` check is defined as:

`npc_spawn_2_available = (npc_spawn_timer >= npc_spawn_2_threshold)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| Spawn timer | `npc_spawn_timer` | int | 0–∞ | Number of ticks this building has been in OPERATING state without having 2 NPCs spawned. Increments by 1 each tick via `Tick.on_ticks_advanced()`. Resets to 0 on NPC spawn or building demolition. |
| Second NPC threshold | `npc_spawn_2_threshold` | int | 1–∞ | Ticks after construction completion before the second NPC spawns. Default: 1000 (`NPC_SPAWN_INTERVAL`, ≈ 0.7 in-game days at 1440 ticks/day). Tuning knob — see Tuning Knobs section. |

**Output Range:** `true` or `false` (boolean). Evaluated every tick while the building is in OPERATING state.

**Degeneracy checks:**
- `npc_spawn_timer = 0` (just completed construction): `0 >= 1000` is `false`. First NPC spawned immediately; second will not spawn until 1000 ticks have elapsed.
- `npc_spawn_timer = 999`: `999 >= 1000` is `false`. One tick remaining.
- `npc_spawn_timer = 1000`: `1000 >= 1000` is `true`. Second NPC spawns. Timer resets.
- `npc_spawn_timer = 5000` (timer not reset after spawn): `5000 >= 1000` is `true`. If the timer is not properly reset after the spawn, the check returns true every tick. The implementation MUST reset the timer or set a flag to prevent repeated spawns. Maximum NPCs per house: 2 (hard-coded cap).
- Building demolished before timer reaches threshold: Timer is cleared. No second NPC spawns.

**Example:** Residential House completes construction at tick 0. First NPC spawns instantly. Timer starts at 0.
- Tick 0: `0 >= 1000` → `false`. Waiting.
- Tick 500: `500 >= 1000` → `false`. Still waiting.
- Tick 1000: `1000 >= 1000` → `true`. Second NPC spawns. Timer resets.
- Tick 1001+: `0 >= 1000` → `false` (timer reset). No further spawns (max 2 NPCs).

## Edge Cases

Edge cases are organized by severity. **HIGH** cases are mandatory for the Vertical Slice implementation. **MEDIUM** cases are in scope for the Vertical Slice. **LOW** cases are noted for developer awareness and future iterations.

---

### HIGH Severity

**EC-H1: Save/Load During Construction Progress**

- **Scenario:** The game is saved while a building is in the CONSTRUCTING state (e.g., Residential House at 87/150 ticks accumulated). On reload, the building must resume construction from where it left off — not reset to 0 and not start fully built.
- **Handling:** The building's construction progress (`accumulated_ticks`) is serialized as part of the building registry snapshot in the Save/Load System. On load:
  1. The building is re-instantiated in its correct state (CONSTRUCTING, OPERATING, etc.).
  2. For CONSTRUCTING buildings: `accumulated_ticks` is restored from the save. Construction resumes on the next `on_ticks_advanced` event.
  3. For OPERATING buildings with active production cycles: both the production cycle timer and the NPC spawn timer (if applicable) are restored.
  4. Buffered output (`buffered_output`) is restored exactly — output is never discarded regardless of ticks elapsed since save.
  5. For BLOCKED buildings: no timer is at risk. The building re-checks input availability on `on_ticks_advanced` after load.
- **Rationale:** Construction progress is a scalar value (integer ticks). Serializing it is trivial. Resetting to 0 on reload would be a severe frustration. Resetting to full (instantly built) would be inconsistent with the no-refund demolition rule. Resuming from the save point is the only defensible choice.
- **Cross-reference:** Save/Load System GDD (building registry serialization). Inventory/Storage System EC-H3 (IN_TRANSIT state serialization pattern).

**EC-H2: Production Building Stalls When Storage Is Full**

- **Scenario:** A Lumber Camp completes a production cycle and attempts to deposit 5 Wood into its assigned storage container. The container is at capacity (150/150 slots). The building cannot deposit its output.
- **Handling:** (Defined by Inventory/Storage System EC-H4 + Building System Rule 7)
  1. Deposit attempt fails (`deposit_output` returns FAILURE).
  2. The output stays in the building's output buffer; the carrier holds any cargo it already picked up (WAITING_DESTINATION) until storage frees up.
  3. Once the output buffer reaches `output_capacity`, no new cycle starts — the building idles in OPERATING.
  4. The moment buffer space frees (carrier pickup or manual drag), the next cycle starts automatically.
  5. The building waits **indefinitely** — output is never discarded.
- **Rationale:** Output is the result of consumed inputs; discarding it would punish the player for a logistics problem they can still fix. A full buffer is a signal to fix logistics, not a countdown to loss.
- **Cross-reference:** Inventory/Storage System EC-H4 (full container deposit).

**EC-H3: Demolition During Active Production**

- **Scenario:** A Lumber Camp is in the middle of a production cycle (60/100 ticks) when the player initiates demolition.
- **Handling:**
  1. The building transitions from its current state (CONSTRUCTING, OPERATING, or BLOCKED) directly to DEMOLISHED. No intermediate state.
  2. The building's PackedScene is destroyed (`queue_free()`).
  3. The building is removed from the Grid System's BuildingLayer.
  4. **No resource refund.** Any inputs consumed at the start of the interrupted cycle are permanently lost.
  5. Any NPC assigned to the building is released back to the global NPC pool (`release_npc(npc_id)`).
  6. Resource tiles beneath the building remain cleared (not restored).
  7. Any pending production cycles are cancelled. All internal state is discarded.
  8. Buffered input/output items are dropped onto the tile via `building_items_dropped` (see Rule 8) — not refunded to storage, but recoverable as world pickups.
- **Rationale:** Demolition is intentionally irreversible. No refund reinforces "earned automation." The NPC release is the only recovery — all material investment is sunk.
- **Cross-reference:** Building System Rule 8 (demolition procedure).

**EC-H4: Building Placed on Resource Tile (Resource Permanently Lost)**

- **Scenario:** The player places a building on a tile containing a clearable resource (TREE, BERRY, GRASS). The resource had value but has no representation after placement.
- **Handling:**
  1. Grid's `validate_placement()` determines the resource is clearable and returns SUCCESS.
  2. Grid's `place_building()` removes the resource from ResourceLayer atomically with the BuildingLayer update.
  3. **No resource refund, no salvage, no notification** beyond the placement preview showing the resource tile as the build target.
  4. The resource is permanently destroyed.
- **Rationale:** Consistent with Grid/Map System's "Resource tile clearing" rule and Inventory/Storage System EC-M2. Buildings "clear the land." The Grid System handles clearability; the Building System has no separate resource-loss check.
- **Cross-reference:** Grid/Map System GDD (resource tile clearability). Inventory/Storage System EC-M2.
- **Out of scope:** Non-clearable resource tiles (STONE, IRON) — placement is blocked entirely by `BLOCKED_BY_RESOURCE_TILE`.

**EC-H5: Container Demolished While Building References It (Orphaned Reference)**

- **Scenario:** A production building (e.g., Lumber Camp) is assigned to Storage Area SA1. The player demolishes SA1. The building still holds a reference to `container_id = "SA1"`, but the container no longer exists.
- **Handling:**
  1. Inventory System emits `on_container_removed(container_id)` when the container is removed.
  2. Building System receives the signal and iterates all buildings to find any with `assigned_container_id == container_id`.
  3. For each affected building: enters BLOCKED state, `assigned_container_id` set to `null`, red indicator shown, tooltip: "No storage assigned."
  4. Player must assign a new storage area via building UI. When assigned, building transitions to OPERATING (or stays BLOCKED if other inputs missing).
  5. Buffered output is unaffected — it stays in the building's own buffer (output is only ever stored locally until a carrier collects it).
- **Rationale:** Buildings need storage. An orphaned reference must be explicitly resolved by the player — not auto-fixed (which could silently pull from the wrong storage). The held output is discarded because there is no destination to deposit to. This is a harsh consequence — it reinforces that storage is essential infrastructure. Players will learn to build redundant storage or keep output flowing.
- **Cross-reference:** Inventory/Storage System EC-M6 (orphaned reference).

---

### MEDIUM Severity

**EC-M1: Placement Race Condition — Validation vs. Commit**

- **Scenario:** The player hovers the building ghost over a tile. `validate_placement()` returns SUCCESS. Between validation and confirmation, another process modifies the tile state.
- **Handling:** The Building System performs a **re-validate at commit time**:
  1. Player confirms placement → Building System calls `validate_placement()` again (internal second check).
  2. If still SUCCESS: proceed with placement.
  3. If BLOCKED_BY_*: abort placement, show brief "Placement invalid" message. No resources deducted (only the commit phase deducts).
- **Rationale:** Single-player, single-threaded Godot means true race conditions are extremely unlikely. The re-validate is a zero-cost safety net for future multiplayer changes, background tile modifications, and debugging scenarios.
- **Cross-reference:** Grid/Map System GDD EC "Building Placement Edge Cases."

**EC-M2: Two Buildings Competing for the Same Storage Resource Simultaneously**

- **Scenario:** Two production buildings draw on the same limited resource pool (e.g., both need the last tool in storage delivered).
- **Handling:** Building updates are processed in **deterministic order** per tick cycle: `building_id` ascending (natural sort, maintained by `_insert_sorted`). The first building's cycle start consumes from its own input buffer; carriers deliver in route round-robin order. The losing building enters BLOCKED until the next delivery.
- **Rationale:** Deterministic ordering prevents non-deterministic behavior. If the order were based on production completion time, the same scenario could produce different outcomes across saves.
- **Cross-reference:** Inventory/Storage System EC-H5 (concurrent storage modifications).

**EC-M3: Residential House NPC Spawn During Day Transition**

- **Scenario:** A Residential House completes its NPC spawn timer (1000 ticks) at the exact tick as a day transition (`on_day_transition`). The spawned NPC is immediately subject to hunger consumption.
- **Handling:** The Tick System's signal dispatch order is authoritative: `on_ticks_advanced()` fires before `on_day_transition()`. Therefore, the NPC **always** contributes to the day's food requirement on its spawn day.
- **Rationale:** This is a Tick System ordering decision. The Building System fires `on_npc_spawned()` on tick advancement; the Hunger System subscribes to `on_day_transition`. The order is fixed.
- **Cross-reference:** Tick System GDD (signal dispatch order). Hunger System GDD (day-transition consumption).

**EC-M4: Building at Map Edge — Radius Queries Clipped**

- **Scenario:** A Lumber Camp is placed at the edge of the 30×30 grid (e.g., tile (0, 15)). Radius-based queries return fewer tiles than a center building would see.
- **Handling:** **No special edge-case handling in the Building System.** Distance calculations (Formula 3 and 4) use Manhattan distance, which is unaffected by grid boundaries. Radius clipping is the Grid System's responsibility.
- **Rationale:** Distance formulas are coordinate-agnostic. They only care about the distance value, not absolute coordinates.
- **Cross-reference:** Grid/Map System GDD EC "Grid Boundary Edge Cases."

**EC-M5: Pause/Resume During Construction — Progress Preservation**

- **Scenario:** The player pauses while a building is under construction (e.g., 120/200 ticks). The game is paused for an arbitrary amount of real time, then resumed.
- **Handling:**
  1. When PAUSED, `on_ticks_advanced()` is not called (or called with `delta_ticks = 0`). Construction progress does not change.
  2. When resumed, `on_ticks_advanced()` resumes with normal `delta_ticks`. Progress continues from the stored value.
  3. **No progress is lost.** The building does not reset.
- **Rationale:** Pausing is a meta-game action, not a gameplay state change. The game world freezes. This is enforced by the Tick System's pause logic.
- **Cross-reference:** Tick System GDD (pause behavior). Building System Rule 4.

---

### LOW Severity

**EC-L1: Building Type Deprecated Between Game Versions**

- **Scenario:** A save file contains a building type that no longer exists in the current build's building registry.
- **Handling:**
  1. Log warning: "Unknown building type '[building_type]' — deprecated."
  2. The building instance is destroyed, its tile in BuildingLayer set to `null`.
  3. Resource tiles beneath the building are restored to pre-building state (cleared resources returned).
  4. **No resource refund.**
- **Rationale:** Forward-compatibility safety net. The game must not crash on load. Resource restoration "frees" the land but is not a refund. **Note:** This is a special backward-compatibility case that differs from EC-H4 (normal placement permanently destroys resources). Deprecated-building resource restoration exists only to prevent permanently blocked tiles in loaded saves.
- **Cross-reference:** Grid/Map System GDD EC "Map Loading Edge Cases."

**EC-L2: Grid Size Change Between VS (30) and MVP (50)**

- **Scenario:** A VS save (30×30 grid) is loaded in an MVP build (50×50 grid). Buildings are at valid coordinates in the VS grid but occupy only a fraction of the expanded grid.
- **Handling:** The grid is instantiated at its configured size (50×50). Buildings are instantiated at their original coordinates. No coordinate remapping. All distance calculations continue to work (distance is relative, not absolute).
- **Rationale:** Grid size is a project-level constant. 30×30 coordinates are a valid subset of 50×50 coordinates.
- **Cross-reference:** Grid/Map System GDD EC "Grid size change between VS and MVP."

**EC-L3: Stalled Re-evaluation After Storage Capacity Increases**

- **Scenario:** A building idles with a full output buffer. The carrier finally finds space at the destination and picks up. Does production resume immediately?
- **Handling:** The cycle-start check runs on every `on_ticks_advanced` tick. As soon as the buffer drops below `output_capacity`, the next cycle starts. No manual player action required.
- **Rationale:** No timer or discard mechanic exists. Output-full idle is purely a "waiting for pickup" condition that resolves as soon as it clears.
- **Cross-reference:** Inventory/Storage System EC-M3. Building System Rule 7.

**EC-L4: Building Frozen at Zero Efficiency**

- **Scenario:** A building's efficiency reaches 0.0 (theoretical — the nutrition curve floors NPC efficiency at 0.25 and adjacency floors at 0.5, so this requires future modifiers).
- **Handling:**
  1. Formula 5 / F3 returns the INT_MAX sentinel — the cycle never completes.
  2. The building does not crash, does not enter BLOCKED, and consumes no further inputs (inputs were consumed at the cycle start that froze).
  3. The live recalculation un-freezes the cycle the moment efficiency rises above 0.
- **Rationale:** A frozen building is a visible signal, not an error state. The floors in the efficiency curves are deliberately set so normal gameplay cannot reach 0.
- **Cross-reference:** Formula 5 degeneracy check. ADR-0012 F3 sentinel.

**EC-L5: Tool Charge Depleted During Production**

- **Scenario:** A Lumber Camp's input buffer holds 0.03 tool charge. Each cycle consumes 1/30 ≈ 0.033 charge. The next cycle start finds insufficient charge.
- **Handling:**
  1. `_try_start_production_cycle` checks the input buffer at cycle start. If `input_buffer["tool"] < 1/30`, the cycle does not start — the building enters BLOCKED (`Missing required input`) if an input carrier is assigned, or BLOCKED (`No carrier assigned (inputs)`) if not.
  2. Charge is consumed atomically at cycle start; buffer entries that reach ≤ 0 are erased.
  3. The building remains BLOCKED until a carrier delivers the next tool (+1.0 charge ≈ 30 more cycles) or the player manually loads one.
- **Cross-reference:** Production table (charge_cost = 1/30). `tools/balance/balance-findings.md` finding B1/E1 (tool as capital good).

---

### Edge Case Matrix: Cross-System Interactions

| EC ID | Primary Owner | Coordinating System(s) | Boundary |
|-------|--------------|------------------------|----------|
| EC-H1 | Building System | Save/Load System | Save/Load ↔ Building |
| EC-H2 | Building + Inventory | Inventory/Storage System | Building ↔ Inventory |
| EC-H3 | Building System | NPC System, Grid System | Building ↔ NPC, Building ↔ Grid |
| EC-H4 | Grid System | Building System (consumer) | Grid ↔ Building |
| EC-H5 | Building + Inventory | Inventory/Storage System | Building ↔ Inventory |
| EC-M1 | Building + Grid | Grid System (validation) | Building ↔ Grid |
| EC-M2 | Building + Inventory | Inventory/Storage System (ordering) | Building ↔ Inventory |
| EC-M3 | Tick System (ordering) | Building System, Hunger System | Tick ↔ Building ↔ Hunger |
| EC-M4 | Grid System | Building System (delegator) | Grid → Building |
| EC-M5 | Building + Tick | Tick System (pause) | Building ↔ Tick |
| EC-L1 | Building + Grid | Save/Load System | Save/Load ↔ Building |
| EC-L2 | Grid System | Building System (passive) | Grid → Building |
| EC-L3 | Building System | Inventory/Storage System | Building ↔ Inventory |
| EC-L4 | Building System | Formula 3, Formula 4 | Internal formula edge |

## Dependencies

Dependencies are organized into **upstream** (systems the Building System depends on) and **downstream** (systems that depend on the Building System). Each dependency specifies the interface used and the direction of data flow.

### Upstream (Building System depends on)

| System | Dependency Type | Interface Used | Notes |
|--------|----------------|----------------|-------|
| **Grid/Map System** | Hard — spatial validation and placement | `validate_placement(x, y, building_id) -> PlacementResult`, `place_building(x, y, building_id)`, `remove_building(x, y)`, `get_tile_view(x, y)` | The Grid System is the sole owner of the BuildingLayer. The Building System is the sole writer. No other system may modify the BuildingLayer. |
| **Inventory/Storage System** | Hard — resource consumption and production I/O | `try_consume(container_id, resource_id, quantity)`, `deposit_output(container_id, resource_id, quantity)`, `get_resource(container_id, resource_id)`, `on_container_removed(container_id)` | Buildings never access tiles or player inventory directly. All resource operations flow through Inventory APIs. First-fit stacking governs all deposits. |
| **Tick System** | Hard — timer advancement | `on_ticks_advanced(delta_ticks)`, `on_day_transition(days_elapsed)` | The Building Registry subscribes to `on_ticks_advanced` and iterates all buildings in a single loop. No per-scene `_process()` for tick logic. |
| **Resource System** | Hard — resource definitions | `get_resource(resource_id) -> ResourceDef` | Reads resource attributes (stack_limit, max_charge, category) for build cost validation and production definitions. Read-only. |
| **NPC System** | Hard — NPC assignment and availability | `assign_npc(npc_id, building_id)`, `release_npc(npc_id)`, `get_available_npcs(building_id)` | Bidirectional assignment tracking. Canonical record: NPC System (NPCs are the owned resource). Building System stores reference. |

### Downstream (systems that depend on Building System)

| System | Dependency Type | Interface Used | Notes |
|--------|----------------|----------------|-------|
| **Recipe Database System** | Hard — recipe data source | `get_recipe(building_id) -> RecipeDef` | Building System reads recipe definitions (inputs, outputs, tick_cost) from the Recipe Database. Recipe Database is pure data; all execution logic lives in the Building System. There is no separate Production System. |
| **Player Character System** | Soft — placement initiation | `initiate_build(building_id, x, y)`, receives `on_construction_complete(building_id, x, y)` | Building placement was moved from PC System to Building System (PC System GDD revision B8). The PC System initiates the flow but does NOT execute placement. |
| **Hunger System** | Soft — NPC count for consumption | Indirect via NPC System: `get_all_npcs()` returns count including house-spawned NPCs | Residential House spawns NPCs that become subject to hunger consumption. The Hunger System does not call Building System APIs directly. |
| **HUD/UI** | Soft — display and interaction | `get_building_state(building_id) -> {state, blocked_reason, progress}` | HUD polls Building System for state display (ghost preview, status indicators, tooltip text). Building System does NOT push to HUD. |
| **Save/Load System** | Hard — state serialization | `serialize() -> Array[building_snapshot]`, `deserialize(Array[building_snapshot])` | Building Registry provides deterministic serialization: buildings serialized in `building_id` order, fields in stable order (state, accumulated_ticks, assigned_container_id, npc_id, production_cycle_progress, stalled_since_tick). |

### Bidirectional Consistency

**Building System ↔ Grid/Map System:** Grid's `validate_placement()` is the authoritative placement gate. Building System never duplicates validation logic. Grid's BuildingLayer is modified only by `place_building()` and `remove_building()` from the Building System.

**Building System ↔ Inventory/Storage System:** Building System is the active caller for `try_consume()` and `deposit_output()`. Inventory/Storage System emits `on_container_removed()` to notify dependent buildings. Deterministic withdrawal ordering (EC-H5) is enforced by both systems agreeing on `building_id` ascending order.

**Building System ↔ NPC System:** Assignment is bidirectional but canonical in NPC System. Both track the assignment to prevent double-assignment. Building System queries availability; NPC System owns the authoritative assignment state.

**Building System ↔ Recipe Database:** Building System reads recipe definitions at production cycle start. Recipe Database is read-only from the Building System's perspective — no writes, no signals.

**Building System ↔ Save/Load System:** Building System is passive — Save/Load System calls `serialize()` and `deserialize()`. The Building System does not initiate save operations.

### Circular Dependencies Summary

| Pair | Type | Resolution |
|------|------|------------|
| Building ↔ Recipe Database | Active (Building) → Passive (Recipe DB) | Building System reads recipe data. Recipe Database never calls Building APIs. |
| Building ↔ Inventory/Storage System | Active (Building) → Passive (Inventory) | Building System calls Inventory APIs. Inventory only pushes `on_container_removed()`. |
| Building ↔ NPC System | Bidirectional tracking | Both track assignment. Canonical: NPC System. Building System stores reference. |

### Cross-System Design Notes

- **Building representation:** Buildings are PackedScene instances placed at tile centers (not TileMapLayer tiles), per Grid/Map System architecture. The Building System creates these instances and syncs their visual state (sprite, overlay) on state transitions. The instances are pure visual targets — no independent game state lives in the scene.

- **YSort depth sorting:** All buildings must be children of a `YSort` node (`y_sort_enabled = true`) for proper top-down depth ordering. Direct children of `MapRoot` do NOT receive Y-sorting. This is enforced by the Grid/Map System's rendering architecture.

- **Building data model:** Each building is defined by a data table with: `building_id`, `display_name`, `build_cost` (Array[{resource_id, quantity}]), `construction_ticks`, `building_type` (storage/housing/production), and type-specific fields (`capacity`, `housing_slots`, `base_output`, `cycle_ticks`). This table is the Building System's single source of truth — analogous to the Resource System's registry.

## Tuning Knobs

All tuning knobs below are parameters in the formulas defined in Section D. They are exposed as `@export` variables in the Building Registry script. Safe ranges define the boundaries within which the system behaves as designed — values outside may require changes to edge case handling or degeneracy checks.

### T1: Carrier Base Speed (`TICKS_PER_TILE`)
- **Formula:** Formula 3 (Carrier Travel Time); shared with NPCSystem and LogisticsSystem
- **Type:** float
- **Safe Range:** 1.0–10.0
- **Default:** 5.0 (anchored 2026-06-12: 50% efficiency = 10 ticks/tile)
- **Gameplay Effect:** Base travel cost per tile at 100% carrier efficiency. Raising it makes distance (and carrier feeding, via F4) more punishing; lowering it makes logistics nearly free and removes the spatial incentive. Must stay identical across the three systems that hard-code it.
- **Pillar alignment:** Pillar 3 (Optimization Over Expansion) — spatial cost of layout decisions.

### T2: Base Cycle Ticks (per building, `PRODUCTION_TABLE.base_cycle_ticks`)
- **Formula:** Formula 5 (Production Cycle Duration)
- **Type:** int
- **Safe Range:** 50–1000
- **Default:** 250 (Gathering Hut / Lumber Camp / Stone Mason), 375 (Tool Workshop)
- **Gameplay Effect:** Sets the production tempo: ~5–6 cycles/day for basic producers at full efficiency. Halving it doubles throughput across the whole economy — retune the carrier capacity and tool charge together (see `tools/balance/economy_sim.py`).
- **Pillar alignment:** Pillar 1 (Earned Automation) — pacing of the automated economy.

### T3: Demolition Refund Rate (`refund_rate`)
- **Formula:** Formula 6 (Demolition Refund)
- **Type:** float
- **Safe Range:** 0.00–1.00
- **Default:** 0.00
- **Gameplay Effect:** Controls how much resources are returned when a building is demolished. At 0.00 (default), demolition is a sunk cost — reinforcing "earned automation" and discouraging experimental placements. At 1.00, demolition is a free reset — encouraging trial-and-error placement. At 0.50, players can adjust layouts with a 50% tax.
- **Playtesting question:** "Did demolition feel too permanent?" If players report frustration over failed placements and experiment rarely, consider increasing toward 0.50 for a "guilt-free trial" mode. If players feel no penalty for demolishing, increase above 0.00.
- **Pillar alignment:** Pillar 1 (Earned Automation) — the higher the refund, the less "earned" each placement becomes.
- **Note:** This is a game-mode-level knob. A full refund mode could be a separate difficulty setting.

### T4: Second NPC Spawn Threshold (`npc_spawn_2_threshold`)
- **Formula:** Formula 8 (NPC Spawn Timer)
- **Type:** int (ticks)
- **Safe Range:** 100–5000
- **Default:** 1000 (1 in-game day)
- **Gameplay Effect:** Controls how quickly a Residential House ramps from 1 NPC to 2 NPCs after construction completes. At 100 ticks (10 seconds), a new house is effectively producing 2 NPCs immediately. At 5000 ticks (50 seconds), players must wait a noticeable amount of time for the second NPC, extending the sense of gradual growth. The default 1000 (1 day) provides a moderate ramp — the player sees the house sit at 1 NPC for a full day cycle.
- **Playtesting question:** "Did the NPC spawn timing feel right?" If players feel houses should ramp faster, decrease toward 500. If the game feels too NPC-saturated early on, increase toward 2000.
- **Pillar alignment:** Pillar 1 (Earned Automation) — gradual growth reinforces the sense of building something from nothing.

### T5: Adjacency Efficiency Curve (`ADJACENCY_BASE` / `PER_TILE` / `FLOOR` / `CEIL`)
- **Formula:** Formula F6 (Efficiency System, ADR-0012) — `clamp(0.7 + 0.10 × tiles, 0.5, 1.0)`
- **Type:** floats in `EfficiencyFormulas`
- **Safe Range:** base 0.5–0.9, per-tile 0.05–0.25, floor ≥ 0.5
- **Default:** base 0.7, +0.10/tile, floor 0.5, ceiling 1.0 (1 tile → 0.80, 2 → 0.90, 3+ → 1.00)
- **Gameplay Effect:** How strongly map geometry rewards/punishes placement of adjacency buildings (Lumber Camp, Stone Mason, Gathering Hut). The floor guarantees no building freezes purely from geometry. Softened 2026-06-12 from +0.25/tile so that 1–2 adjacent tiles is viable, 3+ is a layout reward.
- **Pillar alignment:** Pillar 3 — layout optimization stays a gradient, not a wall.

### T6: Construction Time Tuning (Per-Building, `BUILD_TIME`)
- **Formula:** Formula 2 (Construction Time Lookup)
- **Type:** int (ticks)
- **Safe Range:** 0–∞
- **Default:** 0 (Collection Point, Road), 960 (Storage Building), 1200 (Residential House), 640 (Gathering Hut), 1600 (Lumber Camp, Stone Mason), 3000 (Tool Workshop)
- **Gameplay Effect:** Construction pacing in real planning units (0.4–2.1 in-game days). Rescaled ×8–12 on 2026-06-11 so building is a commitment, not an instant.
- **Playtesting question:** "Do building construction times feel appropriate?" Adjust individual building times based on feedback, keeping the hours-to-days scale.

### T7: Building Menu Energy Cost per Resource
- **Context:** Rule 2 (Placement — "deducts placement energy from the player's energy pool per Formula 7")
- **Type:** float (energy per resource unit)
- **Safe Range:** 0.00–1.00
- **Default:** 0.10
- **Gameplay Effect:** Controls the energy "cost" of placing a building, separate from the resource cost. At 0.00, placing buildings costs no energy — the only constraint is resource availability and grid space. At 1.00, placing a Lumber Camp (18 total resource cost) costs 1.8 energy. The default 0.10 means a Lumber Camp costs 1.8 energy, a Residential House costs 1.3, and a Storage Building costs 1.0. This is a secondary constraint layered on top of resource costs — it prevents energy-flood scenarios where the player has abundant resources but unlimited energy to place everything instantly.
- **Playtesting question:** "Did energy feel like a meaningful constraint on building placement?" If players never worry about energy during placement, this knob can be reduced toward 0.00. If placement feels too easy, increase toward 0.20.
- **Pillar alignment:** Pillar 1 — ties building density to energy management, reinforcing that every placement is a resource decision.

### T8: Building Capacity Multiplier
- **Context:** Storage Building capacity field
- **Type:** float
- **Safe Range:** 0.50–3.00
- **Default:** 1.00
- **Gameplay Effect:** Scales the base storage capacity of all storage buildings. At 1.00 (default), Storage Area = 50 slots, Storage Building = 150 slots. At 2.00, Storage Building = 300 slots — storage upgrades become more impactful, encouraging larger builds. At 0.50, Storage Building = 75 slots — forcing the player to build more buildings for more capacity, which is more spatially expensive but provides more placement decisions.
- **Playtesting question:** "Did storage capacity feel like the right pressure?" If players always have too much storage, decrease toward 0.75. If players are constantly capped and need to rush new storage, increase toward 1.50.
- **Note:** This knob affects space planning more than production. It's a secondary dial — important for pacing but not for immediate feel.

### T9: Tool Charge Cost Per Cycle (`charge_cost`)
- **Context:** Rule 5 (Operation — Lumber Camp, Stone Mason), `PRODUCTION_TABLE.inputs`
- **Type:** float
- **Safe Range:** 1/100–1.0
- **Default:** **1/30 ≈ 0.033** (one delivered tool = 1.0 buffer charge = 30 cycles ≈ 5 in-game days)
- **Gameplay Effect:** Controls tool durability. At 1.0 (the pre-balancing value), one tool lasted exactly one cycle — the tool chain became a treadmill that ran at a permanent deficit (~1.5 workshops needed per lumber camp; see balance finding B1). At 1/30, the Tool Workshop is a rare capital investment and the tool balance is positive in the standard village chain. At 1/100, tools are effectively infinite and the workshop loses its purpose.
- **Playtesting question:** "Did tool consumption feel meaningful?" If players never notice tools depleting, increase toward 1/15. If replenishing tools feels like a chore, decrease toward 1/50.
- **Pillar alignment:** Pillar 2 (Information Transparency) — the building UI shows remaining tool charge so players can predict when to stock up.

### Design Note: Multiple Building Distance Penalty

When multiple buildings of the same type share a storage container (e.g., two Lumber Camps assigned to the same Storage Building), each building calculates its own distance penalty independently (Formula 3 is evaluated per-building using its own coordinate). This is the current design — no tuning knob needed. If future design changes this to a shared penalty, a new knob would be added here.

### Knob Interaction Matrix

| Pair of Knobs | Interaction | Notes |
|---------------|-------------|-------|
| T1 + T2 | Carrier speed vs. production tempo decide whether one carrier can keep pace with one producer. | At defaults (5 t/tile, 250 t/cycle, capacity 2) a fed carrier keeps pace out to typical distances; verify changes with `tools/balance/economy_sim.py`. |
| T2 + T9 | Cycle time and tool durability together set the tool drain per day. | Halving T2 doubles tool consumption per day — lower T9 (more cycles per tool) to compensate. |
| T4 + T8 | Second NPC spawn + storage capacity. More NPCs = more food = more production = more storage needed. | If T4 is low (fast NPC growth) and T8 is low (small storage), players may hit storage pressure early. |
| T5 + Nutrition curve | Adjacency and worker food multiply (adjacency buildings: `efficiency = F6 × worker_eff`). | Both floors (0.5 geometry, 0.25 starving) keep the worst case at 0.125 — slow but never frozen. |

## Visual/Audio Requirements

This section covers visual feedback and audio cues for every Building System lifecycle event. Art direction follows the "Functional Clarity" visual identity and Moonlighter aesthetic (warm flat colors, high contrast, readable silhouettes). All status indicators use color + shape combinations for colorblind accessibility (no reliance on color alone).

### Building Sprite Guidelines

**Asset spec: 1×1 tile sprites at 64×64 pixels, Moonlighter style.** Warm flat colors with bold outlines, high contrast against the terrain, no shading gradients — solid fills only. Each building type has a distinct silhouette readable at a glance from across the 30×30 map.

| Building | Silhouette Shape | Primary Color | Secondary Color | Detail Level |
|----------|-----------------|---------------|-----------------|-------------|
| **Storage Area** | Orange X marker on ground (no sprite) | Orange (#E67E22) | Dark brown outline | Minimal — just ground markings |
| **Storage Building** | Small shed with peaked roof, single door | Warm tan walls (#D4A76A) | Brown timber frame (#5D4037), dark gray roof (#455A64) | Door detail, roof pitch, timber beam lines |
| **Residential House** | Cozy house with chimney, rounded windows | Warm cream walls (#F5E6CA) | Brown timber frame (#5D4037), terracotta roof (#C0392B) | Chimney smoke (animated), window panes, front door |
| **Lumber Camp** | Open-sided shed with sawhorse, visible wood pile | Pale wood color (#C9B07A) | Dark brown posts (#3E2723), gray saw blade | Saw blade outline, stacked wood planks, open front |

**Design rules:**
- All building sprites anchored at bottom-center of 64×64 tile (y-resolution).
- Ground shadow underneath each building (solid dark shape, no gradient).
- Roof overhang extends 8px beyond walls on all sides for visual warmth.
- Warm palette: all colors use warm undertones (no cool blues on buildings themselves). Terrain provides cool contrast.
- Silhouette test: each building must be distinguishable from the others at 25% zoom (16×16 preview size).

### Visual Feedback by Lifecycle Event

**VFX-1: Placement Preview (PLACE_VALIDATING)**

- **Visual:** A semi-transparent ghost sprite of the building appears at the mouse cursor position. The ghost is rendered at 60% opacity with the building's normal sprite.
  - **Valid placement:** Ghost tinted green (#4CAF50 overlay). Ground tile highlighted with a thin green border.
  - **Blocked placement:** Ghost tinted red (#E74C3C overlay). Ground tile highlighted with a thick red border. A small icon appears above the ghost indicating the block reason:
    - X icon for `BLOCKED_BY_BUILDING`
    - Wall icon for `BLOCKED_BY_IMPASSABLE`
    - Border icon for `BLOCKED_BY_BOUNDS`
    - Tree icon for `BLOCKED_BY_RESOURCE_TILE`
    - Bag icon for insufficient resources (queried from Inventory System)
- **Audio:** No audio for preview hover. A soft "click" when confirming placement.

**VFX-2: Construction Start**

- **Visual:** Ghost solidifies into the building sprite at full opacity. A scaffolding overlay fades in over the sprite (semi-transparent wooden frame lines drawn on top). The scaffolding has a subtle bob animation (2px vertical oscillation at 2Hz).
- **Audio:** A brief wood thud sound (200ms) when the building first appears.

**VFX-3: Construction Progress (CONSTRUCTING)**

- **Visual:** Hammer animation on the scaffolding. A small hammer icon swings in an arc (270° sweep) every 800ms. The hammer starts at the top-left of the building sprite and swings toward the center. Progress indicator: a thin bar appears at the bottom edge of the building showing `(accumulated_ticks / build_time)` as a green fill (left to right).
- **Audio:** No continuous audio during construction. A soft "thud" at 25%, 50%, 75% milestones (subtle, not distracting).

**VFX-4: Construction Complete**

- **Visual:** Scaffolding overlay fades out over 300ms (alpha 100% → 0%). The building sprite transitions from scaffolding-covered to clean. A brief pulse effect on the building sprite (scale 1.0 → 1.05 → 1.0 over 400ms). Green checkmark icon appears above the building for 1 second, then fades.
- **Audio:** A satisfying "ding" (wooden bell or chime, ~500ms, frequency ~800Hz) + a soft clap of wood (construction completion "sound of completion").

**VFX-5: Operational State — Green (OPERATING, producing)**

- **Visual:** Normal building sprite. A small green dot (4px diameter, #4CAF50) appears in the top-right corner of the sprite. The dot pulses subtly (scale 1.0 → 1.15 → 1.0 at 1.5Hz). If the building is producing (not just sitting idle), a subtle smoke or particle trail rises from chimney/top of building (for Lumber Camp: sawdust particles; for Residential House: chimney smoke).
- **Audio:** No continuous audio. A soft "work hum" is not implemented at MVP — production is purely visual.

**VFX-6: Operational State — Yellow/BLOCKED**

- **Visual:** Green dot turns yellow (#FFC107). The dot becomes static (no pulsing). A small exclamation mark (!) icon appears above the building, hovering 8px above the roof peak. The icon does not animate. Tooltip text on hover shows what's missing.
- **Audio:** No audio for BLOCKED state (silent failure — consistent with Pillar 2: information through UI, not sound).

**VFX-7: Operational State — Red (output-full / waiting carrier) [HISTORICAL — see Rule 7]**

- **Visual:** Red dot turns (#E74C3C) and begins pulsing (scale 1.0 → 1.2 → 1.0 at 1Hz — slower pulse than the green producing dot). The exclamation mark (!) icon appears above the building. Tooltip text: "Storage full."
- **Audio:** No audio for STALLED state (same rationale as BLOCKED).

**VFX-8: Demolish**

- **Visual:** Building sprite shrinks rapidly (scale 1.0 → 0.0 over 300ms) while fading to 0% opacity. Small debris particles scatter outward from the building center (4-6 brown/tan pixel fragments, each 4×4px, flying in random directions 200-40px). The ground tile briefly highlights orange where the building was, then returns to normal terrain.
- **Audio:** A quick "crunch" sound (wood breaking, ~300ms, descending pitch) as the building collapses.

**VFX-9: Residential House NPC Spawn**

- **Visual:** When the first NPC spawns (immediate): a small person-silhouette icon (not a full NPC figure) appears above the building door, waves briefly (2-frame wave animation, ~500ms), then fades. When the second NPC spawns (after 1000 ticks): same silhouette animation from the building door. NPCs are not visible on the map per game design; this is a brief celebratory indicator, not a persistent NPC presence.
- **Audio:** A soft "door open" creak + a subtle "hello" murmur (very quiet, 300ms).

**VFX-10: Placement on Resource Tile**

- **Visual:** When the building is placed on a clearable resource tile, the resource sprite briefly flashes (brightness increase, 200ms) then disappears as the building's foundation takes over. No special notification — the resource disappearance is visually implicit in the placement animation.
- **Audio:** A brief "crunch" (terrain clearing, same as demolish but shorter, ~150ms).

### Status Indicator Design (Colorblind-Safe)

All status indicators use **color + shape + animation** triple encoding. A colorblind player can identify every state by shape or animation alone.

| State | Color | Shape | Animation | Colorblind-safe? |
|-------|-------|-------|-----------|-----------------|
| Producing | Green (#4CAF50) | Solid circle (4px) | Subtle pulse (1.5Hz) | Yes — circle + pulse |
| Idle (no production cycle) | Gray (#9E9E9E) | Solid circle (4px) | None | Yes — gray + static |
| BLOCKED | Yellow (#FFC107) | Solid circle + exclamation mark above | None | Yes — exclamation mark |
| STALLED | Red (#E74C3C) | Solid circle | Slow pulse (1Hz, larger amplitude) | Yes — slow big pulse |
| CONSTRUCTING | Orange (#FF9800) | Scaffolding overlay | Hammer swing (periodic) | Yes — scaffolding unique shape |

**Color hex values chosen for maximum contrast on all terrain types:**
- Green #4CAF50 — passes WCAG AA on brown (#5D4037) and green (#388E3C) terrain
- Yellow #FFC107 — passes WCAG AA on all terrain except very yellow grass
- Red #E74C3C — distinct from yellow in hue (red vs. yellow), providing maximum contrast
- Gray #9E9E9E — neutral, no hue conflict with any terrain

**Colorblind simulation targets:**
- Deuteranopia (red-green weakness): Green becomes darker orange, Yellow remains yellow, Red remains distinguishable as a darker red-orange. Distinguishable by shape+animation.
- Tritanopia (blue-yellow weakness): No critical impact — no blue-dependent indicators.
- Protanopia (red weakness): Red-tinted colors shift toward yellow. The red demolition ghost uses an X icon overlay, not just color.

### Art Bible Mapping

| Requirement | Art Bible Section | Principle |
|-------------|------------------|-----------|
| Building silhouette readability | Section 1 (Visual Identity — Functional Clarity) | "Can I identify a building from across the room?" — each sprite passes the 16×16 silhouette test |
| Warm flat colors, no gradients | Section 2 (Color System — Palette Direction) | Moonlighter-aligned: solid fills, warm undertones, high-contrast outlines |
| Status indicator color choices | Section 3 (Color System — Accessibility) | Colorblind-safe triple encoding; WCAG AA contrast verification |
| Minimalist medieval shapes | Section 1 (Visual Identity — Minimalist Medieval) | Timber frames, thatched roofs, cobblestone — no fantasy-kitsch |
| Ground shadows (solid, no gradient) | Section 2 (Shape Language — Consistency) | All shadows use the same dark fill shape language, not per-object shading |
| Particle effects (debris, sawdust, smoke) | Section 1 (Information Density) | Particles are minimal — maximum 6 fragments, no bloom/glow. Always secondary to building readability |

## UI Requirements

### UI-1: Building Menu (Build Mode Entry)

- **Trigger:** Player clicks the Building Button in the HUD (or presses B key) → opens the Building Menu as an overlay panel.
- **Layout:** Grid of building icons (2 columns, scrollable if more than 6 buildings). Each icon shows the building sprite at 32×32 (half resolution of full sprite) with the building name below it.
- **Per-building row entries:**
  - Building icon + name
  - Build cost display (resource icons with quantities: e.g., 🪵 15 + 🪨 3)
  - Energy cost (e.g., "1 Energy") — shown in small text
  - Affordability indicator: cost row is green if affordable, red if not (with a small "!" if resources are insufficient, showing deficit quantity)
  - Construction time (e.g., "200 ticks") — shown in small text
- **Selection:** Clicking a building icon selects it and closes the menu. The building ghost appears at the cursor. The previously selected building type is highlighted with a border in the menu.
- **Close:** Click outside the menu, press Escape, or right-click closes the menu and deselects.

### UI-2: Placement Ghost Preview

- **Trigger:** Player selects a building from the menu and moves cursor onto the map.
- **Display:** The ghost sprite follows the cursor, rendered at full sprite resolution with 60% opacity overlay (green tint if valid, red tint if blocked).
- **Tooltip under ghost:** Shows building name, build cost, construction time, and energy cost (per Formula 7). E.g., "15 Wood, 3 Stone, 1 Energy". If blocked, shows the block reason:
  - "Cannot build here — occupied" (BLOCKED_BY_BUILDING)
  - "Cannot build here — impassable terrain" (BLOCKED_BY_IMPASSABLE)
  - "Cannot build here — out of bounds" (BLOCKED_BY_BOUNDS)
  - "Cannot build here — resource tile" (BLOCKED_BY_RESOURCE_TILE)
  - "Cannot afford building" (insufficient resources)
  - "Not enough energy" (insufficient energy)
- **Confirm:** Left-click on valid tile confirms placement. Preview disappears, construction begins immediately.
- **Cancel:** Escape, right-click, or scroll-wheel away cancels placement mode and closes the Building Menu.

### UI-3: Building Interaction Panel (Click on Existing Building)

- **Trigger:** Player clicks on an existing building (not in build mode).
- **Display:** A context panel appears adjacent to the clicked building (never off-screen — position adjusts dynamically). The panel shows:
  - **Building name** (header, bold)
  - **Current state** with color indicator (green/yellow/red)
  - **Progress bar** (if CONSTRUCTING or producing): `(accumulated_ticks / total_ticks)` as a horizontal fill bar
  - **State-specific info:**
    - CONSTRUCTING: "Building... X/Y ticks" + progress bar
    - OPERATING: "Producing" or "Idle" + production rate (e.g., "5 wood per cycle")
    - BLOCKED: "Blocked — [reason]" (e.g., "No NPC assigned", "Missing wood")
    - Output-full idle: full output bar shown in the panel
  - **Action buttons** (context-dependent):
    - If OPERATING and has NPC: "Release NPC" button
    - If OPERATING and no NPC assigned: "Assign NPC" button → opens NPC selection list
    - Any state: "Demolish" button (always present)
- **NPC Selection List (if "Assign NPC" clicked):** Opens a secondary popup listing all available NPCs with their names/IDs. Clicking an NPC assigns them and closes the popup.

### UI-4: Demolish Confirmation

- **Trigger:** Player clicks "Demolish" in the Building Interaction Panel.
- **Display:** A confirmation dialog appears:
  - Text: "Demolish [Building Name]? This action cannot be undone. No resources will be refunded."
  - Two buttons: "Confirm Demolish" (red, prominent) and "Cancel" (gray)
  - The building pulses red while the dialog is open to reinforce the danger.
- **On confirm:** Building is demolished (see VFX-8). Interaction panel closes.
- **On cancel:** Dialog closes. Building returns to normal state.

### UI-5: Hover Tooltip (Quick Info)

- **Trigger:** Player hovers cursor over a building for 250ms (tooltip delay to avoid flicker).
- **Display:** A small tooltip appears near the cursor (not anchored to the building — follows cursor to avoid occlusion).
- **Content:**
  - Building name (bold, header)
  - State line: `[Green Dot] Producing — 5 wood/cycle` or `[Yellow Dot] Blocked — No NPC assigned`
  - If CONSTRUCTING: `Construction: 87/200 ticks (43%)`
  - If OPERATING with assigned NPC: `NPC: [NPC Name]`
  - If OPERATING with assigned storage: `Storage: [Storage Name/ID]`
  - Building efficiency (if production building): `Efficiency: 80%` (from F2/F6 × worker)
  - **If building consumes tool charge:** `Tool Charge: 0.7 remaining (≈ 21 cycles)` (input buffer charge; 1.0 = one full tool = 30 cycles). If remaining charge is ≤ 2 cycles worth: display in red. If no charge present: `Tool Charge: NONE — will BLOCK on next cycle`. This ensures the player can see impending tool depletion before it stops production (Pillar 2: Information Transparency).
- **No action buttons in hover tooltip** — it's read-only information.

### UI-6: Build Mode Indicator

- **Persistent UI element** when in build mode (building ghost is visible):
  - A small banner in the top-center of the screen: "Build Mode — [Building Name] — Press Esc to cancel"
  - The banner is semi-transparent, does not obstruct gameplay.
  - The building name in the banner is clickable — clicking it re-opens the Building Menu for quick switching.
- **When build mode is cancelled:** Banner fades out over 300ms.

### UI-7: Construction Completion Notification

- **Trigger:** A building finishes construction (CONSTRUCTING → OPERATING transition).
- **Display:** A small notification appears in the top-right corner:
  - Text: "[Building] is ready!"
  - Duration: 3 seconds, then fades.
  - If multiple buildings complete simultaneously (same tick): consolidated into one notification: "[Building A], [Building B] are ready!"
- **Non-blocking:** Player can interact with the game while the notification is displayed.

## Acceptance Criteria

Each criterion uses the GIVEN/WHEN/THEN format and includes a verification method. Verification methods reference either visual observation (V), tooltip/UI text (T), state machine log (S), or API assertion (A).

### Lifecycle & Placement

**AC-01: Successful Placement**
**GIVEN** a building is placed on a valid tile with sufficient resources, **WHEN** the player confirms placement, **THEN** resources are deducted from storage, the building enters CONSTRUCTING state, and the scaffolding visual appears.
- **Verify:** T — storage UI shows reduced resource count; S — state machine shows PLACE → CONSTRUCTING; V — scaffolding PackedScene is visible

**AC-02: Invalid Placement Blocked**
**GIVEN** a building placement tile is invalid (occupied, impassable, out of bounds, or blocked by resource), **WHEN** the player attempts to confirm placement, **THEN** placement is blocked, the ghost shows a red tint, and a tooltip displays the specific block reason.
- **Verify:** V — ghost tile is red; T — tooltip shows specific reason (e.g., "Tile occupied by another building")

**AC-03: Placement Energy Cost Deduction** [NEW]
**GIVEN** a player has sufficient resources and energy to place a building, **WHEN** placement is confirmed, **THEN** the energy cost calculated by Formula 7 is deducted from the Player Character's energy pool, in addition to resource costs.
- **Example:** Residential House (10 Wood + 3 Stone) at energy_per_resource = 0.10 costs 1 energy. Player with 100 energy → 99 energy after placement.
- **Verify:** T — player energy bar shows -1; S — PC System energy pool decremented by correct amount

**AC-04: Zero-Energy Placement Blocked** [NEW]
**GIVEN** a player has sufficient resources but insufficient energy, **WHEN** the player attempts to confirm placement, **THEN** placement is blocked, the ghost shows a red tint, and the tooltip displays "Not enough energy."
- **Verify:** T — tooltip text "Not enough energy"; V — ghost is red

**AC-05: Storage Area Instant Construction** [NEW]
**GIVEN** a Storage Area is placed (cost: 0 resources, 0 energy), **WHEN** placement is confirmed, **THEN** the Storage Area enters OPERATING state immediately (no CONSTRUCTING phase), with 0 ticks of construction progress required.
- **Verify:** S — state machine goes PLACE → OPERATING directly; V — no scaffolding visual appears

### Construction

**AC-06: Construction Progress**
**GIVEN** a building is in CONSTRUCTING state, **WHEN** accumulated ticks reach the build_time threshold, **THEN** the building transitions to OPERATING state, scaffolding disappears, and a construction completion notification appears.
- **Verify:** S — state machine shows CONSTRUCT → OPERATING; V — scaffolding removed; T — notification "[Building] construction complete!"

**AC-07: Construction Paused When Game Paused**
**GIVEN** a building is in CONSTRUCTING state and the game is paused, **WHEN** time passes in real life, **THEN** construction progress does NOT advance (accumulated_ticks remains unchanged).
- **Verify:** S — accumulated_ticks stays constant across real-time seconds while paused

**AC-08: Construction Demolished Before Completion** [NEW]
**GIVEN** a building is in CONSTRUCTING state (e.g., Lumber Camp at 100/200 ticks), **WHEN** the player demolishes the partially-constructed building, **THEN** the building is destroyed, no resources are refunded, and all construction progress is lost.
- **Verify:** S — building removed from registry; T — "No resources refunded" in demolition dialog; no resource items returned to storage

### Production & Operation

**AC-09: Production Cycle Starts**
**GIVEN** a production building is in OPERATING state with all required inputs available and an NPC assigned, **WHEN** the next tick cycle fires, **THEN** the building deducts inputs from storage and begins a production cycle.
- **Verify:** S — production_cycle_ticks resets to 0; T — building status shows "Producing"; storage UI shows reduced input resources

**AC-10: Blocked State (Missing Input)**
**GIVEN** a production building is missing a required input (resource, tool, or NPC), **WHEN** the tick cycle fires, **THEN** the building enters BLOCKED state and shows a yellow indicator with the missing item shown in the tooltip.
- **Verify:** V — yellow circle indicator with !; T — tooltip lists missing item (e.g., "Missing: NPC assigned")

**AC-11: Unblock on Input Available**
**GIVEN** a production building is BLOCKED, **WHEN** the missing input becomes available (resource deposited or NPC assigned), **THEN** the building automatically transitions back to OPERATING on the next tick cycle without player action.
- **Verify:** S — state machine shows BLOCKED → OPERATING without player input; V — indicator changes from yellow to green

**AC-12: Full Output Regardless of Distance** [REVISED]
**GIVEN** a Lumber Camp (base_output = 5) at any distance from its assigned storage, **WHEN** it completes a production cycle, **THEN** 5 Wood are placed in the output buffer — distance never modifies output quantity.
- **Verify:** S — buffered_output gains exactly 5; T — building detail panel shows 5 Wood buffered

**AC-13: Efficiency-Scaled Cycle Duration** [REVISED]
**GIVEN** a Lumber Camp (base_cycle_ticks = 250) whose assigned worker is unfed (NPC efficiency 0.5), **WHEN** it starts a production cycle, **THEN** the cycle duration equals 500 ticks.
- **Calculation:** F3 — `floor(250 / 0.5) = 500`
- **Verify:** S — production_cycle_duration == 500

**AC-14: Live Efficiency Recalculation Mid-Cycle** [NEW]
**GIVEN** a production cycle is running at efficiency 0.5 (duration 500), **WHEN** the worker is fed at the day transition and efficiency rises to 1.0, **THEN** the in-progress cycle's duration is recomputed to 250 on the next tick — the speed-up applies immediately, not at the next cycle.
- **Verify:** S — production_cycle_duration drops to 250 after the efficiency change

### Output-Full Behavior

**AC-15: No New Cycle When Output Buffer Full**
**GIVEN** a production building whose output buffer holds ≥ output_capacity items, **WHEN** the tick cycle fires, **THEN** no new production cycle starts, the building remains in OPERATING state, and no inputs are consumed.
- **Verify:** S — cycle_running == false, state == OPERATING, input_buffer unchanged

**AC-16: Production Resumes When Output Is Collected**
**GIVEN** a building idle with a full output buffer, **WHEN** a carrier picks up items (or the player drags them out) so the buffer drops below capacity, **THEN** the building starts a new cycle on the next tick without player action.
- **Verify:** S — cycle_running == true after pickup

**AC-17: Buffered Output Is Never Discarded**
**GIVEN** a building has held a full output buffer for any duration, **WHEN** ticks elapse, **THEN** the buffered output is NOT discarded — it remains until collected or the building is demolished.
- **Verify:** S — buffered_output unchanged regardless of ticks elapsed; no discard event fired

**AC-18: Demolition Drops Buffered Items**
**GIVEN** a building holding buffered output and/or input, **WHEN** the player demolishes it, **THEN** the building is destroyed, all buffered items (input buffer rounded up, output buffer, storage container contents) are dropped onto the tile via `building_items_dropped`, and no build-cost resources are refunded.
- **Verify:** S — building removed from registry; V — world pickups spawn on the tile; no resource refund

### Demolition & NPCs

**AC-19: Demolition (No Refund)**
**GIVEN** a player initiates demolition on any building via the interaction panel, **WHEN** the player confirms in the demolition dialog, **THEN** the building is destroyed, no resources are refunded, the assigned NPC is released, and all pending cycles are cancelled.
- **Verify:** S — building removed from registry; T — "No resources refunded" shown; NPC shows "unassigned" in NPC UI

**AC-20: Residential House First NPC Spawn**
**GIVEN** a Residential House completes construction, **WHEN** the construction completes, **THEN** 1 NPC spawns immediately and the second-NPC timer starts at 1000 ticks.
- **Verify:** S — NPC created and assigned to house; S — npc_spawn_timer = 1000; V — spawn animation (silhouette wave) on house sprite

**AC-21: Residential House Second NPC Spawn**
**GIVEN** a Residential House has been in OPERATING state for 1000 ticks with only 1 NPC spawned, **WHEN** the tick counter reaches 1000, **THEN** a second NPC spawns and the timer resets.
- **Verify:** S — 2 NPCs assigned to house; S — npc_spawn_timer = 0; V — spawn animation on house; no third NPC spawns

**AC-22: Residential House NPC Hard Cap** [NEW]
**GIVEN** a Residential House has 2 NPCs spawned and the timer has reset, **WHEN** the npc_spawn_timer reaches 1000 again, **THEN** no third NPC spawns — the house maintains exactly 2 NPCs.
- **Verify:** S — npc_spawn_2_available returns true only once; NPC count for house = 2 regardless of elapsed time; state machine prevents repeated spawn

### Tile & Storage Interactions

**AC-23: Resource Tile Removal**
**GIVEN** a building is placed on a clearable resource tile, **WHEN** placement succeeds, **THEN** the resource is permanently removed from the tile and the building's foundation occupies that tile.
- **Verify:** S — resource entry removed from Grid System ResourceLayer at (x, y); clicking the tile shows no resource info

**AC-24: Storage Container Demolished**
**GIVEN** a production building's storage container is demolished, **WHEN** the container is removed from the Inventory System, **THEN** the building receives a notification, enters BLOCKED state, and displays "No storage assigned" in the tooltip.
- **Verify:** T — tooltip shows "No storage assigned"; V — yellow indicator; S — state = BLOCKED with missing_storage flag

**AC-25: Deterministic Resource Ordering**
**GIVEN** two production buildings assigned to the same storage, **WHEN** both need the same limited resource on the same tick cycle and only one unit is available, **THEN** the building with the lower building_id receives the resource first (deterministic ordering).
- **Example:** Building #3 and Building #7 both need 1 Stone; only 1 Stone available. Building #3 gets it.
- **Verify:** S — Building #3 state = OPERATING, Building #7 state = BLOCKED (missing stone); ordering is reproducible across load/unload

