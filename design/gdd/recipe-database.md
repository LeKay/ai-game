# Recipe Database System

> **Status**: Partially Implemented — design target; see implementation note (2026-06-13)
> **Author**: User + Claude (Sonnet 4.5)
> **Last Updated**: 2026-06-13
> **Implements Pillar**: Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)
>
> **Implementation note (2026-06-16):** The centralized `res://data/recipes.json`
> registry described below is **not yet built**. The current implementation splits
> recipes across two code tables:
> - **Manual crafting** — `src/gameplay/crafting_registry.gd` (`CraftingRegistry`
>   Autoload): five recipes — `axe` (3 Wood + 2 Stone, 20 Energy, 120 ticks → 1 Axe),
>   `pickaxe` (3 Stone + 1 Wood, 20 Energy, 120 ticks → 1 Pickaxe),
>   `spindle` (2 Wood + 2 Fiber, 15 Energy, 90 ticks → 1 Spindle),
>   `cloth` (4 Fiber, 20 Energy, 180 ticks → 1 Cloth), and `clothing`
>   (3 Cloth + 2 Fiber, 25 Energy, 240 ticks → 1 Clothing). Crafting advances the world
>   clock via `advance_ticks_manual` — it is not instant (balancing 2026-06-11).
>   No tool-charge inputs on the manual path.
> - **Building production** — `BuildingRegistry.RECIPES` (see `design/gdd/building-system.md`):
>   cycle recipes as arrays per building type (index 0 = main recipe, index 1+ = fallback).
>   Buildings with fallback recipes expose a recipe selector in BuildingDetailPanel.
>   Current building recipes: Lumber Camp (requires Axe), Stone Mason (requires Pickaxe),
>   Gathering Hut, Tool Workshop (3 recipes: Axe/Pickaxe/Spindle), **Weaver**
>   (Fiber+Spindle→Cloth, 250/750 ticks), **Tailor** (Cloth+Spindle→Clothing, 300/900 ticks),
>   **Sawmill** (2 Wood + 1 Axe → 3 Plank, 250 ticks),
>   **Farm** (WHEAT-adjacent gathering → 5 Wheat, 250 ticks; efficiency scales with adjacent WHEAT count),
>   **Mill** (2 Wheat → 3 Flour, 250 ticks), **Bakery** (2 Flour → 4 Bread, 300 ticks).
>   **Clay Pit** (1 Pickaxe → 5 Clay, 250 ticks; requires adjacent CLAY terrain),
>   **Pottery Kiln** with_tool (2 Clay + 1 Pickaxe → 3 Pottery, 300 ticks) /
>   bare_hands fallback (2 Clay → 1 Pottery, 900 ticks).
>   **Tannery** with_knife (2 Hide + 1 Knife → 3 Leather, 250 ticks) /
>   bare_hands fallback (2 Hide → 1 Leather, 750 ticks). Gated behind `tannery`
>   progression node (prereqs: tailoring + hunting + knife).
>   **Tailor** gains 3rd recipe leather_garments (2 Leather + 1 Spindle → 2 Clothing, 300 ticks).
>   **Tool Workshop** gains craft_knife (2 Wood + 1 Stone → 1 Knife, 375 ticks).
>   New tool resource: `knife` (wood ×2 + stone ×1; manual craft 90 ticks).
>   New intermediate resource: `leather` (production_good / intermediate).
>   New trade_good resource: `pottery` (perk_eligible; NPC comfort good like clothing).
>   New intermediate resource: `flour` (production_good / intermediate).
>   **Hunting Bow chain (2026-06-20):** New tool resource `hunting_bow` (wood ×2 + fiber ×3).
>   Manual craft: `hunting_bow` (120 ticks, 20 energy). New building **Bowyer's Workshop**
>   (`BOWYERS_WORKSHOP`): `craft_bow` (wood ×2 + fiber ×3 → hunting_bow ×1, 375 ticks, NPC).
>   Hunting Lodge recipe split: `hunt_with_bow` (primary, hunting_bow ×1 → meat ×3 + hide ×2,
>   300 ticks) and `hunt` (bare hands fallback, no inputs → meat ×2 + hide ×1, 450 ticks).
>   Progression: `bowyer` node (crafting branch, prereqs: woodcutting + fiber_harvesting) unlocks
>   BOWYERS_WORKSHOP + manual hunting_bow recipe; `bow_hunting` node (food branch, prereqs:
>   hunting + bowyer) unlocks `HUNTING_LODGE:hunt_with_bow`.
> Migrating both tables into the JSON registry below remains the design goal
> (data-driven content rule); treat the rest of this document as the target design,
> not the implemented state.

## Overview

The Recipe Database System defines the complete set of production recipes in the game — every transformation from inputs to outputs, whether performed manually by the player, by NPCs in buildings, or through automated processes. It specifies each recipe's required inputs (resources and tool charge costs), produced outputs (resources with quantities), tick cost (production time), building requirement (which structure can execute it, if any), and unlock conditions (progression gates or NPC tier requirements). Stored as a centralized JSON registry at `res://data/recipes.json`, it serves as the single source of truth for all production chain logic, enabling the Production System to execute recipes, the Manual Labor System to present player crafting options, the Building System to validate construction costs, and the UI to display recipe previews and requirements.

All gameplay systems that involve resource transformation reference this registry rather than hardcoding recipe definitions, enabling data-driven content expansion: adding a new production chain (e.g., "wheat → flour → bread") requires only editing the JSON file, not changing code. The system distinguishes between **manual recipes** (player can perform bare-handed or with tools), **building recipes** (require a specific building type and NPC assignment), and **construction recipes** (building placement costs, handled specially by Building System). Recipe complexity directly serves **Pillar 2 (Information Transparency)** by making all production chains inspectable and debuggable (no hidden formulas) and **Pillar 3 (Optimization Over Expansion)** by enabling deep multi-step chains (wood → planks → furniture) rather than wide variety for its own sake.

## Player Fantasy

