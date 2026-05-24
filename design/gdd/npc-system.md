# NPC System

> **Status**: In Design
> **Author**: User + Claude (Sonnet 4.5)
> **Last Updated**: 2026-05-11
> **Implements Pillar**: Pillar 1 (Earned Automation), Pillar 2 (Information Transparency)

## Overview

The NPC System is the village's workforce — a pool of automated workers that transform the player's manual labor into passive production. NPCs are recruited when a Residential House is built and left unoccupied: the player triggers recruitment, and one NPC moves in (up to 2 per house). Recruited NPCs are assigned to production buildings (Lumber Camps) and execute a deterministic task cycle: travel to assigned building → participate in production → travel to assigned storage → deposit output → return. NPCs have no visible sprite on the map; they are abstract entities whose presence is communicated through building status indicators (green = producing, yellow = blocked, red = stalled). Movement is Manhattan-distance-based (consistent with Grid/Map System) with tick-cost per tile. Each NPC has an identity, an assignment state, and a position tracked in tile coordinates.

## Player Fantasy

You are the Foreman of your village. The NPCs are your crew — not abstract units, not a population counter, but people you recruit, assign, and lead.

The first NPC assignment is the emotional core of the game. Three days ago you were swinging an axe at bare hands, burning energy every swing, counting every berry. Now you click the Lumber Camp, assign the NPC, and watch them pick up the axe. The production cycle ticks through: the axe falls, the log appears, the status indicator turns green. You didn't move your character. The game just made wood. And it felt like a victory.

This is the Foreman fantasy: competence through delegation. Every NPC assigned is leverage — one hour of planning becomes a day of output. You remember the friction of doing everything yourself, and now you replaced your own labor with something that never tires, never needs food, never runs out of energy. The satisfaction is not "I am strong" or "I am wise" — it is "I am effective."

You earn this through manual investment (Pillar 1). You see it through transparent indicators (Pillar 2). A green status means the crew is working. A yellow status means they need something — a blocked path, an empty storage, a missing tool. A red status means something is broken and urgent. No mystery, no hand-waving. You can always tell what your crew needs.

Reference: Factorio's first conveyor belt — that moment when the factory runs without you watching, and it feels like a win. Anno's population satisfaction — the emotional payoff of seeing people thrive under your care. Both games nail the feeling this system delivers: automation made human.

## Detailed Design

### Core Rules

**Rule 1: NPC Identity and Assignment**
Each NPC is a unique entity with three properties: position (tile coordinates), assignment state (which building or action they are performing), and status (a composite of Perk System evaluations — see Rule 6). NPCs are recruited by the player clicking an unoccupied Residential House and selecting "Recruit." A newly recruited NPC starts in the IDLE state. Each Residential House has up to 2 assignment slots — after the first NPC moves in, the second becomes available 1000 ticks after the first recruitment.

**Rule 2: Recruitment**
Recruitment is a player action with no resource cost and no tick/energy cost. When a Residential House is constructed and unoccupied, the house shows a "Recruit" affordance. The player clicks it. The NPC immediately becomes active and is assigned to the house as their home base. A house can hold max 2 NPCs.

**Rule 3: Task Assignment**
The player assigns an idle NPC to a production building by clicking the NPC (when idle) and then clicking the target building, or by clicking a building with free assignment slots and selecting an idle NPC. A production building's assignment slots are defined in the Building System — a Lumber Camp has 1 slot, a Quarry has 1 slot. The NPC's assignment state changes from IDLE to the building's work cycle (see Rule 4). Assignment is not automatic — the player must choose which NPC goes where.

At assignment time, the player also selects which storage building receives the NPC's output. This assignment is persistent: the NPC always deposits to the same storage until reassigned. If the assigned storage is demolished, the NPC's storage assignment is cleared and they return home IDLE (see Rule 8).

**Rule 4: NPC Task Cycle**
An assigned NPC executes the following cycle:

