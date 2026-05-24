# Inventory/Storage System

> **Status**: Approved
> **Author**: User + Claude
> **Last Updated**: 2026-05-11
> **Implements Pillar**: Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)

## Overview

The Inventory/Storage System is the player's material world — the containers that hold resources and the spatial act of moving them from where they're harvested to where they're needed. When you chop a tree, the wood doesn't go into your pockets — it lies on that tile. You walk there, carry it to your storage area, and only then can the village use it. Every movement costs Energy and time. Every tile of distance is a decision: "Is this trip worth the Energy?"

For the Vertical Slice, the system defines two concepts: **tile-drop resources** — items harvested by the player appear on the tile of the action and are not accessible to buildings until placed in a Storage Area — and **storage containers** — the Storage Area (free, 50 slots) and the Storage Building (8 Wood + 2 Stone, 150 slots). Buildings pull inputs exclusively from storage, never directly from tiles or the player.

The Resource System's definitions (stack limits, categories, item charge) flow directly into storage behavior. The system is visible and frequent — you open your storage dozens of times per session, watching slots fill as your village grows from nothing.

## Player Fantasy

**Early Game — The Burden of Distance:**

You've just chopped down a tree. It's eight tiles from your Storage Area. You calculate in your head: 2 energy to pick it up, plus 8 energy to carry it back. That's 10 energy—nearly a tenth of your starting pool. You could make ten trips to the forest edge, or one trip to the quarry 30 tiles away for stone. Your hands are already tired. You start walking.

This is the tactile beginning. Every tile of distance costs something real. The player develops an intuitive sense of "energy budget" the way a medieval peasant would understand "how much work my body can do before sundown." The game speaks to the body first, the mind second.

**Mid Game — The Living Inventory:**

You open your Storage Area. It holds a handful of collected resources, organized by type. You add another batch and watch the slots shift and settle. You notice that processed goods (planks, cooked food) take fewer slots than raw materials. You start thinking: "If I can get an NPC to process everything before it comes in here, I can double my effective capacity." You've just discovered automation through inventory pressure, not a tutorial.

Storage is not a list—it's a place. A physical container where things exist in space, and watching it fill is watching your village take shape. You understand capacity through visual occupancy, not a percentage bar. Empty slots feel like wasted space; filled slots feel like progress.

**Ongoing — The Granary Bottleneck:**

Your storage is full. Three choices: haul back the last batch of processed planks (worth building the wall), carry more raw logs from the forest (essential for the upcoming upgrade), or take the fish to your NPC cook before it spoils. You can only make one trip. The slots are full.

This is the tension that drives every meaningful decision after automation is established. Capacity is a felt constraint, not a number on a tooltip. The player should feel the weight of a full granary—the pleasant problem of "I have too much, but not the right things." Optimization over expansion means you solve this not by building more storage, but by making better decisions about what flows through your one bottleneck.

**The Unifying Thread:** Storage is the village's single point of truth and constraint. Everything flows through it, everything pauses at it, everything is measured by it. When an NPC finally starts pulling wood from storage automatically, you should feel genuine relief—not "cool, a new mechanic," but "I don't have to walk those eight tiles anymore." The automation is valuable because the manual labor was real.

## Detailed Design

### Core Rules

**1. Inventory Container Data Model**

The Inventory/Storage System manages `InventoryContainer` instances — each with a fixed capacity and an array of slots:

```
InventoryContainer {
    container_id: String             // unique identifier
    name: String                     // display name (e.g., "Main Storage")
    capacity: int                    // max number of slots (fixed at creation)
    slots: Array[InventorySlot]      // fixed-size array, size == capacity
}

InventorySlot {
    slot_index: int                  // 0-based position (0 to capacity-1)
    resource_id: String?             // null = empty slot
    quantity: int                    // 1..stack_limit (from Resource System)
    current_charge: float            // total remaining charge for ALL units in this slot
                                     // fully stocked: current_charge == quantity * max_charge
                                     // slot is cleared when current_charge <= 0
}
```

Each `InventorySlot` holds one type of resource. The `stack_limit` and `max_charge` come from the Resource System registry — the Inventory System never defines resource attributes itself, only consumes them. When depositing N new items, `current_charge` increases by `N × max_charge`. When a recipe consumes a fractional `charge_cost`, `current_charge` is decremented by that amount. Stacked items contribute their charge additively — three units of wood (max_charge 100 each) provide 300 total charge. The slot is emptied (resource_id set to null) only when `current_charge <= 0`.

**2. Storage Containers (Vertical Slice)**

For the Vertical Slice, there are two container types:

| Container | Build Cost | Capacity | Upgradable? |
|-----------|------------|----------|-------------|
| **Storage Area** | None (free, placeable) | 50 slots | No |
| **Storage Building** | 8 Wood + 2 Stone | 150 slots | No |

The **Storage Area** is a freely placeable marker with 50 empty slots. The player places it on any valid tile before any other actions.

The **Storage Building** is a buildable structure placed on top of an existing Storage Area. It costs 8 Wood + 2 Stone, takes 120 ticks to build, and expands the Storage Area to 150 total capacity. There are no further upgrades — to increase capacity beyond 150 slots, the player places additional Storage Areas or Buildings.

**3. Tile-Drop Resources**

When the player performs a manual harvest action (chop a tree, pick berries, mine stone, search a meadow), the yielded resource **drops on the tile of the action**. It does NOT go into a personal inventory. The resource persists on the tile as a visible pile.

Tile-drop resources exist in the following states:

| State | Description | Transition |
|-------|-------------|------------|
| **DROPPED** | Resource pile sits on a tile, visible | Manual harvest action (Manual Labor System) completes |
| **IN_TRANSIT** | Player is carrying resource toward storage | Player initiates transport (selects source tile + target storage) |
| **STORED** | Resource deposited into a slot in an InventoryContainer | Transport reaches target storage and succeeds |
| **LOST** | Resource removed from tile without being collected | Grid System clears the tile (building placed on the tile), or explicit player drop |

**4. Transport Mechanics**

Transport is a player-initiated action that moves a tile-drop resource to a storage container. It is a two-step interaction:

1. **Select source:** Player clicks a tile containing a dropped resource. The system shows a preview: "[Resource] — Transport to [nearest storage]: [N] Energy, [M] Ticks".
2. **Select destination:** Player clicks a target Storage Area. Transport begins.