You zoom out and watch your village run. The sawmill eats logs and produces planks. The carpenter takes planks and makes furniture. The trading post bundles furniture for export. Every building is a gear in a machine *you* designed — and the recipes are the teeth on those gears, the precise specifications that make each connection work. You don't think about recipes anymore. You think about flow.

Early, recipes are visible and demanding. You manually execute each one, counting inputs, watching tick timers crawl forward. "80 ticks to fell a tree... 100 ticks to craft a tool... 50 ticks for 5 planks." Every transformation is visceral — you *feel* the tick cost because you're paying it with your time.

Mid-game, recipes disappear into buildings. You stop thinking "this recipe takes 50 ticks and 1 log" and start thinking "the sawmill feeds the carpenter." The recipe becomes invisible infrastructure, exactly like real-world manufacturing — nobody at Toyota thinks about individual bolt specifications; they think about the production line. The numbers fade. The flow takes over.

Late-game, recipes resurface only when something breaks. A bottleneck forces you to re-examine the clockwork. You click the bread production building and see: flour takes 80 ticks, but dough only takes 30, and the mill is running at 60% capacity while the bakery is idle 40% of the time. The recipe is no longer a crafting instruction — it's a diagnostic tool. You know every number by heart, and now those numbers tell you exactly where the machine jams.

The Recipe Database System exists to make that transformation possible. Early, it teaches you the rules. Mid, it gets out of your way. Late, it becomes the X-ray vision you use to see *through* your production empire and understand why it's not perfect yet. The fantasy is the factory architect who built the machine so well that they forgot how the individual parts work — until something jams, and then their deep knowledge kicks in.

## Detailed Design

### Core Rules

**1. Recipe Definition Schema**

Every recipe in the registry has the following structure:

**Required Attributes:**
- **`recipe_id`** (string, unique) — Machine-readable identifier (e.g., `"chop_tree_manual"`, `"sawmill_produce_planks"`). Lowercase alphanumeric + underscore only. Never changes once assigned.
- **`display_name`** (string) — Human-readable name shown in UI (e.g., "Chop Tree", "Produce Planks"). Localized.
- **`category`** (enum: `"gathering"` | `"crafting"` | `"processing"`) — Classification for UI organization and validation rules:
  - `"gathering"` — Zero-input resource generation (berry picking, twig collecting)
  - `"crafting"` — Manual player recipes with inputs (tool crafting, basic processing)
  - `"processing"` — Building-operated recipes with NPC assignment (sawmill, bakery)
- **`inputs`** (array of objects) — Required resources. Can be empty for gathering recipes. Each input:
  - `resource_id` (string) — References `res://data/resources.json`
  - `quantity` (integer >= 1) — Amount consumed whole (charge fully deducted: `quantity × max_charge`)
  - `charge_cost` (float, optional) — If set, deducts this amount of charge from the slot instead of consuming whole items. The item remains in the slot until `current_charge <= 0`. If both `quantity` and `charge_cost` are set, `charge_cost` takes priority and `quantity` must be 1.
- **`outputs`** (array of objects, length >= 1) — Produced resources. Each output:
  - `resource_id` (string) — References resource registry
  - `quantity` (integer >= 1) — Amount produced (items are always produced at full charge)
- **`tick_cost`** (integer >= 1) — Production time in ticks. Minimum 1 (instant recipes use tick_cost = 1, not 0).
- **`building_requirement`** (string | null) — Building ID required to execute this recipe. `null` = manual recipe (player can perform bare-handed or with tools).
- **`icon_path`** (string) — Relative path to recipe icon (e.g., `"assets/ui/icons/recipes/chop_tree.png"`).

**Optional Attributes:**
- **`description`** (string, max 120 chars) — Tooltip text explaining what this recipe does.
- **`unlock_conditions`** (array of condition objects) — Progression gates. If empty/null, recipe is available from game start. See Rule 3 for condition schema.
- **`execution_mode`** (enum: `"single"` | `"loop"`) — Default `"single"` for manual recipes (player performs once per click), `"loop"` for building recipes (NPC repeats until inputs exhausted or stopped).

**2. Recipe Execution Rules**

**Manual Recipes** (`building_requirement: null`):
- Player initiates via UI action (click recipe in crafting menu)
- Player character must be idle (not already executing another recipe)
- Tick cost is paid by player's action timer (blocks other actions during execution)
- `execution_mode` is always `"single"` (one click = one execution)
- Inputs are deducted from player inventory at recipe start, outputs added at recipe completion

**Building Recipes** (`building_requirement: "some_building"`):
- Requires NPC assignment to the building
- Building must exist and be functional (not under construction, not destroyed)
- `execution_mode` defaults to `"loop"` — NPC repeats recipe until:
  - Inputs exhausted (insufficient resources in storage)
  - Output storage full (cannot accept outputs)
  - NPC unassigned or building destroyed
  - Player manually stops production
- Inputs deducted from shared storage at recipe start, outputs added at completion
- If inputs consumed mid-execution by another building/recipe, current execution **restarts from 0 ticks** (harsh but clear feedback)

**Charge Consumption (partial item use):**
- If an input has `charge_cost`, the system searches storage for slots containing `resource_id` with `current_charge >= charge_cost`
- For stacked items, `current_charge` is the **total charge for all units in the slot** — three axes at 150 max_charge each = 450 total charge available
- Selects the slot with the **lowest current_charge** that still satisfies `charge_cost` (use most-depleted slot first to minimize waste)
- Deducts `charge_cost` from the selected slot's `current_charge`
- If `current_charge <= 0` after deduction, the slot is emptied (resource_id = null, quantity = 0)
- If no slot has sufficient charge, the recipe cannot execute (status: "Insufficient charge")

**3. Unlock Conditions (Satisfactory-Style Milestones)**

Recipes can have unlock conditions that gate their availability. Conditions are evaluated continuously; when all conditions for a recipe become true, the recipe unlocks permanently (no re-locking).

**Milestone Unlock Schema:**
```json
{
  "type": "milestone",
  "milestone_id": "bronze_age",
  "required_stockpiles": [
    {"resource_id": "wood", "quantity": 50},
    {"resource_id": "stone", "quantity": 30}
  ]
}
```