1. **TRAVEL_TO_BUILDING**: Move from current position to the assigned building's tile. Travel time = Manhattan distance × ticks_per_tile (Formula 1). Each tile costs ticks, not real time.
2. **WORK_AT_BUILDING**: The NPC participates in the building's production process. Production speed is determined by the Building System's production_output formula (Formula 3). If multiple NPCs are assigned to a building, the building's slot definition limits how many can work (typically 1 NPC per slot).
3. **TRAVEL_TO_STORAGE**: After production completes, the NPC travels to their assigned storage building. Travel time = Manhattan distance from building to storage × ticks_per_tile (Formula 1).
4. **DEPOSIT**: The NPC deposits the produced resource into the storage building's inventory (via the Inventory/Storage System's deposit interface). If the storage is full, the NPC holds the output internally and enters a WAITING state — they remain at the storage building until space becomes available, at which point they deposit and continue the cycle. The Building enters STALLED (per Building System EC-H5) while the NPC is waiting.
5. **RETURN_TO_BASE**: The NPC travels back to their home base. Travel time = Manhattan distance from storage to home × ticks_per_tile (Formula 1). Upon arrival, the NPC returns to IDLE state, ready for reassignment.

The cycle repeats until the NPC is reassigned, the building is demolished, or the NPC becomes unavailable (see Rule 6).

**Rule 5: Movement and Pathfinding**
NPC movement uses Manhattan distance (consistent with Grid/Map System). Diagonal movement is not supported — NPCs move along grid axes only. NPCs can pass through any non-walkable tile that a building occupies (buildings are transparent to NPC movement). NPCs cannot pass through other NPCs — if the path is blocked, movement pauses until the blocking NPC moves. At Vertical Slice scope, obstacle detours are not modeled — travel time is purely Manhattan distance. At future scope, pathfinding around impassable tiles (water, cliffs) may replace Manhattan distance.

**Rule 6: NPC Status (deferred to post-VS)**

At Vertical Slice scope, all NPCs work at 100% effectiveness. The Perk System (which will evaluate consumption needs and apply effectiveness modifiers) is not yet designed and will be introduced in a later milestone. NPC behavior at VS is binary: an NPC is either working or idle, with no effectiveness modifiers.

Future: The Perk System will drive NPC effectiveness through disabled perks (food, clothing, shelter), with a special case where food deprivation reduces effectiveness to 50%. Population tier consumption requirements will gate perk activation. This rule is retained as a placeholder — no code or behavior is implemented for it at VS scope.

**Rule 7: NPC Limits**
Each Residential House has a capacity of 2 NPCs. The total NPC population is bounded by the number of Residential Houses × 2. There is no global population cap beyond housing capacity. Food, housing, and perk satisfaction are the limiting factors.

**Rule 7a: Carrier Assignment (Logistics System)**
An idle NPC can be assigned as a **carrier** through the Transportation UI (`design/ux/transportation.md`). When assigned to a carrier route, the Logistics System's carrier FSM **fully replaces** the NPC System's task cycle (Rule 4) for that NPC. The NPC System continues to track position and home base, but the Logistics System dictates the NPC's behavior (TRAVEL_TO_SOURCE → PICKUP → TRAVEL_TO_DESTINATION → UNLOAD → RETURN_HOME — see logistics-system.md Rule 3 and Rule 5).

A carrier-assigned NPC cannot simultaneously be assigned to a production building. The two assignment modes are mutually exclusive — an NPC is either a production worker (Rule 3) or a carrier (this rule), never both. When a carrier route is deleted or deactivated, the NPC returns to IDLE and is available for production assignment again. See `design/gdd/logistics-system.md` for the full carrier state machine and precedence rules.

**Rule 8: NPC Disconnection**

If the assigned production building is demolished, the NPC immediately abandons their current task and returns home (instant, no travel ticks). Any held output is discarded. Upon arrival, the NPC becomes IDLE.

