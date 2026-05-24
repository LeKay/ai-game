# Player Character System

> **Status**: In Design
> **Author**: User + Claude (Sonnet 4.5)
> **Last Updated**: 2026-05-10
> **Implements Pillar**: Pillar 1 (Manual → Automated)

## Overview

The Player Character System is the data registry and state machine that tracks the player's interaction with the game world — energy pool, active manual actions, and resource gathering state. It receives input events from the Input System (tile clicks for harvesting, drag-and-drop for transport, UI actions for menus) and the Input System's camera controls (WASD moves the camera viewport, not a player character) and the Tick System (tick accumulation, day transitions, speed changes) and translates them into gameplay effects: initiating manual labor (foraging, chopping trees, picking berries, mining stone) by clicking directly on world tiles, consuming food to refill energy, and transporting resources from harvested tiles to storage buildings by dragging pin icons on the map.

The player character does not exist as a visible entity or sprite on the map. They act from above — clicking directly on world tiles to initiate actions. When the player harvests a tile, the resource appears **on that tile** as a small resource icon (pin). Transporting resources to storage is a drag-and-drop action: the player drags the pin icon from the resource tile to the storage building tile, consuming energy (2 × quantity + 1 × distance) and ticks (5 × distance). There is **no carrying inventory** — the player operates remotely from above, not as a physical presence.

The system owns the **Energy** pool (100 max) and its depletion mechanics: at 0 Energy, all manual actions cost 2× ticks and produce `ceil(output × 0.5)` output (minimum 1). This energy constraint is the throttle that makes earned automation meaningful — if the player could work infinitely, there would be no incentive to build production buildings or hire NPCs.

## Player Fantasy

In the beginning, every manual action costs energy — and every drop of energy demands a choice. You click a tree, the tick counter fills, your energy bar drops. You click berries, chop wood, carry stone. The game doesn't rush you. You can't rush yourself. Energy is the throttle that makes every action deliberate.

But slowly, without noticing, the weight of your work shifts. Your first NPC starts producing at the lumber mill. You check your energy — 12/100 — and realize: *I don't need to chop the next tree. I can just eat a berry and watch.* The village runs itself for a moment. You exhale. That moment — the first time you stop working because the system works without you — is the game's emotional core.

You are not a god. You are the steward of a struggling village — someone who began by working the land with their own hands and now guides the settlement toward prosperity. The energy bar is not a health bar; it's an hourglass. Low energy isn't danger — it's just *time to rest and eat.* Automation is the reward for understanding, not an escape from labor. Every process you automate, you understand, because you did it yourself first.

UI language guidelines:
- Energy bar: "39/100" (plain numbers), green when full, amber when low (10-29), red when critical (0-9)
- Low energy state: "Rest a moment — actions will be slower" (not "Depleted!" or "Exhausted!")
- 0 Energy: "Energy depleted — actions cost 2x time, yield 50% less" (factual, not dramatic)

## Detailed Design

### Core Rules

**1. Player Identity**
- The player character has no visible sprite on the map. They act remotely from above.
- The player interacts with the world by clicking directly on world tiles or dragging resource pins.
- WASD and arrow keys move the camera viewport, not the player character.
- The player character exists as a data state machine: energy pool, active manual actions, tile-level resource state.

**2. Energy Pool**
- The player starts with 100 Energy (full). Energy never exceeds 100 or drops below 0 (clamped).
- Energy is consumed by manual actions according to the action's discrete energy cost.
- There is **no upfront energy gate**: the player can always start any action regardless of current Energy. Energy is an hourglass, not a wall. At 0 Energy, the depletion penalty applies (2× tick cost, halved output) but the action still proceeds.
- At 0 Energy, the player can start any action — including Pick Berries (the primary recovery action). This ensures the player is never stuck.
- Energy is deducted at action start. If deducting the action's energy cost would bring Energy below 0, it is clamped to 0 (cannot go negative).
- Eating food **occupies the action slot**: it runs for its tick cost and prevents starting other actions during that time. See Rule 6.