**Behavior:**
- Milestone is considered "achieved" when player has simultaneously stockpiled ALL required resources
- Resources are **NOT consumed** — this is a check, not a trade
- Once achieved, all recipes with this `milestone_id` unlock permanently
- UI shows milestone progress: "Bronze Age: Wood 45/50, Stone 30/30"

**Future unlock types (post-MVP):**
- `"type": "trade_completed"` — Unlock when player completes a trade quest
- `"type": "building_constructed"` — Unlock when specific building exists
- `"type": "npc_tier_reached"` — Unlock when NPCs reach tier threshold

**4. Data Format**

- **File:** `res://data/recipes.json`
- **Structure:** JSON object with version and recipes array
- **Example:**
```json
{
  "version": 1,
  "last_updated": "2026-05-05",
  "recipes": [
    {
      "recipe_id": "gather_berries",
      "display_name": "Gather Berries",
      "category": "gathering",
      "inputs": [],
      "outputs": [
        {"resource_id": "berries", "quantity": 3}
      ],
      "tick_cost": 40,
      "building_requirement": null,
      "icon_path": "assets/ui/icons/recipes/gather_berries.png",
      "description": "Pick berries from nearby bushes.",
      "unlock_conditions": [],
      "execution_mode": "single"
    },
    {
      "recipe_id": "sawmill_planks",
      "display_name": "Produce Planks",
      "category": "processing",
      "inputs": [
        {"resource_id": "wood", "quantity": 1},
        {"resource_id": "axe", "charge_cost": 5.0}
      ],
      "outputs": [
        {"resource_id": "plank", "quantity": 5}
      ],
      "tick_cost": 50,
      "building_requirement": "sawmill",
      "icon_path": "assets/ui/icons/recipes/planks.png",
      "description": "Convert logs into planks at the sawmill.",
      "unlock_conditions": [
        {
          "type": "milestone",
          "milestone_id": "woodworking_basics",
          "required_stockpiles": [
            {"resource_id": "wood", "quantity": 20}
          ]
        }
      ],
      "execution_mode": "loop"
    }
  ]
}
```

**5. Validation Rules (Load-Time Enforcement)**

The system validates the recipe registry on load and rejects malformed data:

**Critical (Halt load on failure):**
- `recipe_id` is unique across all recipes
- `category` is one of the defined enum values
- All `resource_id` references in inputs/outputs exist in `res://data/resources.json`
- If `building_requirement` is non-null, the building ID exists in the building registry
- `outputs` array has length >= 1 (recipes must produce something)
- `tick_cost >= 1` (no zero-tick recipes — prevents infinite loops)
- If input has `charge_cost`, the referenced resource must exist in the registry AND `charge_cost > 0.0`
- If `charge_cost` is set alongside `quantity`, `quantity` must be 1 (charge_cost subsumes whole-item consumption)
- If `category == "processing"`, `building_requirement` must be non-null (processing recipes require buildings)
- If `category == "gathering"`, `inputs` must be empty (gathering recipes have no inputs)

**Warning (Log but allow):**
- If `unlock_conditions` is empty, warn: "Recipe available from game start"
- If `inputs` is empty AND `tick_cost < 50`, warn: "Fast resource generator — verify balance"
- If `execution_mode == "loop"` but `building_requirement == null`, warn: "Loop mode on manual recipe — likely error"

**6. Extensibility**

- New recipes can be added without code changes (systems load registry at runtime)
- Schema versioning: Increment `version` when adding required fields. Systems apply migration for old saves.
- Deprecation: Add `"deprecated": true` to hide recipe from UI while keeping it loadable from saves

### States and Transitions

Recipes themselves are stateless data definitions. Recipe **instances** (executions in progress) have states:

**Recipe Execution States:**

| State | Description | Transitions |
|-------|-------------|-------------|
| **Available** | Recipe unlocked, player has inputs, can execute | → Queued (player clicks) OR → Unavailable (inputs consumed) |
| **Unavailable** | Recipe locked OR missing inputs | → Available (unlock OR gain inputs) |
| **Queued** | Player/NPC initiated, waiting to start | → In Progress (tick reaches start time) OR → Cancelled (player stops) |
| **In Progress** | Actively executing, tick timer counting | → Completed (tick reaches end time) OR → Failed (inputs removed mid-execution) OR → Cancelled (building destroyed) |
| **Completed** | Outputs produced, added to storage | → Available (loop mode) OR → Idle (single mode) |
| **Failed** | Execution interrupted, progress lost | → Available (if inputs replenished) OR → Unavailable (if still missing) |

**State Diagram:**
```
[Unavailable] ←→ [Available] → [Queued] → [In Progress] → [Completed]
                                             ↓                 ↓
                                        [Failed]    (loop mode) → [Available]
```

**Transition Rules:**
- **Available → Unavailable:** Triggered when inputs consumed by another system OR recipe lock re-applied (future feature)
- **Queued → Failed:** Only if inputs removed from storage after queuing but before execution completes
- **In Progress → Failed:** Building destroyed mid-execution OR NPC unassigned (manual recipes cannot fail mid-execution — player character cannot be destroyed)

### Interactions with Other Systems

**Production System (primary consumer):**
- **Reads:** All building recipes (`category == "processing"`)
- **Query:** "Given building type X and storage contents Y, which recipes can execute?"
- **Data flow:** Production System queries available recipes, selects highest-priority, initiates execution, manages tick timer, calls back to Recipe Database on completion to get outputs

**Manual Labor System:**
- **Reads:** All manual recipes (`building_requirement == null`)
- **Query:** "Show all recipes player can perform with current inventory"
- **Data flow:** Presents recipe list to player, on selection deducts inputs and blocks player actions for `tick_cost`, on completion adds outputs to player inventory

**Building System:**
- **Reads:** Recipe `building_requirement` field to validate building placement prerequisites
- **Data flow:** When player builds a Sawmill, checks if any locked recipes require `"sawmill"` and displays "Unlocks 3 new recipes" in build tooltip
- **Note:** Building construction costs are stored in building definitions themselves (not in Recipe Database)