If the assigned Residential House is demolished, the player is shown a confirmation dialog to reassign the NPC to a different available house. If the player confirms and an available house exists, the NPC's home base changes to that house and they continue their current cycle. If no available house exists, the player is shown a second confirmation — if confirmed, the NPC leaves the village (is removed from the game). If the player cancels, the NPC retains their home base and continues working.

If the assigned storage building is demolished, the NPC returns home IDLE. Their storage assignment is cleared. Any held output is discarded.

### States and Transitions

| State | Description | Allowed Transitions |
|-------|-------------|---------------------|
| IDLE | No active assignment. NPC is at their home base. | → TRAVEL_TO_BUILDING (when assigned) |
| TRAVEL_TO_BUILDING | Moving to assigned building. | → WORK_AT_BUILDING (arrived), → IDLE (building demolished) |
| WORK_AT_BUILDING | Participating in production. | → TRAVEL_TO_STORAGE (production complete), → IDLE (building demolished) |
| TRAVEL_TO_STORAGE | Moving to assigned storage after production. | → DEPOSIT (arrived), → IDLE (storage demolished), → IDLE (building demolished) |
| DEPOSIT | Handing off output to storage. | → RETURN_TO_BASE (deposit complete), → WAITING (storage full) |
| RETURN_TO_BASE | Moving back to home base. | → IDLE (arrived) |
| WAITING | Storage was full; NPC waiting at storage for space. | → RETURN_TO_BASE (space available, deposited), → IDLE (storage demolished) |

### Interactions with Other Systems

**Building System**: Buildings have assignment slots (1 slot per worker, typically). Building status indicators reflect NPC presence (green = producing with NPC, yellow = idle without NPC, red = blocked/stalled). Building demolition triggers NPC disconnection (Rule 8). The Building System owns NPC spawn triggering (Residential House spawns NPCs via Formula 8); the NPC System owns what happens after the spawn event fires.

**Inventory/Storage System**: NPCs deposit produced output into their assigned storage building via the deposit interface. Storage full status triggers the NPC's WAITING state. The storage assignment is per-NPC (persistent across cycles). Storage demolition clears the NPC's storage assignment and returns them home IDLE.

**Grid/Map System**: NPC movement uses Manhattan distance and tile coordinates. The Grid/Map System provides the distance calculation. Buildings are transparent to NPC pathfinding at Vertical Slice scope.

**Tick System**: All NPC timing (travel time, work duration) is tick-based. 1000 ticks = 1 day. Travel speed is measured in ticks per tile.

**Player Character System**: Player actions (click to recruit, click to assign) are handled through the player character's interaction system. Assignment is manual — the player decides which NPC goes where. Recruitment costs no energy or ticks.

**Perk System (deferred to post-VS)**: NPC work effectiveness is driven by Perk System evaluations. See Rule 6 — no effectiveness modifiers are active at VS scope.

**Logistics System**: When an NPC is assigned to a carrier route, the Logistics System takes over task scheduling via `npc_system.set_carrier_state(npc_id, state)`. The NPC System provides position tracking (`get_npc_position(npc_id)`) and availability queries (`is_available(npc_id)`). The NPC's production task cycle (Rule 4) is suspended for the duration of carrier assignment. See Rule 7a and `design/gdd/logistics-system.md` for the full contract.

**Population Tier System (deferred to post-VS)**: Defines which goods each NPC tier requires. The Perk System evaluates these requirements against the NPC's home storage. The Population Tier System does not directly modify NPC behavior.

## Formulas

### Formula 1: NPC Travel Time

`travel_ticks = manhattan_distance(from_position, to_position) × ticks_per_tile`

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `from_position` | Vector2i (tile coords) | — | NPC's current position |
| `to_position` | Vector2i (tile coords) | — | Destination tile |
| `ticks_per_tile` | float | 3.0 | Ticks required to travel one tile |