**3. Manual Actions**
- The player initiates a manual action by clicking on a world tile. The action type is determined by what is on the tile (tree, berry bush, stone, grass/meadow, etc.).
- Before starting, the system shows cost preview (energy cost, tick cost, expected output) on hover. At 0 Energy, the tooltip shows modified values (doubled ticks, halved output).
- Once initiated, the action runs for its tick cost. The player **cannot start another action during a manual action** — the action slot is occupied.
- When the action completes, the resource appears **on the clicked tile** as a small resource pin icon (stack of 1 item for now — more can drop via the random chance for Meadow Foraging).
- **Tool requirement:** Two actions (Chop Tree, Mine Stone) require a tool with sufficient charge in the shared storage. The player must have at least 1 slot of a resource tagged `"tool"` with `current_charge >= charge_cost`. Each tool-requiring action deducts `charge_cost` from the most-depleted qualifying tool slot. If no slot has sufficient charge, the action is blocked with tooltip: "No tool available — craft one first." Tools are stored in the Inventory/Storage System and are shared across all use (manual and automated).

| Action | Tick Cost | Energy Cost | Output |
|--------|-----------|-------------|--------|
| Meadow Foraging | 50 | 8 | Randomly drops: 1 Wood (40%), 1 Fiber (40%), 1 Stone (20%) |
| Pick Berries | 40 | 5 | 3 Berries |
| Craft Tool | 100 | 15 | 1 Tool |
| Chop Tree | 80 | 12 | 5 Wood (requires tool, deducts charge_cost charge) |
| Mine Stone | 60 | 10 | 3 Stone (requires tool, deducts charge_cost charge) |

**4. Transport (Drag-and-Drop)**
- After harvesting a tile, the resource appears as a **pin icon** (small resource sprite) on the tile. The pin shows a stack count when there are multiple items.
- The player **drags the pin icon** from the resource tile to the destination tile (storage building). This is a drag-and-drop interaction — not a click-then-confirm dialog.
- **Energy cost:** `2 × quantity + 1 × distance`, where `distance` is the Manhattan distance from the source tile to the nearest storage building.
- **Tick cost:** `5 × distance`, where `distance` is the Manhattan distance from the source tile to the nearest storage building. (Transport time is distance-based, not item-based — bulk transport is time-efficient but energy-expensive, encouraging players to optimize building-to-storage placement.)
- When transport completes: the pin icon is removed from the source tile and the storage building's inventory updates.
- The player can drag and drop multiple items at once (up to 5 per drag). Each drag is a single transport action.
- If the player cancels the drag (releases the pin on a non-storage tile), the pin returns to its original position and no energy/ticks are consumed.

**5. Energy Depletion Penalty**
- When the player's Energy reaches 0, the depletion penalty activates:
  - All new actions cost **2× their base tick cost** and produce **ceil(base_output × 0.5)** output (minimum 1 output for any action that produces ≥ 1 item).
  - Energy cost is NOT modified — the player still pays the base energy cost (deducted, clamped to 0 if insufficient).
  - The player is **never locked out** of any action, including Pick Berries (the primary recovery path).
  - The only UI change is the energy bar turning red with the text "Energy depleted — actions cost 2x time, yield 50% less."

**6. Food-to-Energy Refill**
- The player can consume food items to refill Energy instantly.
- Consumption amounts:
  - 1 Beere (berry) → +10 Energy
  - 1 Brot (bread) → +25 Energy
- Eating food **occupies the action slot**: the player must spend a manual action to eat, and the action runs until completion. The eating action has no tick cost — it completes instantly once initiated. However, the action slot IS occupied, preventing other actions during this time.
- Energy is clamped to max 100 — excess Energy is lost.
- Food source: food is consumed from whichever container it currently resides in (tile drop pin or storage building). There is no separate carry-inventory for food. If food is on a tile pin, the player can eat it by clicking the pin (or via the energy bar quick-eat menu). If food is in storage, eating it requires opening the storage UI and selecting the food item.

**7. Day Transition**
- The player character persists across day boundaries. Energy, tick state, and pending manual actions are unaffected by day transitions.
- The Tick System fires `day_transition` at tick 1000 → tick 0. This triggers:
  - Hunger consumption: NPCs only, per Hunger System GDD. The player does NOT consume food — the player manages energy via the Energy system (Rule 6).
  - The player is NOT killed by hunger (hunger is a productivity modifier, not a death timer).