**Inventory/Storage System:**
- **Reads:** Recipe `inputs` and `outputs` for availability checks
- **Data flow:** Recipe Database queries storage for resource quantities and tool charge, Inventory System provides readonly access, deductions/additions happen after Recipe Database validates execution

**UI Systems:**
- **HUD:** Displays active recipe progress bars (tick timer)
- **Crafting Menu:** Shows available recipes filtered by `building_requirement == null`, grays out unavailable recipes, shows unlock progress
- **Building Panel:** Shows building-specific recipes, displays loop status ("Producing planks... 15 in storage, looping")
- **Milestone Tracker:** Shows unlock progress for milestone conditions

**Goal System (future):**
- **Writes:** Unlocks recipes when goals completed (e.g., "Complete tutorial → unlock advanced recipes")

**Trading System (future):**
- **Writes:** Unlocks recipes when trade quests completed (Satisfactory-style)

## Formulas

The Recipe Database System uses the following calculations:

### 1. Item Charge Selection Formula

When a recipe input specifies `charge_cost`, the system selects which storage slot to deduct charge from.

**The `select_slot_for_charge` formula is defined as:**

`selected_slot = first(sort_asc(filter(slots, resource_matches AND sufficient_charge), by: current_charge))`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| slots | S | array | 0-999 slots | All slots in shared storage |
| resource_id | rid | string | registry id | Resource type required by recipe input |
| charge_cost | cost | float | > 0.0 | Charge consumed by recipe |
| current_charge | c_curr | float | 0.0–(qty × max_charge) | Total remaining charge of all units in slot |
| candidate_slots | C | array | 0-99 slots | Slots matching resource_id with c_curr >= cost |
| selected_slot | s_sel | object | slot or null | Chosen slot (null if no valid candidates) |

**Intermediate steps:**
- `resource_matches = slot.resource_id == resource_id`
- `sufficient_charge = slot.current_charge >= charge_cost`
- `filter(S, resource_matches AND sufficient_charge) = C`
- `sort_asc(C, by: current_charge) = sorted candidates` (most-depleted first)
- `first(sorted candidates) = s_sel`

**Output Range:** [slot instance] if candidates exist, [null] otherwise

**Example:**
```
Recipe: "Produce Planks" requires axe with charge_cost: 5.0
Storage contains:
  - Slot A: axe, current_charge = 12.0 (e.g. 1 axe at 12/100)
  - Slot B: axe, current_charge = 435.0 (e.g. 5 axes at 87/100 each)
  - Slot C: wood, current_charge = 300.0 — EXCLUDED (wrong resource_id)

Filtered candidates: [Slot A (12.0), Slot B (435.0)]
Sorted ASC by current_charge: [Slot A (12.0), Slot B (435.0)]
Selected: Slot A (use most-depleted slot first)
Result: Slot A.current_charge = 12.0 - 5.0 = 7.0 (slot survives)
```
Next cycle: Slot A has 7.0 charge — still >= 5.0, selected again
After 2nd cycle: Slot A.current_charge = 2.0 (below charge_cost 5.0, now excluded)
3rd cycle: Slot B selected, Slot B.current_charge = 435.0 - 5.0 = 430.0
```

---

### 2. Recipe Efficiency Formula

Used to compare manual vs. building recipes producing the same output, and by AI to select optimal recipes.

**The `recipe_efficiency` formula is defined as:**

`efficiency = total_output_value / (tick_cost + total_input_value)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| outputs | O | array | 1-5 items | Recipe output resources with quantities |
| inputs | I | array | 0-10 items | Recipe input resources with quantities |
| tick_cost | t | int | 1-1000 | Production time in ticks |
| base_value | v | int | 1-999 gold | Resource value from resource registry |
| total_output_value | V_out | int | 1-9999 | Sum of output quantities × base_value |
| total_input_value | V_in | int | 0-9999 | Sum of input quantities × base_value (0 for gathering) |
| efficiency | η | float | 0.001-999.0 | Output value per unit cost |

**Calculation steps:**
- `V_out = sum(output.quantity × resource[output.resource_id].base_value for each output in O)`
- `V_in = sum(input.quantity × resource[input.resource_id].base_value for each input in I)`
- `η = V_out / (t + V_in)`

**Output Range:** 0.001 to 999.0 (theoretical — practical range 0.1 to 50.0 for balanced recipes)

**Example:**
```
Recipe: "Sawmill Planks"
Inputs: 1 Wood (value: 2 gold), 1 Axe charge -5 (ignore charge cost for efficiency)
Outputs: 5 Planks (value: 3 gold each)
Tick cost: 50

V_out = 5 × 3 = 15 gold
V_in = 1 × 2 = 2 gold
η = 15 / (50 + 2) = 15 / 52 = 0.288

Compare to manual recipe "Chop Tree":
Inputs: 1 Axe charge -10
Outputs: 5 Wood (value: 2 gold each)
Tick cost: 80

V_out = 5 × 2 = 10 gold
V_in = 0 (charge ignored)
η = 10 / 80 = 0.125

Conclusion: Sawmill is 2.3× more efficient than manual chopping
```

**Note:** Charge costs are excluded from efficiency calculation because they're tool *consumption*, not resource inputs. Including charge would overvalue gathering recipes (0 inputs) and undervalue advanced recipes (high tool costs but superior outputs).

---

### 3. Milestone Progress Formula

Calculates completion percentage for unlock conditions.

**The `milestone_progress` formula is defined as:**

`progress = min(1.0, sum(stockpile_fraction) / required_count)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| required_stockpiles | R | array | 1-10 items | Resources + quantities needed for milestone |
| current_storage | S | int | 0-9999 | Player's current quantity of a resource |
| required_quantity | q_req | int | 1-9999 | Milestone's required quantity for that resource |
| stockpile_fraction | f | float | 0.0-1.0 | min(1.0, S / q_req) for one resource |
| required_count | n | int | 1-10 | Number of resources in milestone |
| progress | p | float | 0.0-1.0 | Overall milestone completion (0% to 100%) |

**Calculation steps:**
- For each resource in R: `f = min(1.0, current_storage / required_quantity)`
- `sum(f for all resources) = total completion`
- `p = sum / n` (average completion across all requirements)
- Milestone unlocks when `p >= 1.0` (all requirements at 100%)

**Output Range:** 0.0 (nothing stockpiled) to 1.0 (milestone complete)

**Example:**
```
Milestone: "Bronze Age"
Requirements:
  - Wood: 50 (current: 45)
  - Stone: 30 (current: 30)
  - Fiber: 20 (current: 5)