**Notes:**
- Manhattan distance = `abs(from.x - to.x) + abs(from.y - to.y)`, as defined by the Grid/Map System.
- At default `ticks_per_tile = 3.0`, a 10-tile travel costs 30 ticks (~1.8% of a day).
- Minimum `ticks_per_tile = 1.0`. Setting to 0 would make NPCs teleport (infinite production throughput).
- **Perk interaction**: The Perk System may modify the effective `ticks_per_tile` value for individual NPCs based on active perks. When a perk affecting movement is disabled, the effective `ticks_per_tile` increases (NPC is slower). The exact modifier is defined in the Perk System GDD.

**Example:** NPC at (2, 3) travels to building at (5, 3). Manhattan distance = 3. Travel time = 3 × 3.0 = 9 ticks.

---

### Formula 2: NPC Effective Attributes (deferred to post-VS)

At Vertical Slice scope, all NPC effective attributes equal their base values (no modifiers). The Perk System will compute `perk_modifier` and apply it via:

**Formula: `effective_attribute = base_attribute × perk_modifier`**

Where `perk_modifier` is computed by the Perk System and returned as a value in [0.10, 1.00]. The Perk System is the authoritative source for all perk-to-attribute mappings. The NPC System consumes the computed modifier and applies it to its internal calculations.

**Effective attributes (future, not active at VS):**
- **Speed**: Travel and work speed multiplier. Base = 1.0.
- **Production output**: Items produced per work cycle. Base = 1.0 (normalized).
- **Carry capacity**: Max items the NPC can hold. Base = defined by building/storage.

---

### Formula 3: NPC Production Output Per Cycle (delegate to Building System)

The canonical production output formula is defined in the Building System GDD (Formula 4 — Production Output, which uses Formula 3 — Distance Modifier internally). The Building System GDD will include `npc_slots_used` as a multiplicative factor so the complete formula is:

`production_output = floor(base_output × distance_modifier) × npc_slots_used × effective_production_modifier`

NPCs do not define their own production formula — they consume the Building System's result. At VS scope, `effective_production_modifier` = 1.0 (Perk System deferred), so the effective formula is `production_output = floor(base_output × distance_modifier) × npc_slots_used`.

## Edge Cases

**EC-1: NPC Spawned, No Production Buildings Available**
An NPC is recruited but all production buildings are full (all assignment slots occupied). The NPC remains IDLE at their home base. They become assignable again when a building slot frees up (due to building being BLOCKED and releasing the NPC, or the NPC being reassigned). No timeout or auto-assignment occurs — the player must manually assign.

**EC-2: NPC Spawned, No Production Buildings Exist**
The player has recruited an NPC but has not yet built any production buildings. The NPC remains IDLE at home. The Residential House shows a "No workers assigned" indicator. When the player builds a production building with free slots, the NPC becomes assignable (the player must manually click to assign).

**EC-3: Storage Full on Deposit — NPC Waits**
An NPC arrives at storage to deposit but the storage is full (per Building System STALLED rules). Two simultaneous state transitions occur: the NPC enters WAITING (NPC System state) and the building enters STALLED (Building System state, triggered by `building.on_npc_waiting()`). The NPC does not block other NPCs' pathfinding (NPCs are abstract, not physical obstacles at Vertical Slice scope). When storage space becomes available (next tick that storage has room), the NPC deposits immediately and continues the cycle, returning to RETURN_TO_BASE. The building exits STALLED when the NPC completes the deposit.

**EC-4: Production Building Input Unavailable Mid-Cycle**
An NPC is in WORK_AT_BUILDING and the input storage for the building is demolished. The current cycle completes — the NPC already committed to work. On the next cycle start, the building enters BLOCKED (per Building System Rule 7) and releases the NPC. The NPC returns home IDLE. Note: a single-slot building only has one NPC working, so the input cannot be consumed by another NPC — this edge case only applies when an external event (demolition, inventory system error) removes the input.

**EC-5: Building Enters STALLED — NPC Already at Storage**
A building produces output but the assigned storage is full. The building enters STALLED (per Building System). The NPC is already at the storage in WAITING state (EC-3). When space opens, the NPC deposits, returns home, and the building exits STALLED on the next cycle start (inputs refilled).