**8. Energy Depletion During Active Actions**
- If an action is already running and the player's Energy drops to 0 mid-action (e.g., the player was at 5 Energy, started a 5-Energy action, and depleted during it): the action completes normally at its base cost. The 2x tick / 50% output penalty only applies to NEW actions started at 0 Energy.

**9. Architect Mode — Manual Labor Locks Out After First NPC Assigned**

The player has two distinct gameplay phases:

- **Pre-NPC phase (Day 1):** The player manually gathers resources (Pick Berries, Chop Tree, Mine Stone) and transports them to storage. This is the bootstrapping phase. The player IS the only laborer.
- **Architect phase (first NPC assigned onward):** Once the player assigns the first NPC to any building, all manual gathering actions (Pick Berries, Chop Tree, Mine Stone) are permanently locked out. The player is now a systems architect — they place buildings, manage storage, set building assignments, and observe production. They can still: eat food, transport resources, interact with UI, and place/demolish buildings.

This transition is one-way and permanent within a session. There is no return to manual labor. The lock-out is enforced by the Player Character System: after `on_npc_assigned` fires for the first NPC, the action slot rejects all gathering tile-clicks with a tooltip: *"Your workers handle this now."*

**Rationale:** This commitment resolves the architect/settler identity split. Manual labor is a tutorial mechanism — it teaches the economy before automation arrives — not a persistent gameplay mode. The designer's intent is for the emotional peak to be the moment the player stops working because the system works without them.

**Transition event:** `on_npc_assigned(npc_id, building_id)` from NPC System. The Player Character System subscribes to this signal. First fire locks manual gathering permanently.

### States and Transitions

| State | Description | Input Behavior |
|-------|-------------|----------------|
| **Idle** | No action in progress. Ready to accept manual actions, transport drags, or UI interactions. | Click tile → start action. Drag pin → start transport. Menu clicks → UI navigation. |
| **Performing Action** | Manual action running (harvesting, crafting, eating). Tick counter fills. | No new manual actions accepted. Transport also blocked. Menu clicks still accepted. |
| **Transporting** | Transport action running (drag-and-drop from tile to storage). Tick counter fills based on distance. | No new manual actions or transports accepted. Menu clicks still accepted. Pin icon fades from source tile. |
| **Energy Depleted** | Energy = 0. Not a separate state — a flag on any state. All actions available (no lockout). Energy deducted then clamped to 0. | Actions cost 2× ticks, produce ceil(output × 0.5) min 1. UI shows depleted text below energy bar. |

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Input System** | Receives tile clicks, drag-and-drop events, camera movement, UI actions | Input System → Player Character: `on_tile_clicked(world_pos)`, `on_drag_start(world_pos)`, `on_drag_end(world_pos)`, `on_food_consumed(food_type)` | Player Character interprets tile clicks as action initiations, drag events as transport |
| **Tick System** | Receives tick updates, day transitions, speed changes | Player Character → Tick System: `advance_ticks_manual(cost: int)`, `get_tick_modifier()` | Tick System provides tick accumulation; player character charges action duration against ticks. The PC System calls `advance_ticks_manual()` directly — no separate `start_action` interface. |
| **Resource System** | Spawns/removes resources on tiles | Player Character → Resource System: `spawn_resource(tile_pos, resource_id, quantity)`, `remove_resource(tile_pos, resource_id, quantity)` | Player Character queries resource definitions for tile types, spawns output on action completion |
| **Inventory/Storage System** | Receives transported items | Player Character → Inventory/Storage: `deposit_to_storage(storage_id, resource_id, quantity)` | Player Character deposits items into storage building after drag-and-drop transport completes |
| **HUD System** | Displays energy bar, action progress, resource pins, cost previews | Player Character → HUD: `energy_state(current, max)`, `action_progress(action_id, current_ticks, total_ticks)`, `resource_pins(tile_pos, resource_id, quantity)` | HUD renders energy bar, tile-level progress indicators, resource pin icons on map |