Stockpile fractions:
  - f_wood = min(1.0, 45/50) = 0.9
  - f_stone = min(1.0, 30/30) = 1.0
  - f_fiber = min(1.0, 5/20) = 0.25

sum = 0.9 + 1.0 + 0.25 = 2.15
n = 3
p = 2.15 / 3 = 0.716... = 71.6% complete

UI displays: "Bronze Age: 71% (Wood 45/50, Stone 30/30, Fiber 5/20)"
Milestone NOT unlocked (p < 1.0)

After gathering 5 more wood + 15 more fiber:
  f_wood = 1.0, f_stone = 1.0, f_fiber = 1.0
  p = 3.0 / 3 = 1.0 → Milestone UNLOCKED
```

## Edge Cases

### Recipe Execution Failures

- **If a building is destroyed mid-recipe execution**: Recipe transitions to Failed state, all progress lost (0 ticks), inputs NOT refunded, outputs NOT produced. The NPC transitions to idle and can be reassigned. Harsh but clear — teaches players to protect production infrastructure. Matches real-world manufacturing: if a factory burns down mid-production, materials inside are lost.

- **If inputs are consumed by another system mid-recipe execution**: Recipe **restarts from 0 ticks** (per Detailed Design Rule 2). Already-consumed inputs remain consumed (not refunded). If inputs no longer available, transitions to Failed. Creates visible feedback loop — players see tick timer reset to 0 and learn to avoid input sharing between buildings.

- **If a slot's charge is fully depleted mid-recipe execution**: The slot is cleared (emptied). If no other slot of the same resource_id has sufficient charge, recipe transitions to **Unavailable** (status: "Insufficient charge"). Building/NPC remains assigned but idle. Execution does NOT automatically resume until sufficient charge is available. Makes resource depletion visible (Pillar 2: Information Transparency).

### Item Charge Selection

- **If multiple slots have identical current_charge**: Slot selection uses `first()` after sorting ascending (Formula 1). Selects the slot with the **lowest slot_index** as a deterministic tiebreaker. Prevents UI "flickering" where different slots are shown selected on each frame.

- **If no slot has sufficient charge for `charge_cost`, but multiple partially-depleted slots exist**: Recipe transitions to **Unavailable** state (status: "Insufficient charge"). The system does NOT combine charge across multiple slots to meet a single recipe input's `charge_cost`. Each input must be satisfied by a single slot. Clear failure state — player must restore charge by depositing new items of that type.

- **If resources consumed after milestone achieved but before unlock processed**: Milestones unlock **permanently** once achieved (per Detailed Design Rule 3: "unlocks permanently, no re-locking"). Consuming resources after achievement does NOT revert the unlock. Milestone state flips to "unlocked" when `progress >= 1.0` and never reverts. Prevents frustrating yo-yo behavior. Satisfactory-style design — once you hit a tier, you don't drop back if you spend resources.

- **If multiple milestones require same resource stockpile**: Each milestone evaluates independently. Stockpiling 100 wood unlocks both "50 wood milestone" and "100 wood milestone" simultaneously on the same tick. UI displays both unlock notifications. All recipes gated by either milestone become available. Rewards efficiency — why stockpile 50, spend it, then stockpile 100 again?

- **If player loads save from before milestone was unlocked**: Milestone reverts to **locked** state (save data is authoritative). Recipes gated by that milestone become unavailable again. If player has queued recipes that are now locked, those executions transition to Failed on load and are removed from queue. Save files must be self-contained and consistent.

### Milestone Unlocking

- **If multiple recipes produce the same output resource**: **Allowed and intentional**. Example: "Manual Chop Tree" and "Sawmill Process Logs" both produce wood. Both recipes remain available; player/AI chooses based on efficiency, availability, or preference. Efficiency formula (Formula 2) enables rational comparison. Pillar 3 (Optimization Over Expansion) explicitly values deep chains with choices. Production chains often have multiple paths (manual vs. automated, slow vs. fast, cheap vs. expensive).

- **If recipe consumes and produces same resource** (e.g., "Refine Wood: 5 Wood → 3 Refined Wood"): **Allowed** if inputs and outputs have different `resource_id` values ("wood" vs "refined_wood" are distinct resources). If inputs and outputs have **identical** `resource_id` (e.g., "5 Wood → 3 Wood"), validation logs **Warning: "Net-negative recipe — verify balance"** but allows the recipe to load. Refinement chains (bronze → steel → titanium) are valid gameplay. Net-negative recipes could be intentional (compacting items for storage).

### Zero-Input Recipes

- **If gathering recipe has zero inputs and low tick cost** (e.g., "Gather Berries: 0 inputs → 3 berries, 10 ticks"): Recipe is **valid** (per Detailed Design Rule 1: gathering category allows empty inputs). Load-time validation issues **Warning** if `tick_cost < 50` (per Rule 5). Recipe executes normally. Buildings with loop mode can generate infinite resources limited only by tick rate and output storage capacity. Gathering recipes ARE infinite resource generation — that's their purpose. Warning alerts designer to potential balance issues, but final judgment is designer's call.

### Storage Overflow

- **If recipe completes but output storage cannot accept full output quantity**: Recipe execution **blocks** at 99% completion (tick timer reaches `tick_cost - 1` but does not increment to `tick_cost`). Recipe remains in **In Progress** state until storage space becomes available. Once space exists, final tick completes, outputs added, execution transitions to Completed (loop mode) or Idle (single mode). Inputs remain consumed (deducted at recipe start per Rule 2). Prevents item duplication exploits (start recipe with full storage → items vanish). Blocking behavior creates visible bottleneck — player sees "99% complete, storage full" and knows to expand storage or move items.

## Dependencies

### Upstream Dependencies (Systems Recipe Database depends on)

**None.** The Recipe Database System is a Foundation-layer pure data registry with zero upstream dependencies (like Resource System and Tick System). It defines transformations but does not execute them — execution logic lives in dependent systems.

### Downstream Dependents (Systems that depend on Recipe Database)

**Primary dependents:**

1. **Production System** (#14, Vertical Slice) — **Hard dependency**
   - **Interface:** Queries building recipes (`category == "processing"`) to determine what a building can produce
   - **Data flow:** Production System reads recipe `inputs`, `outputs`, `tick_cost`, validates against storage, manages execution state machine, reports completion
   - **Nature:** Production System cannot function without Recipe Database — buildings would have no defined outputs

2. **Manual Labor System** (#12, Vertical Slice) — **Hard dependency**
   - **Interface:** Queries manual recipes (`building_requirement == null`) to present crafting options to player
   - **Data flow:** Manual Labor System reads recipe list, filters by player inventory, presents UI, executes selected recipe, blocks player actions for `tick_cost`
   - **Nature:** Without Recipe Database, player has no manual actions beyond movement

3. **Inventory/Storage System** (#14, Vertical Slice) — **Soft dependency**
   - **Interface:** Reads `charge_cost` from recipe inputs to select and deduct charge from slots
   - **Data flow:** Inventory System provides slot-level charge data; Recipe Database defines the required charge per input; Production/Manual Labor Systems orchestrate the deduction

**Secondary dependents:**

4. **Building System** (#10, Vertical Slice) — **Soft dependency**
   - **Interface:** Reads `building_requirement` field to show "Unlocks N recipes" in building tooltips
   - **Data flow:** When player hovers over buildable structure, Building System queries: "How many locked recipes have `building_requirement == this_building_id`?"
   - **Nature:** Building System's core function (placement, construction) doesn't require Recipe Database, but unlock feedback does

5. **UI Systems** (HUD #27, Building Menu #28, Crafting Menu, Milestone Tracker) — **Soft dependency**
   - **Interface:** Display recipe progress bars, unlock status, milestone progress
   - **Data flow:** Read-only queries of recipe data for presentation
   - **Nature:** UI reflects recipe state but doesn't modify it

**Future dependents (post-MVP):**

6. **Goal System** (#20, MVP) — Will write `unlock_conditions` when goals are completed
7. **Trading System** (#22, Core Experience) — Will write `unlock_conditions` when trade quests are fulfilled

### Bidirectional Consistency

Recipe Database → Production System:
- Production System GDD must reference Recipe Database as its data source
- If Production System expects additional recipe fields (e.g., `npc_skill_requirement`), those must be added to Recipe Database schema

Recipe Database → Manual Labor System:
- Manual Labor System GDD must handle recipes with 0 inputs (gathering category)
- Manual Labor System must respect `execution_mode == "single"` for all manual recipes

## Tuning Knobs

The Recipe Database System has the following designer-adjustable values:

### Registry-Level Knobs

**1. `max_recipe_count`** (integer, default: 500)
- **Purpose:** Maximum number of recipes loaded from JSON
- **Safe range:** 50-2000
- **Effect:** Limits memory footprint and load time
- **What breaks if too high:** Load time >5s, memory usage spikes
- **What breaks if too low:** Designer cannot add new recipes without removing old ones
- **Interaction:** Affects all systems that query recipes (Production, Manual Labor, UI)

---

### Validation Knobs

**2. `warn_fast_generator_threshold`** (integer, default: 50 ticks)
- **Purpose:** Triggers warning for zero-input recipes with tick_cost below this value
- **Safe range:** 20-100
- **Effect:** Detects potentially overpowered resource generators during load
- **What breaks if too high:** Misses balance issues (10-tick berry gathering goes unnoticed)
- **What breaks if too low:** False positives (60-tick balanced gathering flagged as suspicious)
- **Interaction:** Load-time validation only, doesn't affect runtime behavior

**3. `allow_zero_tick_recipes`** (boolean, default: false)
- **Purpose:** Enables or forbids recipes with `tick_cost == 0`
- **Safe range:** false (recommended) | true (advanced use only)
- **Effect:** When false, validation rejects recipes with tick_cost == 0. When true, allows instant conversion recipes (e.g., bundling items)
- **What breaks if enabled:** Potential infinite loops if recipe outputs feed back into inputs
- **What breaks if disabled:** Cannot create "organize inventory" recipes (10 planks → 1 plank bundle)
- **Interaction:** Cross-references validation Rule: "if tick_cost == 0, outputs must NOT contain inputs"

---

### Milestone Knobs

**4. `milestone_unlock_delay_ticks`** (integer, default: 0)
- **Purpose:** Artificial delay between milestone achievement and recipe unlock (for pacing control)
- **Safe range:** 0-1000
- **Effect:** When player achieves milestone, recipes unlock after N ticks
- **What breaks if too high:** Frustrating delay ("I stockpiled the resources, why can't I use the recipe?")
- **What breaks if too low:** No issue — 0 is instant unlock (default)
- **Interaction:** Affects UI milestone notification timing

**5. `milestone_progress_update_frequency`** (enum, default: "on_storage_change")
- **Purpose:** When to recalculate milestone progress formula
- **Options:** "every_tick" | "on_storage_change" | "manual"
- **Safe range:** "on_storage_change" (best performance-to-responsiveness balance)
- **Effect:**
  - "every_tick" = check all milestones every tick (1000x/day) — precise but CPU-intensive
  - "on_storage_change" = check when storage quantities change — efficient, imperceptible lag
  - "manual" = only check when player opens milestone UI — lowest CPU, stalest data
- **What breaks if too frequent:** CPU spike on large recipe sets (100+ milestones × 5 stockpile checks × 60 FPS = 30k checks/sec)
- **What breaks if too infrequent:** Milestones don't unlock until player manually checks progress
- **Interaction:** Affects UI responsiveness and frame budget

---

### Execution Knobs

**6. `recipe_restart_on_input_loss`** (boolean, default: true)
- **Purpose:** Whether recipes restart from 0 when inputs consumed mid-execution (Detailed Design Rule 2)
- **Safe range:** true (harsh but clear) | false (pause and resume)
- **Effect:** When false, recipes pause at current tick progress and resume when inputs replenished. When true, recipes restart from 0.
- **What breaks if enabled (true):** Player frustration when two buildings compete for same input (sawmill resets to 0 when bakery consumes wood)
- **What breaks if disabled (false):** Exploit: start expensive recipe, consume inputs elsewhere, recipe completes for free
- **Interaction:** Affects Production System execution state machine

**7. `storage_overflow_blocks_completion`** (boolean, default: true)
- **Purpose:** Whether recipes block at 99% when output storage is full (Edge Case: Storage Overflow)
- **Safe range:** true (prevents duplication) | false (outputs vanish)
- **Effect:** When true, recipe halts until space available. When false, recipe completes and excess outputs are discarded.
- **What breaks if enabled (true):** Buildings "stuck" at 99% can confuse players ("why isn't my sawmill working?")
- **What breaks if disabled (false):** Item duplication exploits, resources vanish silently
- **Interaction:** Affects UI status displays, Production System loop logic

---

### Cross-Knob Interactions

- **`max_recipe_count` + `milestone_progress_update_frequency`**: High recipe count (500+) + "every_tick" frequency = performance bottleneck. If max_recipe_count > 200, force frequency to "on_storage_change".
- **`allow_zero_tick_recipes` + validation**: If enabled, must also enable feedback-loop detection (outputs ∩ inputs == ∅). These knobs are coupled.
- **`recipe_restart_on_input_loss` + `storage_overflow_blocks_completion`**: Both enabled (default) creates harsh but transparent system. Disabling both creates lenient but exploit-prone system. Mixing (one true, one false) creates asymmetric behavior that may confuse players.

## Visual/Audio Requirements

[To be designed]

## UI Requirements

[To be designed]

## Acceptance Criteria

### Core Functionality (Blocking — Required for Logic Story Completion)

1. **GIVEN** the game starts fresh, **WHEN** the recipe registry loads, **THEN** all recipes pass validation (unique IDs, valid resource references, outputs.length >= 1, tick_cost >= 1)

2. **GIVEN** a gathering recipe with 0 inputs and tick_cost 40, **WHEN** player executes it, **THEN** outputs are produced without consuming any inputs

3. **GIVEN** a crafting recipe requiring 2 Wood + 1 Stone, **WHEN** player has exactly those resources and executes the recipe, **THEN** inputs are deducted at start, tick timer counts to tick_cost, outputs are added at completion

4. **GIVEN** a building recipe in loop mode with inputs for 3 iterations (6 Wood available, recipe consumes 2 Wood/iteration), **WHEN** NPC assigned and recipe started, **THEN** recipe executes exactly 3 times (consuming all 6 Wood), then stops with status "Inputs Exhausted"

5. **GIVEN** a recipe input with `charge_cost: 5.0` for axe, **WHEN** storage has Slot A (axe, current_charge 12.0) and Slot B (axe, current_charge 435.0), **THEN** system selects Slot A (lowest charge) and reduces it from 12.0 to 7.0

6. **GIVEN** a milestone requiring 50 Wood + 30 Stone, **WHEN** player stockpiles exactly 50 Wood and 30 Stone, **THEN** milestone unlocks and all gated recipes become available permanently

7. **GIVEN** a recipe at tick 25 of 50, **WHEN** another system consumes the recipe's inputs, **THEN** recipe tick counter resets to 0 AND status changes to "Restarting" AND recipe requires full inputs again to proceed

8. **GIVEN** a building recipe with tick_cost 50 producing 5 planks, **WHEN** tick reaches 49 AND output storage has space for only 2 planks (insufficient for 5), **THEN** tick stays at 49 (does NOT increment to 50) AND status shows "Storage Full" AND outputs NOT added until space becomes available

9. **GIVEN** two recipes both producing Wood (manual chop 80 ticks + sawmill 50 ticks), **WHEN** player queries available recipes, **THEN** both appear in list with different efficiency ratings (sawmill η > manual η per Formula 2)

10. **GIVEN** a recipe with tick_cost 0 in recipes.json, **WHEN** registry loads with tuning knob allow_zero_tick_recipes=false, **THEN** validation rejects the recipe and logs error "tick_cost must be >= 1"

### Item Charge Consumption (Blocking)

11. **GIVEN** a recipe input with `charge_cost: 20.0` for axe AND the only slot has current_charge 15.0 (insufficient), **WHEN** player attempts to execute recipe, **THEN** recipe transitions to Unavailable AND slot is NOT modified AND status message shows "Insufficient charge"

12. **GIVEN** a recipe input with `charge_cost: 15.0` AND a slot has exactly current_charge 15.0, **WHEN** recipe executes to completion, **THEN** slot.current_charge becomes 0.0 AND slot is cleared (resource_id = null, quantity = 0)

13. **GIVEN** Slot A (axe, current_charge 50.0, slot_index 3) AND Slot B (axe, current_charge 50.0, slot_index 7), **WHEN** recipe needs charge_cost 10.0, **THEN** Slot A selected (lower slot_index as tiebreaker per Formula 1)

### Recipe Execution Failures (Blocking)

14. **GIVEN** a building recipe at tick 30 of 50, **WHEN** building is destroyed (demolished, fire, etc.), **THEN** recipe transitions to Failed status, tick progress lost, inputs NOT refunded, outputs NOT produced, NPC transitions to idle

15. **GIVEN** a recipe blocked at tick 49/50 due to storage full, **WHEN** storage space becomes available (5+ empty slots), **THEN** tick increments to 50, outputs added to storage, recipe completes and transitions to Completed (loop mode) or Idle (single mode)

### Milestone Unlocking (Blocking)

16. **GIVEN** milestone unlocked at stockpile [50 Wood, 30 Stone], **WHEN** player consumes resources down to [10 Wood, 5 Stone], **THEN** milestone remains unlocked AND gated recipes remain available (no re-locking per Edge Case: Milestone Unlocking)

17. **GIVEN** milestone_A requires 50 Wood AND milestone_B requires 100 Wood, **WHEN** player stockpiles 100 Wood, **THEN** both milestones unlock simultaneously on same tick AND UI shows both unlock notifications

### Save/Load Persistence (Advisory — Integration Testing)

18. **GIVEN** a recipe in-progress at tick 35 of 50 with inputs consumed, **WHEN** game saved and reloaded, **THEN** recipe resumes at tick 35 with same inputs/outputs state

19. **GIVEN** 2 milestones unlocked in current session, **WHEN** save loaded from before unlocks occurred, **THEN** milestones revert to locked state AND gated recipes become unavailable

### Execution Modes (Advisory)

20. **GIVEN** manual recipe with execution_mode "single", **WHEN** player executes it and it completes, **THEN** recipe completes once and stops (does NOT automatically loop)

21. **GIVEN** building recipe with execution_mode "loop" and inputs for 5 iterations, **WHEN** NPC executes it, **THEN** recipe repeats automatically 5 times until inputs exhausted, then stops

### Validation Warnings (Advisory)

22. **GIVEN** gathering recipe with tick_cost 10 (below warn_fast_generator_threshold default 50), **WHEN** registry loads, **THEN** validation logs WARNING "Fast resource generator — verify balance" but recipe loads successfully

## Visual/Audio Requirements

**Foundation/Infrastructure Note:** The Recipe Database System is pure data infrastructure — it has no direct visual or audio output. Players never see the JSON file or interact with the database directly. However, systems that *use* the Recipe Database (Production, Manual Labor, UI) have visual and audio requirements tied to recipe execution.

**Indirect Visual Requirements (for dependent systems):**
- **Recipe progress bars** (Production/Manual Labor Systems): Visual tick timer showing X/Y ticks completed
- **Recipe status indicators** (Building panel UI): Color-coded states (Available=green, In Progress=yellow, Failed=red, Unavailable=gray)
- **Milestone progress UI** (Milestone Tracker): Progress bar per milestone showing stockpile completion percentage (Formula 3)
- **Item charge visualization** (Inventory UI): Charge bar on tool icons, changes color when low (<20%)

**Indirect Audio Requirements (for dependent systems):**
- **Recipe completion sound** (Production System): SFX when recipe transitions to Completed state (distinct sound per recipe category: gathering=rustle, crafting=clink, processing=thunk)
- **Milestone unlock sound** (Goal System): SFX + music sting when milestone achieved
- **Recipe failure sound** (Production/Manual Labor): Error SFX when recipe transitions to Failed (building destroyed, tool broken)

**No art bible requirements** — Recipe Database is data-only. Visual specifications belong to systems that render recipe data.

## UI Requirements

**Crafting Menu (Manual Labor System dependency):**
- Must display filtered recipe list: only manual recipes (`building_requirement == null`) where player has sufficient inputs
- Recipe card shows: icon, display_name, inputs (with quantities), outputs (with quantities), tick_cost, unlock status
- Grayed-out locked recipes with lock icon + unlock condition tooltip ("Stockpile 50 Wood to unlock")
- Sort options: by category, by efficiency, by tick_cost

**Building Panel (Production System dependency):**
- Must show all recipes where `building_requirement == selected_building_id`
- Recipe execution state visible: tick progress bar (X/Y), status string, loop indicator (if execution_mode == "loop")
- Input/output preview: shows required inputs and produced outputs with current storage quantities
- "Insufficient charge" indicator when recipe Unavailable due to a `charge_cost` input not being satisfiable

**Milestone Tracker UI:**
- Must display all milestones with unlock progress (Formula 3)
- Per-milestone card shows: milestone_id (human-readable name), required_stockpiles list with current/required quantities, overall progress percentage
- Color-coded: <50% = red, 50-99% = yellow, 100% = green (unlocked)
- Clicking a milestone shows all recipes it unlocks

**Tooltip/Hover UI (all systems):**
- Recipe hover: shows full details (inputs, outputs, tick_cost, building_requirement, unlock_conditions)
- Milestone hover: shows progress breakdown per resource
- Item hover: shows current_charge, slot max charge, and tags

**📌 UX Flag — Recipe Database System**: This system has UI requirements defined above. In Phase 4 (Pre-Production), run `/ux-design` to create UX specs for Crafting Menu, Building Panel, and Milestone Tracker **before** writing epics. Stories that reference these UI elements should cite `design/ux/[screen].md`, not the GDD directly.

## Open Questions

**None for Vertical Slice / MVP.** All design decisions have been resolved:
- ✅ Recipe schema finalized (11 required + 2 optional attributes)
- ✅ Unlock system defined (Satisfactory-style milestones, stockpile-based)
- ✅ Execution modes specified (single vs loop)
- ✅ Tool consumption mechanics locked in (tag-based matching, use damaged first)
- ✅ Edge cases resolved (22 acceptance criteria cover all identified cases)

**Future Considerations (post-MVP, noted for reference):**
1. **Alternative inputs** — Deferred to post-MVP. If implemented, add `alternative_inputs` array to schema where each input has `alternatives: [{resource_id, quantity, charge_cost}]`
2. **By-products** — Deferred to post-MVP. If implemented, add `is_byproduct: bool` flag to outputs
3. **Recipe repair mechanics** — Deferred to post-MVP. If implemented, create new recipe category `"repair"` with special handling for tool restoration
4. **Conditional outputs** (e.g., 80% chance for 5 planks, 20% chance for 4 planks + 1 sawdust) — Not planned. Would break determinism principle.
5. **Recipe prerequisites** (e.g., "must have crafted Tool A before unlocking Recipe B") — Possible via unlock_conditions if `"type": "recipe_crafted_count"` is added
6. **NPC skill multipliers** (skilled NPCs reduce tick_cost) — Requires `skill_multiplier_effect` attribute added to schema. Coordinate with Bevölkerungstier System GDD when designed.