**EC-6: House Demolished During NPC Work Cycle**
Per Rule 8: the player is shown a confirmation dialog. If reassigned to another house, the NPC's home base changes mid-cycle — the NPC completes their current cycle but returns to the new house on RETURN_TO_BASE. If no house is available and the player confirms removal, the NPC is immediately removed from the game (no item drop, all held output discarded).

**EC-7: All Houses Demolished**
If all Residential Houses are demolished, all NPCs are subject to EC-6. If the player confirms removal for all, the village is left with zero NPCs and must recruit again from new houses.

**EC-8: Storage Assigned to NPC That Is Later Demolished**
Per Rule 8: the NPC's storage assignment is cleared. If the NPC is currently in the task cycle (holding output or traveling), they return home IDLE. On reassignment, the player must select a new storage.

**EC-9: Building Slot Frees Mid-Cycle (NPC Removes Themselves)**
NPCs cannot voluntarily leave an assignment mid-cycle. An NPC in WORK_AT_BUILDING or TRAVEL_TO_STORAGE cannot return home on their own. Only external events (building demolition, storage demolition, house demolition) can force an NPC out of their cycle.

## Dependencies

| System | Relationship | Data Flow |
|--------|-------------|-----------|
| Building System | Both | NPC assigns to buildings; building releases NPC on demolition. Building System calls `npc_system.on_npc_assigned(building_id)` and `npc_system.on_npc_released(building_id)`. NPC System provides `get_available_npcs()` and `get_npc_state(npc_id)`. |
| Inventory/Storage System | Both | NPC deposits output via storage's `deposit(resource, amount)` interface. Storage provides `get_free_space()` and `get_contents()`. |
| Grid/Map System | NPC reads | Grid provides `manhattan_distance(pos_a, pos_b)`. NPC does not modify grid state. |
| Tick System | NPC reads | Subscribes to `ticks_advanced()` for travel timers. Subscribes to `day_transition()` for Perk System re-evaluation (deferred to post-VS). |
| Player Character System | Player writes | Player recruitment and assignment actions flow through PC input system. |
| Perk System (deferred) | NPC reads | Returns `perk_modifier` for each NPC attribute. Deferred to post-VS — all modifiers are 1.0 during VS. |
| Population Tier System (deferred) | Indirect | Defines tier requirements; Perk System translates these to perk evaluations. Deferred to post-VS. |
| Hunger System (deferred) | Indirect | Daily food consumption evaluated by Perk System. Deferred to post-VS. |
| Production System (future) | TBD | When designed, the Production System may manage automated production chains that assign NPCs automatically. At VS scope, all assignment is manual. |

## Tuning Knobs

| Knob | Default | Range | Effect | Notes |
|------|---------|-------|--------|-------|
| `ticks_per_tile` | 3.0 | 1.0–10.0 | Ticks per tile of NPC travel distance. Higher = NPCs spend more time traveling, less time producing. | Primary distance balance knob. At 10.0, a 20-tile trip costs 200 ticks (20% of a day). |
| `npc_effectiveness_floor` | 0.10 | 0.05–0.50 | Minimum effective attribute when all perks are disabled. | Deferred to post-VS — not active at Vertical Slice scope. |
| `npc_capacity_per_house` | 2 | 1–4 | Max NPCs per Residential House. Affects total workforce cap. | Fixed at 2 for VS. Higher values scale total output linearly. |
| `npc_spawn_delay_ticks` | 1000 | 0–5000 | Ticks before the second NPC slot unlocks in a Residential House. | 0 = both slots available immediately. Higher values stretch the "manual → automated" progression. |
| `max_stuck_cycles_before_reset` | 5 | 3–10 | Number of WAITING cycles before the NPC auto-resets to IDLE. | Post-VS only — at Vertical Slice, the player sees full storage visually so infinite waiting is not a problem. |

## Visual/Audio Requirements

Visual/Audio Requirements for the NPC System at Vertical Slice scope:

- NPCs have no visible sprite on the map (as stated in Overview).
- Building status indicators communicate NPC state: green = producing (NPC present and working), yellow = idle (no NPC assigned), red = blocked/stalled (NPC present but blocked).
- Residential Houses show a worker count indicator: "0/2", "1/2", "2/2". An empty slot shows a "Recruit" affordance (clickable UI element).
- Audio: no NPC-specific audio at VS scope. Building status changes may have subtle audio cues (e.g., a soft "click" when an NPC begins working at a building).

## UI Requirements

| ID | Element | Description |
|----|---------|-------------|
| UI-1 | House recruit button | Appears on Residential Houses with empty slots. Text: "Recruit" (or localized equivalent). Clicking triggers NPC recruitment (Rule 2). |
| UI-2 | House worker counter | Shows "X/2 workers" on the house tooltip. Updates in real time as NPCs are recruited or removed. |
| UI-3 | Building assignment UI | When a building has free slots, shows "Assign Worker" affordance. Clicking opens a list of idle NPCs (or auto-selects the nearest). |
| UI-4 | NPC assignment confirmation | When assigning an NPC to a building, the player selects the output storage. UI shows available storage buildings with their current capacity. |
| UI-5 | NPC state indicator (abstract) | No direct NPC UI exists. NPC state is communicated through building status colors and the house worker counter. |

## Acceptance Criteria

| ID | Acceptance Criterion | Verification |
|----|---------------------|--------------|
| AC-1 | Player can recruit an NPC by clicking an unoccupied Residential House | Manual: click house → NPC appears as recruited (counter updates to 1/2) |
| AC-2 | A Residential House supports up to 2 NPCs, with the second slot unlocking after 1000 ticks | Manual: recruit first NPC → wait 1000 ticks → second recruit becomes available |
| AC-3 | Player can assign an idle NPC to a production building with free slots | Manual: click idle NPC → click building → NPC assigned, building status turns green |
| AC-4 | Player selects an output storage at assignment time, and the NPC always deposits to that storage | Manual: assign NPC with Storage A → produce output → NPC deposits to Storage A |
| AC-5 | NPC travel time is proportional to Manhattan distance using Formula 1 | Automated: place building at known distance → measure cycle duration → verify travel time = distance × ticks_per_tile |
| AC-6 | NPC executes full task cycle: travel → work → travel to storage → deposit → return home | Manual: assign NPC → observe green status (working) → observe status change at each phase |
| AC-7 | NPC enters WAITING state when storage is full, and resumes cycle when space is available | Manual: fill storage to capacity → assign NPC to produce → observe NPC at storage (WAITING) → empty storage → observe NPC deposits and returns |
| AC-8 | Building status is green when NPC assigned and producing, yellow when no NPC assigned, red when blocked/stalled | Manual: assign NPC → green; remove NPC → yellow; fill storage → red |
| AC-9 | Demolishing a production building releases the assigned NPC to IDLE | Manual: assign NPC → demolish building → NPC returns home, counter shows 0/2 assigned |
| AC-10 | Demolishing a house triggers reassignment dialog; no house available + confirmation = NPC removed | Manual: demolish house → dialog appears → reassign or confirm removal |

## Open Questions

| ID | Question | Status |
|----|----------|--------|
| OQ-1 | Should the "Assign Worker" UI auto-select the nearest idle NPC, or always present a full list? | **Closed: manual only at VS.** The Foreman fantasy (player choice matters) takes precedence over convenience. Auto-select undermines the emotional core of deliberate assignment. |
| OQ-2 | Should an NPC's storage assignment be editable after initial assignment, or require the NPC to be IDLE first? | **Closed: editable only when NPC is IDLE.** Simpler to implement, no edge cases for mid-cycle storage changes. Storage is cleared automatically if demolished (Rule 8). |
| OQ-3 | Should the Perk System evaluation happen on day transition for all NPCs at once, or per-NPC when they return home? | **Closed: deferred with Perk System.** Perk System is post-VS; this decision is deferred until it is implemented. |