## Formulas

**1. Transport Energy Cost**

The `transport_energy_cost` formula is defined as:

`transport_energy_cost = (2 × quantity) + (1 × distance)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| quantity | q | int | 1–5 | Number of items dragged in this transport action |
| distance | d | int | 0–unbounded | Manhattan distance from source tile to nearest storage building (`|dx| + |dy|`) |
| transport_energy_cost | E | int | 2–10 + distance | Energy consumed for the transport action |

**Output Range:** [2, unbounded] — at 1 item, 0 distance = 2 energy minimum; at 5 items, 20 tiles = 30 energy.

**Example:**
```
quantity = 3
source_tile = (12, 8)
nearest_storage = (5, 3)
distance = |12-5| + |8-3| = 7 + 5 = 12
transport_energy_cost = (2 × 3) + (1 × 12) = 6 + 12 = 18 energy
```

**2. Transport Tick Cost**

The `transport_tick_cost` formula is defined as:

`transport_tick_cost = 5 × distance`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| distance | d | int | 0–600 | Manhattan distance from source tile to nearest storage building |
| transport_tick_cost | T | int | 0–3000 | Ticks consumed for the transport action |

**Output Range:** [0, 3000] — 0 ticks for source = storage (already there), max 3000 at 600 tiles.

**Example:**
```
source_tile = (12, 8)
nearest_storage = (5, 3)
distance = |12-5| + |8-3| = 7 + 5 = 12
transport_tick_cost = 5 × 12 = 60 ticks
```

**Time vs. energy relationship:** Energy and time are **decoupled** — energy depends on quantity, time depends on distance. A single item at 60 tiles costs 122 energy (E = 2×1 + 60) and 300 ticks (T = 5×60). 5 items at the same distance cost 70 energy (E = 2×5 + 60) and 300 ticks. This asymmetry is the core strategic depth: bulk transport is time-efficient but energy-expensive. The player optimizes quantity vs. distance to maximize items-per-energy.

**3. Energy Depletion Action Modifier**

When the player's Energy is 0 at action start, the effective tick cost and output are modified:

`effective_tick_cost = base_tick_cost × 2`
`effective_output = max(1, ceil(base_output × 0.5))`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| base_tick_cost | T_base | int | 5–200 | Tick cost from action table (Rule 3) |
| base_output | O_base | int | 1–5 | Expected output from action table (Rule 3) |
| effective_tick_cost | T_eff | int | 10–400 | Doubled tick cost when at 0 Energy |
| effective_output | O_eff | int | 1–3 | Output halved (ceiling), with minimum 1 |

**Output Range:** T_eff ∈ [10, 400], O_eff ∈ [1, 3].

**Ceiling with minimum-1 guard:** The `ceil()` function rounds up (unlike `floor()` which rounds down). Combined with `max(1, ...)`, single-item actions (base_output = 1) produce 1 output even at 0 Energy: `max(1, ceil(1 × 0.5)) = max(1, 1) = 1`. Multi-item actions: `max(1, ceil(5 × 0.5)) = max(1, 3) = 3`. The player always gets something back, preserving the "hourglass runs slow, not stops" fantasy.

**Example:**
```
Action: Baum fällen (chop tree)
base_tick_cost = 80, base_output = 5 Wood
effective_tick_cost = 80 × 2 = 160
effective_output = max(1, ceil(5 × 0.5)) = max(1, 3) = 3 Wood
```

**Probabilistic actions:** For actions with random outputs (Meadow Foraging: 1 Wood 40%, 1 Fiber 40%, 1 Stone 20%):
- The random roll happens first: player gets 1 item of random type.
- Then the depletion formula applies: `max(1, ceil(1 × 0.5)) = 1`.
- Result: at 0 Energy, Meadow Foraging always produces 1 item of the randomly rolled type (no doubling — the item type is random, but the quantity is always ≥ 1).

## Edge Cases

**HIGH Priority**

| # | Scenario | Handling |
|---|----------|----------|
| **EC1** | Player has 0 Energy and starts an action that exactly costs all remaining energy (e.g., 0 Energy but action costs 5, can't start). If player is at 5 Energy and starts a 5-Energy action, they hit 0 Energy mid-action. | Rule 2: upfront check — can only start if current_energy ≥ cost. Rule 8: action already running is unaffected — completes at base cost. The depletion penalty only applies to NEW actions. |
| **EC2** | Transport drag started, player pauses game, then resumes. | Tick System freezes on pause. Transport action is frozen — tick counter paused. No energy/ticks deducted during pause. Resuming resumes tick accumulation. |
| **EC3** | Storage building is full when player attempts transport. | Inventory/Storage System returns "full" signal. Transport does NOT complete — pin returns to source tile (NOT lost, consistent with submission aesthetic). Player must clear storage space or build additional storage. No energy/ticks consumed (failed transport). |

**MEDIUM Priority**

| # | Scenario | Handling |
|---|----------|----------|
| **EC4** | Player initiates eating food. | Eating occupies the action slot — no other actions can start while eating. The eating action has 0 tick cost but the slot is still blocked. Energy refills instantly. If another action was previously running (blocked by eating), it cannot resume — the action slot is consumed by eating and remains unavailable until the player manually starts a new action. |
| **EC5** | Day transition occurs while manual action is running. | Action continues uninterrupted (Rule 7). Tick counter keeps accumulating. No state loss. |
| **EC6** | Player drags pin but releases on a non-storage tile (cancel). | Pin returns to original position. No energy or ticks consumed. This is the only way to cancel a transport drag. |
| **EC7** | Multiple resource types harvested on the same tile. | Each resource type appears as its own pin icon on the tile. Multiple pins can coexist. Each pin is an independent transport target. |
| **EC8** | Player clicks tile while another action is already running. | Action slot is occupied (Rule 3). New action is rejected. HUD could show "action in progress" to indicate why the click was ignored. |

**LOW Priority**

| # | Scenario | Handling |
|---|----------|----------|
| **EC9** | Player eats more food than needed (would exceed max energy). | Energy clamped to 100 (Rule 6). Excess restoration is lost. Food is still consumed. |
| **EC10** | Transport distance = 0 (source tile IS the storage building). | Valid edge case. `distance = 0`, so `transport_energy_cost = 2 × quantity`. Minimum energy for 1 item = 2. |
| **EC11** | Player's energy is exactly 0 and they try to transport (1 item, distance 5). | Energy cost = 2 + 5 = 7. Player has 0 energy, cannot afford (energy check is upfront). Transport is blocked. At 0 Energy, actions CAN start (depletion penalty applies), but the upfront energy cost check still requires sufficient energy. |
| **EC12** | Action with output = 1 at 0 Energy (edge case: minimum single-item action). | `max(1, ceil(1 × 0.5)) = 1`. Player gets 1 output. The minimum-1 guard ensures no action produces 0. This is correct behavior — even at 0 Energy the player makes progress. |
| **EC13** | Building placement on invalid tile (e.g., occupied, out of bounds). | Grid/Map System validates placement before Player Character System submits. If invalid, action cancelled, energy refunded, ticks refunded. |

## Dependencies

### Upstream Dependencies

| System | What This System Needs | What This System Provides | Interface |
|--------|----------------------|--------------------------|-----------|
| **Input System** | Tile click events, drag-and-drop events, camera movement events | — | `on_tile_clicked(world_pos)`, `on_drag_start(world_pos)`, `on_drag_end(world_pos)` |
| **Tick System** | Tick accumulation, action duration management, day transition signal | `advance_ticks_manual(cost: int)`, `get_tick_modifier()` | Player Character charges action duration against Tick System |

### Downstream Dependents

| System | What This System Provides | What This System Needs | Interface |
|--------|--------------------------|----------------------|-----------|
| **Manual Labor System** | Energy pool management, action slot occupation, energy depletion logic | — | Shares energy pool and action slot with Manual Labor |
| **Hunger System** | Food consumption source (player eats), energy refill result | Hunger System provides food items to consume | Player Character → Hunger System: `consume_food(food_type)` |
| **Inventory/Storage System** | Transported items delivered to storage | Inventory/Storage validates storage capacity | Player Character → Inventory/Storage: `deposit_to_storage(storage_id, resource_id, quantity)` |
| **Resource System** | Spawns resource pins on tiles, removes resources after transport | Resource System defines which tile types are harvestable | Player Character → Resource System: `spawn_resource(tile_pos, resource_id, quantity)`, `remove_resource(tile_pos, resource_id, quantity)` |
| **HUD System** | Energy state, action progress, resource pin locations | HUD renders all visual feedback | Player Character → HUD: `energy_state(current, max)`, `action_progress(action_id, current_ticks, total_ticks)`, `resource_pins(tile_pos, resource_id, quantity)` |

## Tuning Knobs

These values are configurable without changing system behavior. All knobs have safe ranges and break conditions.

| Knob | Symbol | Default | Safe Range | Gameplay Impact | Break Condition |
|------|--------|---------|------------|-----------------|-----------------|
| Max Energy | `energy_max` | 100 | 50–200 | Player's capacity for manual labor before needing rest. Higher = longer play sessions before automation is necessary. | Below 50: player frustrated by constant eating. Above 200: no meaningful pressure to automate. |
| Berry Energy Restore | `berry_energy_restore` | 10 | 5–20 | Single-berry energy value. Higher = more granular eating, lower = eating becomes a bigger decision. | Below 5: too many berries needed, eating becomes tedious. Above 20: 5 berries = max energy, too easy. |
| Bread Energy Restore | `bread_energy_restore` | 25 | 15–50 | Bread (processed food) energy value. Ratio to berry defines food tier strategy. | Ratio berry:bread should stay 1:2–1:3. Higher ratio = bread too powerful. |
| Transport Energy Per Item | `energy_per_item_transport` | 2 | 1–4 | Energy cost per item in transport. Higher = shorter transport distances viable, lower = transport feels trivial. | Below 1: transport always affordable. Above 4: even 1-item transports expensive at distance. |
| Transport Energy Per Tile | `energy_per_tile_transport` | 1 | 0–3 | Energy cost per tile of distance. Controls how far players are willing to transport. | 0: distance irrelevant, no spatial strategy. Above 3: 10+ tile transports cost more than actions. |
| Transport Ticks Per Item | `ticks_per_item_transport` | 5 | 3–10 | Time cost per item in transport. Higher = transport competes with action time for player attention. | Below 3: transport too fast, no meaningful choice. Above 10: 5 items = 50 ticks, blocks all other actions. |
| Depletion Tick Multiplier | `depletion_tick_multiplier` | 2.0 | 1.5–3.0 | Speed penalty at 0 Energy. Higher = stronger incentive to eat. | Below 1.5: depletion feels meaningless. Above 3.0: 0 Energy = hard lock feeling. |
| Depletion Output Multiplier | `depletion_output_multiplier` | 0.5 | 0.3–0.7 | Output reduction at 0 Energy. Controls how painful depletion is. | Below 0.3: nearly useless at 0 Energy. Above 0.7: no meaningful consequence. |
| Max Drag Quantity | `max_drag_quantity` | 5 | 3–10 | Maximum items per drag-and-drop. Higher = less frequent transport actions needed. | Below 3: tedious micro-management. Above 10: drag loses spatial strategy element. |

## Visual/Audio Requirements

### Visual

| Element | Specification | State |
|---------|--------------|-------|
| **Resource Pin Icons** | Small pin sprite (16×16 px) on harvested tiles, showing resource type via color/shape. Stacks of 2+ show a small number overlay in the corner. | Persistent until transported |
| **Action Progress Bar** | Thin horizontal bar above the tile being worked on, showing tick accumulation progress (0% → 100%). Color matches energy state (green/amber/red). | Visible only during action |
| **Drag-and-Drop Visual** | Resource pin follows cursor during drag. A dotted line connects source tile to cursor position. When hovering over a valid storage building tile, the tile highlights with a green outline. When hovering over invalid tile, red outline. | Only during active drag |
| **Energy Bar** | Top-left HUD element. Plain "39/100" text. Color coding: green (30–100), amber (10–29), red (0–9). Bar fills proportionally from left to right. | Always visible |
| **0 Energy State** | Energy bar pulses red at 1 Hz. Text below bar: "Energy depleted — actions cost 2x time, yield 50% less." | When energy = 0 |
| **Food Consumption** | Brief visual: berry icon flashes near energy bar + small "+10" text fades up. Bread: larger bread icon + "+25". | Instant feedback |
| **Transport Completion** | Source tile pin fades out. Storage building tile briefly flashes with item count increase. | On transport finish |

### Audio

| Event | Audio Cue | Volume/Conditions |
|-------|-----------|-------------------|
| **Action Start** | Short whoosh/start sound, unique per action type (chopping has wood crack, foraging has rustle) | Base volume, not on depletion |
| **Action Complete** | Positive chime + resource-specific sound (wood thud for tree, crunch for berries) | Base volume |
| **Transport Start** | Soft pick-up sound | Base volume |
| **Transport Complete** | Soft deposit sound | Base volume |
| **Energy Depleted** | Low, muffled tone (not alarm — this is rest time, not danger) | Loops at 1 Hz until energy recovered |
| **Eating** | Brief crunch sound | Base volume |
| **Blocked Action** (no energy, action running) | Soft negative tick | Only on rejection |
| **Transport Blocked** (storage full) | Soft thud | Only on rejection |

## UI Requirements

### Energy Bar (HUD)

- **Position**: Top-left corner of screen
- **Components**: Horizontal fill bar + "39/100" text overlay
- **Color states**: Green (#4CAF50) for 30–100, Amber (#FF9800) for 10–29, Red (#F44336) for 0–9
- **0 Energy**: Bar pulses red at 1 Hz, subtitle text appears below bar
- **Interaction**: Clicking energy bar opens food selection menu (if food consumed from tiles)

### Action Cost Preview (On Hover)

- **Trigger**: Player hovers cursor over a harvestable tile
- **Display**: Tooltip showing energy cost, tick cost, and expected output
- **Example**: "Chop Tree — 12 energy, 80 ticks → 5 Wood"
- **Depletion state**: If at 0 Energy, tooltip shows modified values: "Chop Tree — 12 energy, 160 ticks → 3 Wood (depleted)". Note: energy cost is NOT modified by depletion, only tick cost (doubled) and output (ceil × 0.5, min 1).
- **Blocked state**: If player lacks energy to start, tooltip shows crossed-out cost and "Insufficient Energy"

### Drag-and-Drop Transport UI

- **Drag start**: Click and hold on resource pin, pin follows cursor
- **Drag line**: Dotted line from source tile to cursor, showing distance
- **Distance label**: Small text on drag line: "7 tiles"
- **Cost label**: Cost preview appears near cursor during drag: "18 energy · 15 ticks"
- **Valid target**: Storage building tile highlights green outline during drag
- **Invalid target**: Non-storage tile highlights red outline
- **Release on invalid**: Pin animates back to source tile (no cost)
- **Release on valid**: Transport begins, progress bar appears on storage building

### Transport Cost Display

- **Qualitative indicators**: Cost values shown with color-coded risk: green (affordable), amber (significant), red (critical)
- **Thresholds**: Green = cost ≤ 30% of current energy, Amber = 30–70%, Red = >70%
- **Combined display**: Energy cost shown with energy icon, tick cost with clock icon

### Action Progress Indicator

- **On-tile bar**: Thin progress bar above active tile
- **HUD indicator**: If multiple actions could exist, HUD shows action queue (currently 1 action slot)
- **Action type label**: Small text above progress bar: "Chopping..."

## Acceptance Criteria

| # | Acceptance Criterion |
|---|---------------------|
| **AC1** | GIVEN a tile with a harvestable resource WHEN the player clicks it AND the player has sufficient energy THEN the manual action starts, the tick counter fills for the action's tick cost, and energy is deducted by the action's energy cost |
| **AC2** | GIVEN a manual action is running WHEN the tick counter reaches the action's tick cost THEN the resource appears on the tile as a pin icon and the action slot becomes free |
| **AC3** | GIVEN a resource pin on a tile WHEN the player drags it to a storage building AND the player has sufficient energy THEN the transport begins, deducts `2 × quantity + 1 × distance` energy and `5 × distance` ticks, and deposits items into storage on completion |
| **AC4** | GIVEN a resource pin on a tile WHEN the player drags it to a non-storage tile AND releases THEN the pin returns to its original position with no energy or ticks consumed |
| **AC5** | GIVEN the player has 0 Energy WHEN the player attempts to start a manual action with insufficient energy THEN the action is blocked and the energy bar displays the depleted state with subtitle text. At 0 Energy, actions with sufficient energy CAN start with depletion penalties applied. |
| **AC6** | GIVEN the player has 0 Energy WHEN the player initiates eating food THEN energy is instantly restored by the food's value (berry +10, bread +25) clamped to max 100 and the action slot is occupied (even though the eat action has no tick cost) |
| **AC7** | GIVEN the player is at 0 Energy WHEN a new action is started THEN tick cost is doubled and output is `max(1, ceil(base_output × 0.5))` per the Energy Depletion Modifier formula |
| **AC8** | GIVEN a manual action is running WHEN the player's energy drops to 0 during the action THEN the action completes at base cost and base output (depletion penalty does not retroactively apply) |
| **AC9** | GIVEN a day transition occurs WHEN a manual action or transport is running THEN the action continues without interruption and tick progress is preserved |
| **AC10** | GIVEN a storage building is full WHEN the player attempts transport THEN the transport fails, pin returns to source tile (NOT lost), and no energy/ticks are consumed |
| **AC11** | GIVEN the player hovers over a harvestable tile WHEN the player has sufficient energy THEN a cost preview tooltip shows energy cost, tick cost, and expected output |
| **AC13** | GIVEN the player has energy in [91..99] WHEN the player consumes bread (+25 energy) THEN energy is clamped to exactly 100 and the food item is removed from its current source |
| **AC14** | GIVEN the player is at 0 Energy WHEN the player hovers over a harvestable tile THEN the tooltip shows the depleted tick cost (doubled) and depleted output (ceil × 0.5, min 1) with a "(depleted)" label |
| **AC15** | GIVEN a transport drag where source tile equals the storage building tile (distance = 0) THEN transport energy cost = 2 × quantity and tick cost = 0 |
| **AC16** | GIVEN a tool-requiring action WHEN the player has no tools OR all tools have 0.0 charge THEN the action is blocked with the message "No tool available — craft one first" |
| **AC17** | GIVEN the player has food on a tile pin WHEN the player initiates eating that food THEN the food is removed from the tile, energy is restored, and the action slot is occupied (even though eating completes instantly) |
| **AC18** | GIVEN the player has 0 Energy WHEN the player uses WASD to move the camera THEN camera movement is NOT blocked and works normally |

## Open Questions

| # | Question | Impact | Deferred To |
|---|----------|--------|-------------|
| **OQ1** | Can multiple resources of different types coexist on the same tile? If so, how many pins max? Affects HUD complexity, drag-and-drop precision, and tile visual clarity. | High | Building System (depends on whether buildings produce resources on-tile) |
| **OQ2** | Where is the "quick-eat" menu triggered from? Clicking the energy bar? A hotkey? Context menu on food pin? Affects UI System integration. | Medium | HUD System (menu placement and interaction patterns) |
| **OQ3** | Do resource pins stack visually (one pin showing count) or do individual pins multiply (3 pins for 3 berries)? Affects drag-and-drop UX and tile visual density. | Medium | Grid/Map System (tile rendering constraints) |
| **OQ4** | Should there be a "drag-cancel" timeout? If player holds a pin but doesn't move cursor for 5+ seconds, auto-release to prevent stuck drags. | Low | Input System (drag state machine) |
| **OQ5** | Can the player interrupt a running manual action? If yes, what's the refund (full? partial? none)? Affects player freedom vs. commitment tension. | High | Resolved: No interrupt. Actions run to completion. This preserves commitment tension. If the player clicked the wrong tile at 0 Energy, they must accept the penalty — it reinforces deliberate clicking. |