**Transport costs** are deducted when the transport completes (at the player's arrival at the Storage Area):

`energy_cost = 2 * quantity + distance_to_storage`

`time_cost = 5 * distance_to_storage` (in Ticks)

**Variables:**
- `quantity`: number of items being transported
- `distance_to_storage`: Manhattan distance (|x1-x2| + |y1-y2|) from the resource tile to the nearest tile of the target Storage Area. If impassable terrain blocks the direct Manhattan path, the actual path may be longer — transport uses the Manhattan distance for cost calculation regardless of path obstructions (player pathfinding handles the actual route).
- `2`: base energy cost per item (pickup effort, default value — tuning knob in Formula 1 table)
- `1`: energy cost per tile of travel distance (default value — tuning knob in Formula 1 table)
- `5`: ticks per tile of travel distance (default value — tuning knob in Formula 2 table)

**Example:** Transport 5 wood from a tile 8 tiles away to storage:
`energy_cost = 2 * 5 + 8 = 18 Energy`
`time_cost = 5 * 8 = 40 Ticks`

**Movement model:** The player character physically walks from their current position to the storage tile, carrying the items. The player is occupied during transport — cannot perform other actions. Transport is NOT interruptible during the Vertical Slice (once started, it completes or is cancelled entirely). If the player cancels, the items return to the source tile, no energy is deducted.

**If energy is insufficient when transport completes:** The transport fails, items return to source tile, no energy is deducted.

**5. Storage Operations**

**Deposit (transport complete):** When a transport completes, the system allocates slots in the target container following the **first-fit stacking** algorithm:
1. Scan slots from index 0 upward.
2. If a slot already holds the same `resource_id` and `quantity + current_slot_quantity <= stack_limit`: add to existing slot.
3. If a slot is empty (`resource_id == null`): place resource there (or extend existing stack if partial).
4. If no slot can accommodate the full quantity: split across slots (respecting `stack_limit` per slot).
5. If no slots remain: deposit fails, items return to source tile.

**Withdraw (building consumption):** Buildings pull inputs from storage at the **start of a production cycle**. The Production System queries the storage for the required resource ID and quantity, and deducts from slots using the **first-fit** algorithm (lowest slot index wins). If insufficient quantity is available in storage, the building receives no inputs and does not produce.

**Day-transition consumption (Hunger System):** At day transition, the Hunger System deducts food from ALL storage containers on the map. Scan order: all containers by container_id, all slots by slot_index (for deterministic collection). Deduction priority: lowest-quantity slot first (minimize waste — smaller stacks are consumed before larger ones), with slot_index as tiebreaker for equal quantities. If total food across all containers is insufficient for the required amount, apply the hunger debuff (-50% productivity to all player and NPC actions).

**6. Carried Items vs. Storage**

The player has **no carry-inventory**. Carried items exist in the `IN_TRANSIT` state only — they are not stored in a persistent container. When the player is walking back to storage, the item is "on the player" but not in any slot. This means:

- The player can transport any number of items at once (limited only by energy budget).
- Carried items do not occupy storage slots.
- Carried items are visible as the player character sprite carrying a resource icon.

**7. Placement Validation**

The Storage Area is placed through the Building System's placement validation pipeline. The Grid System's `validate_placement()` is called:

- The Storage Area occupies 1 tile.
- It can be placed on `EMPTY` terrain or `GRASS` terrain.
- It CANNOT be placed on `IMPASSABLE` terrain.
- If placed on a `TREE` or `BERRY` resource tile, the resource is cleared (consistent with building placement rules — the Storage Area "clears" the land). If placed on a `STONE` or `IRON` resource tile, placement is blocked (these are treated as impassable for placement purposes — enforced by Grid System's `validate_placement()`).
- If a tile already has a Storage Area, another cannot be placed on the same tile.

After placement succeeds, the Inventory/Storage System creates a new `InventoryContainer` with `capacity = 50` and an array of 50 empty slots.

**8. Storage Building Placement**

A Storage Building is placed via the Building System. Placement constraints:

- Must be placed on an existing Storage Area tile (same tile — the building is built ON the storage area).
- Costs 8 Wood + 2 Stone (deducted from the player's carried items if available; if not, the build is blocked with tooltip: "Not enough resources in reach — transport materials to the storage area first").
- Takes 120 Ticks to build. During this time, the Storage Area retains its 50-slot capacity (the building is under construction, not yet operational).
- Upon completion, the Storage Area's capacity increases to 150.

**9. Invariants (Non-Negotiable Rules)**

- **Buildings NEVER pull from tiles or player inventory.** All inputs come exclusively from storage containers. This is enforced at the Production System level — it can only query `InventorySystem.get_resource(resource_id, container_id)`.
- **Storage capacity is a hard ceiling.** No resource can be stored beyond the container's capacity. Overflow resources remain on-tile or the deposit action fails.
- **Stack limits are enforced by the Resource System.** The Inventory System reads `stack_limit` from the resource registry and never allows a slot to exceed it.
- **Charge state is persistent across storage operations.** Moving an item in/out of storage does not reset `current_charge`. A slot's charge is only modified by recipe consumption or by depositing additional items.
- **Multiple independent Storage Areas are allowed.** Each is a separate `InventoryContainer`. Buildings pull from a specific container (designated at build time — the player assigns which storage feeds which building group).

### States and Transitions

**Tile-Drop Resource States:**

| State | Description | Transition Trigger |
|-------|-------------|-------------------|
| **DROPPED** | Resource pile sits on a tile, visible to player | Manual harvest action (Manual Labor System) completes |
| **IN_TRANSIT** | Player is carrying resource toward storage | Player initiates transport (selects source tile + target storage) |
| **STORED** | Resource deposited into a slot in an InventoryContainer | Transport reaches target storage and succeeds |
| **LOST** | Resource removed from tile without being collected | Grid System clears the tile (building placed on the tile), or explicit player drop |

**Inventory Container States:**

| State | Condition | Transition Trigger |
|-------|-----------|-------------------|
| **EMPTY** | 0 slots occupied | Container created (Storage Area placed) |
| **PARTIAL** | 0 < occupied_slots < capacity | Deposit or withdraw operation |
| **FULL** | occupied_slots == capacity, no empty slots | Deposit fails (all slots occupied and full) |
| **DEMOISHED** | Container removed from map | Storage Building demolished, capacity reverts to base |

**Container Capacity Reference:**

| Container Type | Capacity | Cost |
|----------------|----------|------|
| Storage Area (no building) | 50 | None (free) |
| Storage Area + Storage Building | 150 | 8 Wood + 2 Stone, 120 Ticks |

To increase total capacity beyond 150 slots, place additional Storage Areas or Storage Buildings elsewhere on the map.

**Energy State (Player):**

| State | Condition | Effect |
|-------|-----------|--------|
| **ACTIVE** | energy > 0 | Normal operations |
| **DEPLETED** | energy == 0 | All manual actions cost 2x Ticks, 50% output reduction |

The Energy state is managed by the Player Character System, not the Inventory System. However, the Inventory System consumes Energy as a precondition for transport actions.

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Resource System** | Reads resource definitions (stack_limit, max_charge, category) | Resource System → Inventory: `get_resource(id)` | Inventory uses schema to validate slot operations. Never modifies resource definitions. |
| **Manual Labor** | Yields tile-drop resources on harvest | Manual Labor → Grid: resource appears on tile | Manual Labor does NOT call Inventory directly. Resource spawn on tile is a Grid System event that Inventory observes. |
| **Player Character** | Initiates transport, spends Energy and Ticks | Player Character → Inventory: `start_transport(source_tile, target_storage, quantity)` | Player Character receives `on_transport_complete` signal. Energy/Ticks deducted on arrival. |
| **Building System** | Build costs consume resources; buildings pull from storage | Building System → Inventory: `try_consume(container_id, resource_id, quantity)` | Inventory returns success/failure. Building System shows green/red build preview based on availability. |
| **Building System** (production) | Checks input availability for production cycle start | Building System → Inventory: `get_resource(container_id, resource_id)` | Inventory returns available quantity. Building System's input buffer is stocked by carrier (see Transportation System). The building no longer calls `try_consume()` directly at cycle start — the carrier delivers inputs to the building's input buffer first. |
| **Transportation System** | Carrier NPCs withdraw inputs from storage to deliver to buildings; deposit output collected from buildings into storage | Transport → Inventory: `try_consume(container_id, resource_id, quantity)` (input pickup) and `try_deposit(container_id, resource_id, quantity)` (output delivery) | All production-related storage withdrawals and deposits now flow through carrier NPCs, not the Building System directly. Deposit quantity is always `base_output` — distance does NOT reduce deposited amounts. |
| **Hunger System** | Daily consumption from all containers | Hunger → Inventory: `consume_food(global_food_quantity)` | System scans all containers, deducts from lowest-quantity slots first. Returns actual consumed amount. |
| **Tick System** | Advances transport time costs | Tick System → Inventory: `advance_tick()` | Inventory tracks in-transit items and decrements remaining travel ticks. |
| **Grid System** | Placement validation, tile resource awareness | Grid ↔ Inventory: `validate_placement(x, y)`, `get_tile_drop(x, y)` | Inventory queries Grid for tile drops and placement validity. |
| **HUD/UI** | Displays storage contents and capacity | Inventory → HUD: `get_storage_contents(container_id)`, `get_capacity(container_id)` | HUD polls for display. Shows slot grid, capacity bar, per-type breakdown. |

## Formulas

### 1. Transport Energy Cost

`energy_cost = (2 × quantity) + (1 × distance_to_storage)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| quantity | q | int | 0–1000 | Number of items being transported |
| distance_to_storage | d | int | 0–600 | Manhattan distance from source tile to target storage tile on the Grid |
| 2 | — | float | 2.0 (tuning knob) | Energy cost per item (pickup and carry effort) |
| 1 | — | float | 1.0 (tuning knob) | Energy cost per tile of travel distance |
| energy_cost | E | float | 0.0–1200.0 | Total energy required to complete transport |

**Output Range:** [0.0, 1200.0] — bounded by max stack (1000) × 2 + max plausible distance (600)

**Example (GDD example, 5 wood, 8 tiles away):**
```
q = 5, d = 8
E = (2 × 5) + (1 × 8) = 10 + 8 = 18 Energy
```

**Player budget context:** Starting energy pool is 100. A single transport of 5 wood at 8 tiles costs 18% of total energy. This is the core tension: each trip is a meaningful fraction of the player's daily capacity, forcing tradeoffs between distance, quantity, and urgency.

**Insufficient energy handling:** If `E > energy_remaining`, transport fails entirely. Items return to source tile. No partial transport, no energy deducted. The HUD/tooltip preview (step 1 of transport) shows the cost before the player commits, enabling informed decisions.

**Boundary value analysis:**

| Scenario | q | d | E | Degenerate? |
|----------|---|---|---|-------------|
| Nothing to transport | 0 | 8 | 0 | No — early-exit guard (nothing to select) |
| Adjacent drop, 1 item | 1 | 0 | 2 | No — minimum cost is 2 |
| 1 item, 1 tile away | 1 | 1 | 3 | No — healthy minimum |
| Player at storage (d=0) | 5 | 0 | 10 | No — pickup-only cost |
| Max stack, far away | 99 | 600 | 798 | No — cost exceeds 100-energy pool → transport fails (intended) |
| Max energy pool check | — | — | 100 | If E ≤ 100 and E = energy_remaining, transport succeeds (exactly enough) |
| One over max pool | — | — | 101 | If E = 101, transport fails. This is the intended design — the energy pool is a hard constraint. |

**Degeneracy verdict:** No mathematical degenerate outputs (no negative values, no division-by-zero, no overflow within int32). The formula is safe at all boundaries. The "danger" is intentional: high costs will exceed the 100-energy pool, causing transport failures that drive gameplay decisions. The player fantasy states "nearly a tenth of your starting pool" for a typical trip — the formula delivers this at q=4, d=8 (E=16, 16% of pool), which is the intended feel zone.

---

### 2. Transport Time Cost

`time_cost = 5 × distance_to_storage`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| distance_to_storage | d | int | 0–600 | Manhattan distance from source tile to target storage tile |
| 5 | — | int | 5 (tuning knob) | Ticks per tile of travel distance |
| time_cost | T | int | 0–3000 | Total time cost in ticks |

**Output Range:** [0, 3000] ticks — bounded by max plausible distance (600 tiles) × 5 ticks/tile

**Example (same scenario, 8 tiles away):**
```
d = 8
T = 5 × 8 = 40 Ticks
At 1x speed: 40 ticks = 4 real seconds of travel time
```

**Time vs. energy relationship:** Energy and time are **decoupled** — energy depends on quantity, time does not. A single item at 60 tiles costs 128 energy (E = 2×1 + 60) and 300 ticks (T = 5×60). 50 items at the same distance cost 128 energy and 300 ticks. This asymmetry is the core strategic depth: bulk transport is time-efficient but energy-expensive. The player optimizes quantity vs. distance to maximize items-per-energy.

**Degeneracy check:** `q = 0` is irrelevant (no transport initiated). `d = 0` yields T = 0 (item already at storage — no transport needed). No division operations exist. No degenerate outputs at any boundary.

---

### 3. First-Fit Slot Allocation (Deposit)

This is an algorithmic formula — it defines a deterministic slot selection procedure, not a scalar equation.

**Algorithm: `allocate_slots(container, resource_id, quantity, stack_limit, max_charge)`**

**Preconditions:**
- `container` exists and is not DEMOLISHED
- `quantity > 0`
- `resource_id` matches a valid resource in the Resource System registry
- `stack_limit` is read from `get_resource(resource_id).stack_limit`
- `max_charge` is read from `get_resource(resource_id).max_charge` (default 100.0)

**Procedure:**

```
remaining = quantity
allocated = {}  // set of (container_id, slot_index, quantity) pairs
container = get_container(target_container_id)

// Phase 1: Extend existing slots (same resource_id)
for slot_index from 0 to container.capacity - 1:
    slot = container.slots[slot_index]
    if slot.resource_id == resource_id and slot.quantity < stack_limit:
        fill_space = stack_limit - slot.quantity
        add_amount = min(remaining, fill_space)
        slot.quantity += add_amount
        slot.current_charge += add_amount * max_charge  // new items start fully charged
        remaining -= add_amount
        allocated.add((container.container_id, slot_index, add_amount))
        if remaining == 0:
            return SUCCESS(allocated)

// Phase 2: Fill empty slots
while remaining > 0:
    found_empty = false
    for slot_index from 0 to container.capacity - 1:
        slot = container.slots[slot_index]
        if slot.resource_id == null:
            fill_amount = min(remaining, stack_limit)
            slot.resource_id = resource_id
            slot.quantity = fill_amount
            slot.current_charge = fill_amount * max_charge  // initialize fully charged
            remaining -= fill_amount
            allocated.add((container.container_id, slot_index, fill_amount))
            found_empty = true
            break  // restart scan from index 0 for next portion

    if not found_empty and remaining > 0:
        return FAILURE("No slots remaining — container is full")

if remaining == 0:
    return SUCCESS(allocated)
else:
    return FAILURE("No slots remaining — container is full")
```

**Postconditions:**
- `allocated` describes every slot modification performed
- Total added quantity across all slots equals the original `quantity` (on success)
- No slot exceeds `stack_limit`
- No slot holds mixed resource types
- Slot indices are strictly ascending (first-fit ordering preserved)
- Newly deposited items are always fully charged (`current_charge` increases by `quantity × max_charge`)

**Output:** `{status: SUCCESS|FAILURE, allocated: Array[slot_modification], remaining: int}`

**Degeneracy check:**

| Scenario | Expected behavior | Degenerate? |
|----------|-------------------|-------------|
| quantity = 0 | Precondition guard — return SUCCESS(empty), no allocations | No |
| container.capacity = 0 | Phase 1 and 2 loops are empty iterations → returns FAILURE immediately | No — failure is correct (zero-capacity container can hold nothing) |
| stack_limit = 1 | Each empty slot holds exactly 1 item. If quantity = 99, 99 empty slots needed. | No — works correctly, allocates 99 separate slots |
| stack_limit ≥ quantity (single slot fits) | Phase 1 misses (no matching slot), Phase 2 fills first empty slot completely. | No |
| Exact stack fit (e.g., quantity = stack_limit = 99) | Phase 2 fills one slot to exactly stack_limit. remaining = 0. SUCCESS. | No |
| Overflow split (quantity = 150, stack_limit = 99) | Slot A: 99, Slot B: 51. SUCCESS across 2 slots. | No |
| Container full, partial existing slot | Phase 1: no fill space. Phase 2: no empty slots. FAILURE, items return to source. | No |

**Degeneracy verdict:** No mathematical degenerate outputs. The algorithm is entirely discrete (integers, comparisons, additions). No division, no exponentiation, no edge case produces undefined behavior. The FAILURE return provides a clear, testable signal for the calling system.

---

### 4. Effective Storage Capacity

Storage capacity is determined solely by container type. There are no upgrades.

| Container Type | effective_capacity |
|----------------|-------------------|
| Storage Area (no building) | 50 |
| Storage Area + Storage Building | 150 |

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| effective_capacity | C | int | {50, 150} | Total usable slots in the container |

**Rules:**
- Storage Area without a building: C = 50 (free, placed immediately)
- Storage Area with a Storage Building (build complete): C = 150
- No upgrades exist. To expand storage, place additional containers.

**Degeneracy check:**

| Scenario | C | Degenerate? |
|----------|---|-------------|
| No building | 50 | No |
| Storage Building | 150 | No |
| Capacity 0 | — | Not possible: minimum C = 50 (free Storage Area). |

**Degeneracy verdict:** No degenerate outputs. Minimum capacity is 50 (free Storage Area), ensuring storage is always functional.

---

### 5. Hunger Consumption Priority

This is an algorithmic formula — a deterministic deduction procedure used by the Hunger System at each day transition.

**Algorithm: `consume_food(daily_food_requirement)`**

**Preconditions:**
- Called on `day_transition` from Tick System
- `daily_food_requirement` = sum of all NPC daily food costs (from Hunger System GDD). The player does NOT consume food — only NPCs.

**Procedure:**

```
total_to_consume = daily_food_requirement  // in units (e.g. 3 berries = 3 units)
total_consumed = 0.0  // tracked as charge
slots_affected = 0

// Phase 1: Collect all food-eligible slots from all containers
food_slots = []
containers = get_all_containers_on_map()  // sorted by container_id for determinism

for container_id in containers:
    container = get_container(container_id)
    for slot_index from 0 to container.capacity - 1:
        slot = container.slots[slot_index]
        if slot.resource_id == null:
            continue
        resource_def = get_resource(slot.resource_id)
        if resource_def.category == "consumable":
            food_slots.append({
                container_id: container_id,
                slot_index: slot_index,
                current_charge: slot.current_charge,
                max_charge: resource_def.max_charge,
                resource_id: slot.resource_id
            })

// Phase 2: Sort by current_charge ascending, then slot_index ascending as tiebreaker
// This ensures smallest (least charged) stacks are consumed first (minimize waste).
sort food_slots by: (current_charge ASC, slot_index ASC)

// Phase 3: Deduct charge from sorted slots
// Each unit consumed = max_charge of that resource
charge_still_needed = total_to_consume * food_slots[0].max_charge  // simplified: assume uniform food
// (In practice, iterate and convert units→charge per resource type)

for entry in food_slots:
    if charge_still_needed <= 0:
        break

    container = get_container(entry.container_id)
    slot = container.slots[entry.slot_index]
    resource_def = get_resource(slot.resource_id)

    consume_charge = min(charge_still_needed, slot.current_charge)
    slot.current_charge -= consume_charge
    total_consumed += consume_charge
    charge_still_needed -= consume_charge
    slots_affected += 1

    if slot.current_charge <= 0:
        slot.resource_id = null
        slot.quantity = 0
        slot.current_charge = 0.0

if charge_still_needed > 0:
    apply_hunger_debuff()  // -50% productivity to all player and NPC actions
    remaining_deficit = charge_still_needed
else:
    remaining_deficit = 0

return {
    total_consumed: total_consumed,
    slots_affected: slots_affected,
    remaining_deficit: remaining_deficit,
    hunger_debuff_applied: (remaining_deficit > 0)
}
```

**Postconditions:**
- `total_consumed` ≤ `daily_food_requirement` (may be less if insufficient food)
- Food is consumed from lowest-quantity slots first (minimize waste)
- Empty slots (quantity = 0) are immediately cleared to `resource_id = null`
- `hunger_debuff_applied` is true if and only if total food across all containers was insufficient

**Why "lowest charge first" (not FIFO):** This consumes the least-charged (smallest) stacks before fully-charged (larger) ones, reducing the total number of occupied slots post-consumption. If Slot A holds 30.0 charge of berries and Slot B holds 990.0 charge, Slot A is emptied first. This keeps the inventory cleaner (fewer occupied slots remain) and delays the "near-full" bottleneck state. Deterministic tiebreaking: when two slots have the same charge, the lower slot index wins. Primary sort key is slot current_charge (ascending), secondary sort key is slot index (ascending).

**Example (2 containers, need 10 food):**
```
Container "Main":
  Slot 0: berries × 3
  Slot 1: bread × 50

Container "Backup":
  Slot 0: berries × 5
  Slot 1: planks × 20 (not food — skip)

Scan order: Container "Backup" first (alphabetical by container_id), then "Main"
  Backup Slot 0: berries × 5, consume min(10, 5) = 5 → remaining = 5, slots_affected = 1
  Main Slot 0: berries × 3, consume min(5, 3) = 3 → remaining = 2, slots_affected = 2
  Main Slot 1: bread × 50, consume min(2, 50) = 2 → remaining = 0, slots_affected = 3

Result: consumed 10, 3 slots affected, no hunger debuff.
Main Slot 1: bread × 48 (was 50, now 48)
```

**Example (insufficient food):**
```
All containers combined: 22 berries across all slots
daily_food_requirement = 30

Scan all containers → total food found = 22
remaining_deficit = 30 - 22 = 8
hunger_debuff = applied (-50% productivity)

Result: consumed 22, 5 slots affected, remaining_deficit = 8, hunger_debuff_applied = true
```

**Degeneracy check:**

| Scenario | Expected behavior | Degenerate? |
|----------|-------------------|-------------|
| daily_food_requirement = 0 (no NPCs, player only, 0 food cost) | Loop exits immediately. consumed = 0, no debuff. | No |
| No containers exist on map | Loop over containers is empty. total_consumed = 0. deficit = requirement. Debuff applied. | No — correct behavior (no food available = hunger) |
| No food resources in any container | All slots skipped (category != "consumable"). Same as empty containers. | No |
| All slots are food but total < requirement | Consumes everything, debuff applied. | No |
| quantity = 0 slot encountered | Skipped (resource_id is null after consumption from previous step). | No |
| Simultaneous day transitions (edge case) | Only fires once per day transition (tick_count mod 1000 reset). No double-consumption. | No |

**Degeneracy verdict:** No mathematical degenerate outputs. All operations are integer subtraction and min(). No division, no zero-division risk. The algorithm is fully deterministic and idempotent (each day processes independently). The hunger debuff provides a clear fail-safe when food runs out.

---

### 6. Slot Utilization Ratio

`(occupied_slots / capacity) × 100`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| occupied_slots | o | int | 0–2147483647 | Number of non-empty slots (resource_id != null) in the container |
| capacity | C | int | 50–2147483647 | Total slot count of the container (from Formula 4) |
| 100 | — | float | 100.0 | Scaling factor for percentage |
| utilization | U | float | 0.0–100.0 | Percentage of slots currently occupied |

**Output Range:** [0.0, 100.0] %

**Example (150-slot container, 67 occupied):**
```
o = 67, C = 150
U = (67 / 150) × 100 = 44.67%
```

**Tuning use — "near-full" warning threshold:** The HUD uses this ratio to provide visual feedback about storage pressure. The granary bottleneck feeling relies on the player noticing capacity limits *before* hitting zero:

| Utilization | HUD feedback | Gameplay purpose |
|-------------|-------------|-----------------|
| 0–49% | Normal display | Comfortable — no action needed |
| 50–74% | Subtle color shift (e.g., bar tints amber) | Awareness — planning trip |
| 75–89% | Warning icon + "75% full" text | Caution — plan another storage |
| 90–99% | Red border + "90% full" + pulsing | Urgency — deposit or expand now |
| 100% | "Storage Full" overlay, deposit blocked | Critical — bottleneck active |

These thresholds are **tuning knobs** (detailed in the Tuning Knobs section). They are not hard-coded in the formula — the formula is pure math. The thresholds live in the UI configuration.

**Degeneracy check:**

| Scenario | o | C | U | Degenerate? |
|----------|---|---|---|-------------|
| Fresh Storage Area | 0 | 50 | 0.0 | No — 0 / 50 = 0.0% |
| Half full | 25 | 50 | 50.0 | No |
| Full | 50 | 50 | 100.0 | No |
| Capacity 0 (theoretical) | 0 | 0 | **DIVISION BY ZERO** | **DEGENERATE — must be handled** |
| Corrupted save: o > C | 60 | 50 | 120.0 | No — >100% is valid error signal (data corruption) |

**Degeneracy verdict:** Division by zero at C = 0 is the only degenerate case. **Guard:** If C = 0, return U = 0.0 (empty report). In practice, C is always ≥ 50 (minimum free Storage Area), so C = 0 is unreachable in normal gameplay. However, corrupted saves or debugging test states could produce this. The guard is a simple pre-condition check: `if C == 0 return 0.0`.

> **Note:** The formula is referenced by HUD UI (for capacity bar), Building System (to show build affordability — "add storage to fit these materials"), and the Player Character System (energy budget planning — knowing storage remaining capacity affects how many trips to plan).

---

### Formula Cross-References

These formulas are **referenced by other systems** and must be treated as stable interfaces:

| Formula | Referenced By | How It's Used |
|---------|--------------|---------------|
| Transport Energy Cost | Player Character System | Checks energy pool before allowing transport; shows preview cost in HUD |
| Transport Energy Cost | Manual Labor System | Harvest action may include optional transport cost in total tick/energy budget |
| Transport Time Cost | Tick System | In-transit items decrement remaining ticks each frame via `ticks_advanced` |
| Transport Time Cost | HUD UI | Shows remaining travel time in ticks (e.g., "40 ticks remaining") |
| First-Fit Slot Allocation | Production System | When transport completes, production system observes slots change |
| First-Fit Slot Allocation | Building System | Build preview validates available slots match material needs |
| First-Fit Slot Allocation | Save/Load System | Slot state must be serialized in deterministic index order |
| Effective Storage Capacity | Building System | Build preview checks: "This upgrade adds +100 slots" |
| Effective Storage Capacity | HUD UI | Capacity bar uses C for the denominator |
| Hunger Consumption Priority | Hunger System | Primary consumer of this formula; fires on `day_transition` |
| Hunger Consumption Priority | Day Overview UI | Displays daily food consumption summary (slots affected, debuff triggered) |
| Hunger Consumption Priority | Save/Load System | Slot quantities must be serialized to preserve post-consumption state |
| Slot Utilization Ratio | HUD UI | Drives capacity bar fill level and warning overlays |
| Slot Utilization Ratio | Building System | Build menu shows "Storage at X% — consider upgrading" suggestion |

## Edge Cases

Edge cases are organized by severity. HIGH cases are mandatory for implementation. MEDIUM cases are included in the Vertical Slice scope. LOW cases are noted for developer awareness and future iterations.

### HIGH Severity

**EC-H1: Hunger Death Spiral**

- **Scenario:** Hunger consumes the last food at day transition. Hunger debuff (-50% productivity) activates. Player cannot efficiently gather food. Player cannot recover.
- **Handling:** The Hunger System (separate GDD) must define a minimum auto-regeneration rate when energy is 0 (e.g., +1 energy per 60 seconds real-time). This is a **Hunger System responsibility**, not an Inventory System responsibility. The Inventory System's only role is to return `remaining_deficit > 0` from the `consume_food` algorithm, signaling that the debuff should be applied. The Inventory System does NOT prevent starvation — it reports it.
- **Out of scope:** Guest system, fallback food sources, auto-foraging. These are Hunger System features.

**EC-H2: Storage Building Demolished — Container Persistence**

- **Scenario:** Player demolishes a Storage Building. The container's capacity was 250 (150 base + 2 upgrades). What happens to stored items and capacity?
- **Handling:**
  1. Container persists. The `InventoryContainer` is not deleted when its building is demolished.
  2. Capacity reverts to 50 (Storage Area base). If `occupied_slots > 50`, the excess items remain in their slots but the container is now over its capacity ceiling. This is a temporary state.
  3. Player must place a new Storage Building on the area to restore elevated capacity. The new building starts at `n = 0` (150 slots) — upgrade levels are NOT preserved (the demolished building's upgrades are lost).
  4. **No resource refund** on demolition. 8 Wood + 2 Stone are spent and not returned.
- **Rationale:** The Storage Area (50-slot container) is the persistent data structure; the Storage Building is a mutable modifier on that container. Demolishing the building removes the modifier but not the container.

**EC-H3: Transport IN_TRANSIT During Map Change / Save-Load**

- **Scenario:** Player is IN_TRANSIT when the game is saved and reloaded, or when a map transition occurs.
- **Handling:**
  1. `IN_TRANSIT` state is serialized in the Save/Load System: source tile coordinates, target container ID, quantity, remaining travel ticks, and energy already committed.
  2. On reload: if source tile still exists and target container still exists → transport resumes from remaining ticks. If source tile no longer exists → items transition to LOST (not returned, consistent with non-interruptible rule). If target container no longer exists → items transition to LOST.
  3. Energy is NOT refunded on reload (non-interruptible transport).
- **Out of scope:** Multiplayer race conditions (see EC-M4).

**EC-H4: Carrier Output Deposit Blocked by Full Container**

- **Scenario:** A carrier NPC arrives at the storage container to deposit output collected from a production building (via `BuildingRegistry.collect_output()`). The container is at capacity. `try_deposit()` returns FAILURE.
- **Handling:**
  1. Deposit attempt fails (First-Fit algorithm returns FAILURE).
  2. The carrier NPC enters the WAITING state — it holds the output and waits for storage capacity to free up. When `storage_changed` fires (capacity opens), the carrier retries the deposit.
  3. The production building itself is not directly stalled by a full container — it can continue producing if its output buffer has space. However, if the carrier never returns to collect and the output buffer fills, the building enters STALLED state (handled by Building System EC-H2).
  4. Output is NEVER destroyed — the carrier holds it indefinitely until deposit succeeds.
- **Design note — no longer Building System's concern:** Under the Transportation System model, the Building System no longer calls `deposit_output()` directly. Deposits are exclusively initiated by carrier NPCs. This eliminates the previous "building holds output internally on STALLED" complexity — output is now on the carrier or in the building's output buffer, not in limbo between the two systems.

**EC-H5: Concurrent Storage Modifications — Ordering Guarantee**

- **Scenario:** Multiple systems attempt to modify the same container in the same tick cycle:
  - Case A: Hunger consumes food + building pulls food from the same slot.
  - Case B: Transport completes deposit + building pulls from the same slot.
  - Case C: Two buildings pull from the same container simultaneously.
- **Handling:** All container modifications are processed in a **deterministic order** at the start of each tick cycle:
  1. **Hunger consumption** (highest priority — survival). Runs first. Consumes from all containers globally.
  2. **Building withdrawals** (second priority). Processed in `container_id` ascending order, then `building_id` ascending. Each building pulls as much as available. Subsequent buildings get the remainder.
  3. **Transport deposits** (third priority). Processed in `remaining_ticks = 0` order (those arriving first). If deposit fails due to capacity filled by steps 1-2, items return to source tile (LOST if no source tile exists).
  4. **Day-transition events** (last priority). Triggered after all modifications are complete.
- **Rationale:** This ordering is enforced by the Tick System's signal dispatch order. `on_hunger_consume` fires before `on_production_start` before `on_transport_arrive` before `day_transition`. No race conditions possible.

### MEDIUM Severity

**EC-M1: Resource Tile Cleared During IN_TRANSIT**

- **Scenario:** Player initiates transport from Tile X. Before transport completes, the Grid System clears Tile X (a building is placed on the tile, or a manual harvest removes the last instance). The source tile no longer contains the items.
- **Handling:** At transport completion, verify source tile still contains the expected resource. If not → items transition to **LOST**. No energy refund. No item placement. The transport simply ends — the player arrives at storage with empty hands.
- **Design note:** This is harsh but intentional — the player committed to the transport by selecting source and destination. Canceling before completion returns items (Rule 4). Failing after completion does not.

**EC-M2: Storage Area Placement Clears Resource Tile**

- **Scenario:** Player places a Storage Area on a tile containing a resource node (TREE, BERRY). Rule 7 states the resource is cleared.
- **Handling:**
  1. Resource is permanently destroyed. No refund, no salvage.
  2. **UI requirement:** The Building System's placement preview (red/green check) must show a warning indicator on the tile if it contains a clearable resource. The tooltip text reads: "This will clear the [resource] on this tile."
  3. Non-clearable resources (STONE, IRON) block placement entirely — they are treated as IMPASSABLE for placement purposes. This is enforced by Grid System's `validate_placement()`.
- **Rationale:** Storage Areas "clear the land" — consistent with building placement rules. The player makes a deliberate choice to clear land for storage.

**EC-M3: IN_TRANSIT Items and Container Capacity Reservation**

- **Scenario:** Container is at 149/150 capacity. Transport carrying 1 item is IN_TRANSIT. Simultaneously, a building attempts to deposit 2 items. The container can accept 1 item (1 slot free), but not 2.
- **Handling:**
  1. **IN_TRANSIT items do NOT reserve capacity at initiation.** Capacity is reserved only at **transport completion** (when items transition from IN_TRANSIT to STORED).
  2. At completion time, the deposit is evaluated against current capacity. If the building's deposit filled the last slot during transit, the transport deposit fails. Items return to source tile (or LOST if source tile gone — see EC-M1).
  3. This means a transport can arrive at an already-full container. The risk is acceptable because transport time gives the player a window to check storage status. The HUD shows capacity status in real-time (UI Requirements section).
- **Design tradeoff:** Reserving capacity at initiation would require tracking pending reservations, adding complexity. Allowing it at completion keeps the model simple and adds strategic tension (player must time trips).

**EC-M4: Multiplayer Tile-Drop Race Condition (Out of Scope for VS, Defined for Integrity)**

- **Scenario:** Two players click the same DROPPED tile simultaneously. Both initiate transport. Both have sufficient energy.
- **Handling (for future multiplayer implementation):**
  1. Server-authoritative claim: first transport initiation wins (server-side timestamp with millisecond precision).
  2. Loser's transport is cancelled. Items remain DROPPED on the tile. Energy refunded to the loser.
  3. If both initiate within the same tick → the player with the lower player_id wins (deterministic tiebreaker).
- **Vertical Slice:** Single-player only. This edge case is documented for architectural integrity — the data model (single source tile, single IN_TRANSIT transition) supports multiplayer without refactoring.

**EC-M5: Building References Orphaned When Container Removed**

- **Scenario:** A Storage Building (or any building that depends on storage) references Container X. Container X is removed (Storage Area demolished — see EC-H2). The building still exists but references a non-existent container.
- **Handling:**
  1. When a container is removed, all building references to it are cleared.
  2. Affected buildings enter a "no storage" state: they pause production and show a visual warning (red indicator).
  3. Player must assign a new storage area via the building's UI (select which Storage Area feeds this building).
  4. If no storage is assigned after 24 hours (in-game time), the building enters a "broken" state and does not produce until storage is reassigned.
- **Rationale:** Buildings need storage to function. An orphaned reference must be explicitly resolved by the player, not auto-fixed (which could silently pull from the wrong storage).

**EC-M6: Transport Destination Container Destroyed Mid-Transit**

- **Scenario:** Player initiates transport from Tile A to Storage Area SA1. While IN_TRANSIT, SA1 is destroyed (e.g., disaster event, or the player demolishes it — see EC-H2). At transport completion, the destination container no longer exists.
- **Handling:**
  1. At completion, verify destination container exists. If not → items transition to **LOST**.
  2. No energy refund. No item placement. Consistent with EC-H3 (save-load) and EC-M1 (source destroyed).
  3. The event is logged for debugging: "Transport to removed container [container_id] — items lost."
- **Vertical Slice context:** Disasters are not in VS scope. Player demolishing their own Storage Area is possible but unlikely (no refund, so it's a bad decision).

### LOW Severity

**EC-L1: HUD Utilization Rounding**

- **Scenario:** Formula 6 computes `U = (67 / 150) × 100 = 44.666...%`. How is this displayed and compared against thresholds?
- **Handling:** Display value is rounded to the nearest integer for human readability (`U_display = round(U)`). Threshold comparisons (75%, 90%) use the **raw float** value, not the rounded display value. This means a container at 74.6% (displayed as "75%") triggers the warning at 74.6%, not 75.0%.
- **Tuning knob:** Threshold values are configurable (see Tuning Knobs section).

**EC-L2: `get_resource` Returns Null**

- **Scenario:** A slot holds a `resource_id` that no longer exists in the Resource System registry (corrupted save, missing entry, deleted resource).
- **Handling:** Defensive guard — if `get_resource(resource_id)` returns null:
  1. Log the error to debug console.
  2. Mark the slot as "unknown" in the UI (display `[Unknown Resource]`, quantity preserved).
  3. The slot is treated as occupied (counts toward `occupied_slots`) but is not usable by buildings or hunger consumption.
  4. The item cannot be moved, deposited, or consumed. It is effectively "frozen" until the save is fixed or the slot is manually cleared.
- **This is a data integrity requirement.** The game must not crash on null resource definitions.

**EC-L3: Stack-Split Boundary — Partial Deposit Fails Entirely**

- **Scenario:** Container has 1 empty slot. 5 items of type BAR arrive. Stack limit for BAR is 3. First-Fit: no existing BAR stack. One empty slot. Fill: min(5, 3) = 3 items. Remaining: 2 items. No more empty slots. Deposit returns FAILURE.
- **Handling:** When a deposit fails, the **entire batch is returned to the source**. No partial deposit of 3 items. This prevents fragmented capacity (3 items in a slot + 2 items lost = wasted space that can never hold 2 items of another type).
- **Design note:** This is strict but simple. The alternative (partial deposit) creates "dead space" — slots with 1-2 items that block meaningful deposits of other resources.

**EC-L4: Ideal Split Case (Documented for Developer Clarity)**

- **Scenario:** Container has 2 empty slots. 4 items of type FOO arrive. Stack limit for FOO is 2. Phase 2: first empty slot → 2 items (full). Second empty slot → 2 items (full). Success.
- **Handling:** Standard first-fit flow. No special case. This is the expected successful split behavior. Documented here to prevent developers from implementing "split across fewer slots" incorrectly.

## Dependencies

Dependencies are organized into **upstream** (systems the Inventory/Storage System depends on) and **downstream** (systems that depend on the Inventory/Storage System). Each dependency specifies the interface used and the direction of data flow.

### Upstream (Inventory/Storage depends on)

| System | Dependency Type | Interface Used | Notes |
|--------|----------------|----------------|-------|
| **Resource System** | Hard — schema definitions | `get_resource(resource_id)` returns `{stack_limit, max_charge, category}` | Inventory reads resource attributes from the registry. Never modifies resource definitions. Stack limits and charge caps are enforced by this system's schema, not redefined here. |
| **Player Character System** | Hard — transport & energy | `get_energy_state()` returns `{energy, max_energy, state}`; Inventory → Player Character: `on_transport_complete(quantity, resource_id)` **Bidirectional** | Inventory queries Player Character for energy state before allowing transport. Player Character receives `on_transport_complete` signal to update its sprite (carrying icon) and action state. Both systems call APIs on each other — this is an intentional bidirectional dependency with well-defined roles: Player Character initiates, Inventory processes. |
| **Tick System** | Hard — timer advancement | Subscribes to `ticks_advanced(delta_ticks)` | Inventory decrements `remaining_ticks` for all IN_TRANSIT items each tick. Inventory does NOT call Tick System APIs; it is a passive subscriber to the tick signal. |
| **Grid System** | Hard — spatial validation | `validate_placement(x, y)` returns `{can_place, blocked_by}`; `get_tile_drop(x, y)` returns `{resource_id, quantity, state}` or null | Inventory queries Grid for: (1) Storage Area placement validation (Rule 7), (2) source tile resource info during transport (Rule 4 step 1). Grid's BuildingLayer is modified when Inventory places a Storage Area. Circular, well-defined — Inventory is always the active caller. |

### Downstream (Inventory is depended on by)

| System | Dependency Type | Interface Used | Notes |
|--------|----------------|----------------|-------|
| **Building System** | Hard — build cost consumption | `try_consume(container_id, resource_id, quantity)` returns `{success, remaining_deficit}`; `get_resource(container_id, resource_id)` returns `{quantity_available}` | Building System queries and consumes resources from storage for build costs (Rule 8: 8 Wood + 2 Stone). Build menu shows green/red preview based on storage availability. Circular: Building calls Inventory for consumption, Inventory's state changes trigger Building System build progress. Well-defined — Building System is always the active caller. |
| **Production System** | Hard — input/output | `reserve_input(container_id, resource_id, quantity)` returns `{success, actual_quantity}`; `deposit_output(container_id, resource_id, quantity)` returns `{success, allocated_slots}` | Production System pulls inputs at production start and deposits outputs on completion. Inventory deducts/allocation atomically. Circular: Production calls Inventory for reservation, Inventory's deposit triggers Production completion. Well-defined — Production System is always the active caller. |
| **Hunger System** | Hard — food consumption | `consume_food(daily_food_requirement)` returns `{total_consumed, slots_affected, remaining_deficit, hunger_debuff_applied}` | Hunger System scans all containers and deducts food at day transition via Formula 5. Inventory returns actual consumed amount and a debuff flag. One-way (Hunger → Inventory). Hunger System does not provide APIs to Inventory. |
| **HUD/UI** | Soft — display data | `get_storage_contents(container_id)` returns `{slots: Array[slot_data]}`; `get_capacity(container_id)` returns `{occupied, total, utilization_ratio}`; `get_in_transit_items()` returns `{items: Array[transit_item]}` | HUD polls Inventory for storage contents, capacity bar, in-transit item count, and slot utilization ratio. Inventory does NOT push data to HUD — HUD polls on its own update cycle (60 Hz). One-way (Inventory → HUD). |
| **Save/Load System** | Hard — serialization | `serialize()` returns `Array[container_snapshot]`; `deserialize(Array[container_snapshot])` → creates InventoryContainers | Save/Load System calls Inventory's `serialize()` to capture all container states. On load, calls `deserialize()` which creates containers matching the saved data (including IN_TRANSIT states). One-way (Save/Load → Inventory). Inventory must provide deterministic serialization (slots serialized in index order, containers serialized in container_id order). |

### Circular Dependencies Summary

| Pair | Type | Resolution |
|------|------|------------|
| Inventory ↔ Building System | Active (Building) → Passive (Inventory) | Building System calls Inventory APIs. Inventory never calls Building APIs. |
| Inventory ↔ Production System | Active (Production) → Passive (Inventory) | Production System calls Inventory APIs. Inventory never calls Production APIs. |
| Inventory ↔ Player Character | Bidirectional API | Both systems call each other's methods. Well-defined by contract: Player Character initiates transport, Inventory processes it and signals completion back. |
| Inventory ↔ Grid System | Active (Inventory) → Passive (Grid) | Inventory queries Grid for placement/tile data. Grid's BuildingLayer is modified by Inventory's placement action. |

### Cross-System Design Notes

- **Manual Labor System is NOT a dependency.** Resource tiles are spawned by Manual Labor onto the Grid System. Inventory observes tile state changes via the Grid System (`get_tile_drop(x, y)`), not via a direct call to Manual Labor. The data flow is: Manual Labor → Grid (resource spawn event) → Inventory reads from Grid. Manual Labor is a downstream consumer of the Grid System, not an upstream provider to Inventory.

- **Tick System consumer list gap:** The Tick System's `Interactions with Other Systems` table (Tick System GDD) currently does not list Inventory/Storage as a subscriber to `ticks_advanced`. This should be added when the Tick System GDD is next reviewed. Inventory's in-transit timer tracking depends on receiving this signal every tick.

- **Grid System consumer list gap:** The Grid System's `Interactions with Other Systems` table does not list Inventory/Storage as a user of `validate_placement()` or `get_tile_drop()`. This should be added when the Grid System GDD is next reviewed.

## Tuning Knobs

Tuning knobs are the values that designers will adjust during playtesting to shape the feel and balance of the system. Each knob lists its default value (calibrated for the Vertical Slice 4-day arc), its safe range, and the gameplay aspect it affects.

### Transport Tuning

| Knob | Symbol | Default | Safe Range | Effect | Formula Reference |
|------|--------|---------|------------|--------|-------------------|
| **Base energy cost per item** | — | 2 | 0.5 – 5 | Pickup and carry effort. Higher values make bulk transport more punishing. Primary lever for "burden of distance" feel. | Formula 1 |
| **Energy cost per tile** | — | 1 | 0.25 – 3 | Travel distance penalty. Higher values stretch out the meaningful transport radius. Primary lever for early-game scarcity. | Formula 1 |
| **Ticks per tile of travel** | — | 5 | 1 – 15 | How long transport takes in-game time. Higher values make transport feel more substantial; lower values make it feel trivial. Affects how many concurrent transports a player can plan. | Formula 2 |

### Storage Tuning

| Knob | Default | Safe Range | Effect | Formula Reference |
|------|---------|------------|--------|-------------------|
| **Base capacity (Storage Area)** | 50 | 25 – 100 | Starting container size. Higher values reduce early-game transport urgency; lower values intensify the granary bottleneck from minute one. Default of 50 exceeds VS manual throughput (see capacity analysis below). | Formula 4 |
| **Storage Building capacity** | 150 | 100 – 250 | Total capacity of a built Storage Building. Controls how much additional space the first building investment provides. | Formula 4 |
| **Initial build cost** | 8 Wood + 2 Stone | 5W+1S – 12W+4S | The first investment gate. Higher values delay automation; lower values make it feel too easy. Balanced against 4-day resource production. | Rule 2 |
| **Build time** | 120 Ticks | 60 – 300 | How long the player waits after placing the building. 120 ticks = 12 seconds at 1x speed — enough to feel meaningful without boredom. | Rule 2 |

### Capacity Analysis (Default Configuration)

At default values, the two capacity tiers are:

| Container | Capacity | Cost | VS Context |
|-----------|----------|------|------------|
| Storage Area | 50 | Free | Exceeds Day 1 manual throughput (~30 items). Player won't hit capacity on Day 1 unless they actively try to fill it. |
| Storage Building | 150 | 8 Wood + 2 Stone | Exceeds Day 2–3 throughput (~60–120 items). Comfortable buffer for processing goods. |

**Key insight:** At default values, the 50-slot base far exceeds VS manual throughput. The storage bottleneck arrives after the player needs to decide whether to build a Storage Building or place additional Storage Areas. If playtesting shows the bottleneck should arrive earlier, reduce base capacity to 25 or lower the Storage Building capacity to 100.

### Energy Budget Context (for knob tuning)

All transport energy knobs should be evaluated against the player energy pool (100 at start). Key reference points:

| Trip | q | d | Energy | % of Pool |
|------|---|---|--------|-----------|
| Typical early game (4 wood, 8 tiles) | 4 | 8 | 16 | 16% |
| Efficient bulk (20 wood, 5 tiles) | 20 | 5 | 45 | 45% |
| Maximum viable (9 wood, 82 tiles — max within 100 pool) | 9 | 82 | 100 | 100% |
| Over budget (10 wood, 82 tiles) | 10 | 82 | 102 | 102% → fails |

The formula design means that **quantity is the primary bottleneck, not distance**. A player can haul 20 items 5 tiles (45 energy, 45% pool) but only 9 items even if they're adjacent (at d=0, q = energy_remaining/2). This is intentional: bulk efficiency rewards good base-to-storage positioning.

### HUD Thresholds

| Knob | Default | Safe Range | Effect |
|------|---------|------------|--------|
| **Warning threshold** | 75% | 60% – 85% | Utilization % at which amber/orange warning appears. Lower values give earlier warnings but may cause anxiety. |
| **Critical threshold** | 90% | 80% – 95% | Utilization % at which red border + pulsing appears. Should be high enough that the warning feels urgent but not panic-inducing. |

### Notes on Knob Interdependence

These knobs do not operate in isolation:

- **Base capacity × Storage Building capacity** form a two-tier curve. Changing one without considering the other can make the Storage Building feel redundant (if base is too high) or essential from Day 1 (if base is too low).
- **Energy cost per item × energy cost per tile** are independent levers but their combined effect determines the "meaningful transport radius" — the maximum distance at which bulk transport (high quantity) is still viable. At defaults, this radius is approximately 48 tiles for a 10-item load (E = 20 + 48 = 68 < 100).
- **Ticks per tile × build time** affect perceived pacing. If ticks per tile is lowered (faster transport), build time should also be lowered proportionally to maintain the balance between "waiting for transport" and "waiting for build."

## Visual/Audio Requirements

The Inventory/Storage System has minimal direct visual/audio requirements because it is primarily an infrastructure system — players interact with it through the UI (see UI Requirements section) and through the physical player character carrying items. The following visuals and audio are defined by this system:

### Tile-Drop Visuals

| State | Visual | Detail |
|-------|--------|--------|
| **DROPPED** | Small pile sprite on the tile, matching the resource type | Same visual as Manual Labor harvest output. Pile bobs gently (idle animation, ~2 Hz). Size of pile is proportional to quantity: 1 item = small dot, max stack = full pile. |
| **IN_TRANSIT** | Player character sprite carrying a resource icon above head | The icon matches the resource type and color. Number of items is NOT shown on the icon — player must remember what they're carrying. This reinforces the "burden" feeling. |
| **STORED** | No visual on tile — resource disappears from tile immediately | The moment transport completes, the pile vanishes. This instantaneous disappearance is intentional — it signals "safe in storage." A small sparkle particle effect (1 frame, white flash) appears where the pile was. |

### Storage Building Visuals

| State | Visual | Detail |
|-------|--------|--------|
| **Under construction** (120 ticks) | Scaffolding overlay on Storage Area marker | Animated — hammer icon swings every 2 seconds. Area cannot accept deposits during this time (still 50-slot base capacity). |
| **Operational** | Storage Building sprite on tile | Visual distinction from other buildings: roof shape + storage symbol (barrel icon in door). Color matches building tier. |
| **Full** (storage capacity reached) | Amber glow around building | Pulsing at 1 Hz. Visible from distance. Signals "this storage is full, don't transport here." |

### Transport Visual

| Action | Visual | Detail |
|--------|--------|--------|
| **Transport initiated** | Player character sprite walks from source tile to storage | Path is not pre-drawn (player controls the character). The transport is a real-time walking animation — not teleportation. Travel time = Formula 2 ticks. |
| **Transport cancelled** | Player character returns to source tile with item | Reverses the walk. Items return to tile. No visual effect beyond the walking animation in reverse. |

### Audio Cues

| Event | Audio | Detail |
|-------|-------|--------|
| **Item dropped on tile** | Small thud (soft, muffled) | Volume proportional to quantity. Max stack = loudest. Distinguishes from player footsteps. |
| **Transport completed (deposit)** | Satisfying "clunk" (wood crate opening) | Same sound for all resources. Pitch randomized ±1 semitone for variety (every 3rd deposit has slightly different pitch). |
| **Transport failed (energy insufficient)** | Low "wah" (descending tone, ~0.5 sec) | Short, not jarring. Distinguishes from deposit success. Only plays when energy check fails at arrival. |
| **Storage full warning** | Subtle click (once, when capacity crosses 90%) | Plays once per session when storage crosses critical threshold. Not repeated on every deposit — prevents audio fatigue. |
| **Upgrade completes** | Positive chime (ascending 3-note sequence) | Distinguishes from build completion (which has a different sound). Only plays for the player's own storage, not for off-screen upgrades. |

## UI Requirements

The Inventory/Storage System drives the majority of player-facing UI in the Vertical Slice. Storage is opened dozens of times per session — every transport decision, every building construction, every hunger check requires storage UI access. The UI must be fast, scannable, and information-transparent (Pillar 2).

### Storage Container UI

| Element | Description | Detail |
|---------|-------------|--------|
| **Storage Panel** (modal overlay) | Grid of slot cells, opens when player interacts with a Storage Area | 10 columns × N rows (N = ceil(capacity/10)). Each cell shows: resource icon (32×32px), quantity number (bottom-right corner, white with black outline), stack progress bar (subtle fill level within cell). Empty cells are dimmed (30% opacity). |
| **Capacity Bar** (header of panel) | Horizontal bar showing occupied slots vs. total capacity | Format: "45 / 150 slots". Color matches Slot Utilization Ratio thresholds (green 0-74%, amber 75-89%, red 90-100%). Clicking the bar toggles between sorted-by-resource and sorted-by-slot-index view. |
| **Resource type filter** (row of icons) | Below capacity bar, shows only resources currently in storage | Icon + quantity for each unique resource type. Clicking an icon filters the slot grid to show only that resource. "Show all" button resets filter. |

### Transport Interaction UI

| Element | Description | Detail |
|---------|-------------|--------|
| **Source tile preview** (step 1 of transport) | Tooltip on clicking a tile with dropped resource | Format: "[Resource Icon] [Resource Name] ×N — Transport to [Storage Name]: X Energy, Y Ticks". Color-coded: green if energy affordable, red if not. |
| **Destination selection** (step 2 of transport) | Highlighted border around target Storage Area when hovered | Green border if storage has capacity, red border if full. Border width = 3px. |
| **In-transit status** (while walking) | Small icon above player character + tooltip on hover | Icon shows resource type. Tooltip: "Carrying [Resource] ×N — X ticks remaining". |
| **Energy cost preview** (on HUD) | Energy bar updates when player hovers over a transportable tile | Energy bar briefly dims by the transport cost amount, showing "after transport" energy level. This is a preview — not an actual deduction. Helps the player see "can I afford this trip AND the return trip?" |

### HUD Elements

| Element | Description | Detail |
|---------|-------------|--------|
| **Energy bar** (HUD, top-left corner) | Shows current energy / max energy | Green → yellow → red gradient as energy decreases. Depleted state (0 energy) shows pulsing skull icon next to bar. Not part of Inventory System directly, but Inventory queries Player Character for this value. |
| **Storage quick-access** (HUD, bottom-right) | Mini icon showing nearest storage fill level | Small circle with fill-level color matching utilization ratio. Clicking opens the nearest storage container UI. Hover tooltip: "[Storage Name] — X / Y slots (Z%)". |
| **In-transit counter** (HUD, near quick-access) | Number of items currently being carried | Shows "1" when player has an item. Disappears when transport completes or is cancelled. No special styling — just a small number badge. |

### Building System UI Integration

| Element | Description | Detail |
|---------|-------------|--------|
| **Build preview** (when placing Storage Building) | Green checkmark if storage has resources, red X if not | Tooltip: "Need 8 Wood + 2 Stone. Have: 12 Wood + 0 Stone." (or whichever resources are in the player's nearest storage or global pool). |
| **Building storage assignment UI** (when placing a production building) | Dropdown or clickable grid to select which Storage Area feeds this building | Shows nearby Storage Areas with their available resource types and quantities. Player must select at least one storage before the building can be placed. |
| **Storage suggestion** (in build menu, conditional) | "Storage at 85% — consider adding storage" shown when placing a new building | Only appears when the nearest storage is above the warning threshold. Non-blocking — player can still build. |

## Acceptance Criteria

All acceptance criteria are independently testable. A QA tester should be able to run each test and mark PASS or FAIL.

### Core Mechanics

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC1 | GIVEN a tile with a dropped resource, clicking the tile shows a transport preview with correct energy and time cost calculated by Formula 1 and Formula 2 | Unit test + manual verification |
| AC2 | GIVEN energy_remaining < energy_cost, the transport action is blocked and the preview tooltip displays in red | Manual verification |
| AC3 | GIVEN a valid transport (energy sufficient), completing transport moves the resource from DROPPED state to STORED state and deducts the correct energy and time costs | Integration test with state assertions |
| AC4 | GIVEN the player cancels a transport before arrival, items return to the source tile and no energy is deducted | Manual verification |
| AC5 | GIVEN a resource dropped on a tile, buildings CANNOT access it directly — production system reports zero available | Integration test: build a building near a tile-drop, verify it produces nothing |

### First-Fit Slot Allocation

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC6 | GIVEN an empty container and a deposit of N items where N ≤ stack_limit, all N items fit in a single slot | Unit test: `allocate_slots()` returns one allocation with quantity = N |
| AC7 | GIVEN a container with an existing partial stack and a deposit that overflows that stack, items are split across exactly two slots | Unit test: verify slot indices and quantities |
| AC8 | GIVEN a full container (occupied_slots == capacity), a deposit attempt returns FAILURE and items are NOT partially deposited | Unit test: `allocate_slots()` returns `{status: FAILURE}` |
| AC9 | GIVEN a deposit with quantity that exceeds stack_limit, items are split across the minimum number of slots needed (ceil(quantity / stack_limit)) | Unit test with quantity = 150, stack_limit = 99 → 2 slots |
| AC10 | GIVEN a container with 1 empty slot and a deposit of 5 items with stack_limit = 3, the deposit FAILS (partial deposit not allowed) | Unit test: matches EC-L3 |

### Capacity

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC11 | GIVEN a new Storage Area placed on a valid tile, the created container has capacity = 50 | Integration test: `get_capacity()` returns 50 |
| AC12 | GIVEN a Storage Area with a Storage Building (initial build complete), the container has capacity = 150 | Integration test after build completes |
| AC13 | GIVEN a Storage Area with no building, capacity = 50; GIVEN a Storage Area with a completed Storage Building, capacity = 150 | Integration test: `get_capacity()` returns 50 for bare SA, 150 after build completes |
| AC14 | GIVEN a Storage Building is demolished, the container capacity reverts to 50 and items remain in their slots (even if occupied > 50) | Integration test: demolish building, assert capacity = 50, assert items still in slots |

### Transport

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC15 | GIVEN a transport to a container that is full at arrival time, items are LOST (not deposited) and no energy is refunded | Integration test: fill storage, send transport during fill, assert items lost on arrival |
| AC16 | GIVEN a save-game during an active transport, loading the game restores the transport with correct remaining ticks | Save/load test: start transport, save, reload, assert IN_TRANSIT state preserved |
| AC17 | GIVEN a storage area placed on a TREE resource tile, the tree is cleared and no resource remains on the tile | Integration test: place SA on tree, verify tree gone, verify storage created with 50 slots |
| AC18 | GIVEN a storage area placement on a STONE resource tile, placement is blocked and the tile shows a red X in the placement preview | Integration test: attempt placement on stone, assert `validate_placement()` returns `{can_place: false}` |

### Hunger Consumption

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC19 | GIVEN two containers with food slots of quantities [3, 50], hunger consuming 10 units deducts from Slot A (3) first, then Slot B (2), leaving [0, 48] | Unit test: run `consume_food(10)`, assert slot quantities |
| AC20 | GIVEN total food across all containers < daily_food_requirement, `consume_food()` returns `hunger_debuff_applied = true` and `remaining_deficit > 0` | Unit test: 22 food available, request 30, assert result |
| AC21 | GIVEN food slots across multiple containers, consumption prioritizes lowest quantity first regardless of which container holds the slot | Unit test: Container A has [50], Container B has [3], request 10 → B's slot emptied first |
| AC22 | GIVEN slots sorted by quantity ascending with equal quantities, the slot with the lower slot_index is consumed first | Unit test: two slots with quantity = 5 at indices 3 and 1 → index 1 consumed first |

### Invariants

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC23 | GIVEN a building with production output, the output is deposited into storage (never appears on a tile or in the player's possession) | Integration test: build a production building, verify output appears in assigned container |
| AC24 | GIVEN a slot with current_charge = 75.0 is deposited into storage and then retrieved, the retrieved slot shows current_charge = 75.0 (charge is not reset by deposit/consume operations other than recipe consumption) | Integration test: deposit item, verify slot data preserves current_charge |
| AC25 | GIVEN two buildings pulling from the same container with quantity = 7 available, building A (lower ID) pulls 7, building B (higher ID) pulls 0 | Unit test: deterministic pull ordering by container_id, then building_id |
| AC26 | GIVEN a slot holding a resource_id that no longer exists in the Resource System registry, the slot displays as "[Unknown Resource]" and is treated as occupied but unusable | Unit test: inject corrupted slot data, assert UI display and consumption skip |

## Open Questions

Questions that are unresolved or deferred to future design sessions. These do not block implementation but should be addressed before MVP.

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ1 | Should the player be able to have multiple Storage Areas? If so, is there a limit? | Affects UI complexity (which storage to show?), transport routing (nearest vs. selected), and overall storage strategy. Currently allowed (Rule 9), but VS may want to limit to 1 for simplicity. | **Deferred to VS scope discussion with producer.** |
| OQ2 | What happens to a transport if the player dies? Is death a save-point, or do transported items persist? | Ties into Save/Load System and Player Character System death mechanics. EC-H3 assumes IN_TRANSIT state is persisted, but death may have special rules (item loss, respawn). | **Deferred to Player Character System GDD.** |
| OQ3 | Should there be a "haul all" bulk action for transporting multiple items from the same tile? | Quality-of-life feature. Not in VS scope but worth considering for polish. Would need to be balanced against the "every trip costs something" tension. | **Deferred — note for UI design review.** |
| OQ4 | Can the Storage Area marker be moved after placement? | If yes, moving it changes transport distances for all nearby tile-drops. If no, early placement decisions matter more. Current design assumes NO (placement is permanent). | **Design preference — discuss with game-designer.** |
| OQ5 | Should there be a "favorite storage" or "nearest storage" auto-select for transport? | UX convenience vs. player awareness. Auto-selecting nearest storage removes one click but may hide distance tradeoffs from the player. | **Deferred to UX review.** |
| OQ6 | At what quantity does the tile-drop visual change size? Is the bobbing animation speed constant, or does it vary by quantity? | Visual clarity — player should be able to quickly read "how many items are on this tile" without clicking. | **Deferred to technical-artist for sprite implementation.** |
