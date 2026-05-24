# Hunger System

> **Status**: In Design
> **Author**: User + Claude (Sonnet 4.6)
> **Status**: Design Complete
> **Last Updated**: 2026-05-12
> **Implements Pillar**: Pillar 1 (Earned Automation), Pillar 2 (Information Transparency)

## Overview

The Hunger System is the village's daily bread ballot — a simple, relentless ledger that tallies one food unit per mouth, every day, and makes the cost of expansion painfully clear. When your first NPC arrives, you gain one worker. You also gain one more mouth to feed. Hunger is the tension between growth and sustainability: every NPC you recruit is leverage, but also responsibility. If food runs out, the entire village slows — player actions and NPC production both suffer a -50% debuff. There is no death, no game-over screen, just the meditative pressure of "can I automate food production fast enough?" Hunger is the reason automation matters. Without it, the player could manually gather everything forever; with it, the player *must* automate, and earns that automation through the struggle of staying fed.

## Player Fantasy

You earned automation through consequence, not explanation.

Yesterday you only had to feed yourself. Today an NPC appeared in the new house, and the daily tally just grew by one. You look at your berry stash. It was enough yesterday. It isn't today. This is the first time the game asks you to think about tomorrow instead of right now, and it happens so quietly you might not even notice the shift until you're already planning a garden.

Hunger is the game's way of introducing systemic thinking without a single line of tutorial text. You don't learn "each NPC consumes 1 food per day" from a pop-up — you learn it by staring at your jar of berries at day transition and realizing one fewer means tomorrow. The knowledge comes from consequence, not explanation. That's earned understanding (Pillar 1), and it sticks.

The debuff is the sound of a system telling you it's out of equilibrium. All your actions slow to half-speed, the Lumber Camp takes twice as long to produce logs, your own axe feels heavier. It doesn't feel like failure. It feels like physics — you dropped a support beam on a bridge, of course it sags. The satisfaction of fixing it is the first time you feel what optimization actually means: you stopped reacting. You started designing.

Reference: Factorio's first bottleneck moment — when your coal consumption outpaces your coal mining and the furnaces start starving. Anno's quiet panic when your food surplus shrinks below what your population needs. Both games nail the feeling this system delivers: growth has a cost, and understanding that cost is earned through living it.

## Detailed Design

### Core Rules

**Rule 1: Daily Food Consumption**
At each day transition (Tick System `day_transition` signal, tick 1000 → tick 0), the Hunger System requests food deduction via the Inventory/Storage System's `consume_food(daily_food_requirement)` interface (Formula 5). The daily food requirement is calculated as:

`daily_food_requirement = npc_count × npc_food_unit`

Where:
- `npc_count` = number of active, recruited NPCs (from NPC System)
- `npc_food_unit` = 1.0 food unit per NPC (at VS scope — Population Tier System will define tier-based consumption later)

The player does NOT consume food in the daily tally. The player has the Energy system (Player Character System) — eating refills energy, not hunger. Only NPCs have a daily food requirement.

**Rule 2: Food Unit Values**
Different food items count as different amounts of food units:
- **1 Berry** = 1 food unit
- **1 Bread** = 2 food units
- Future food items: defined in the Recipe Database System

Each NPC requires 1 food unit per day. This means 1 bread satisfies 2 NPCs' daily needs.

**Rule 3: Debuff Activation and Deactivation**
The hunger debuff (-50% speed, 2× tick cost, no output change) applies when the village is HUNGRY at day transition. The debuff affects:
- **Player actions:** All manual actions cost 2× tick cost. Output quantity is unchanged by hunger (energy depletion separately reduces output to 50%). The player's Energy depletion penalty and the hunger debuff are **separate modifiers** that stack multiplicatively. (See Formulas.)
- **NPC buildings:** Production cycles take 2× ticks (100 ticks → 200 ticks). Output quantity is unchanged.

The NPC-side debuff persists until the next successful day transition (village FED). The player-side debuff from hunger clears when the village has sufficient food (next successful `consume_food()` at day transition). The player's Energy depletion debuff is separate and clears when the player eats (energy rises above 0 per PC System Rule 2).

**Rule 4: NPC Count**
- **Player:** Not counted in daily food requirement. The player manages energy, not hunger.
- **NPCs:** Count of NPCs in any active state (IDLE, TRAVEL_TO_BUILDING, WORK_AT_BUILDING, TRAVEL_TO_STORAGE, DEPOSIT, RETURN_TO_BASE, WAITING). Removed NPCs do not count.

**Rule 5: Consumption Order**
The Inventory/Storage System handles all food deduction via Formula 5. The Hunger System provides the `daily_food_requirement` argument and receives back `{hunger_debuff_applied: bool, ...}`. The Hunger System never defines its own deduction algorithm.

**Rule 6: No Death — Debuff Only (Design Decision)**
NPCs never die from starvation. The -50% debuff is the sole consequence of food shortage. This is a deliberate design choice: the game is about optimization, not survival. The pressure is "can I automate fast enough?" — not "can I avoid losing my workforce?" This keeps the experience meditative and correctable rather than punishing and irreversible. NPCs that are HUNGRY work slower and the player works slower; the village continues to function at reduced capacity until food is restocked. The debuff clears immediately at the next successful day transition — there is no lasting damage.

**Rule 7: Scope at Vertical Slice**
- All recruited NPCs count toward daily requirement from day 1
- No tiered NPC consumption (all NPCs = 1 food unit/day)
- Perk System interaction deferred

### States and Transitions

| State | Condition | Transition Trigger | Effect |
|-------|-----------|-------------------|--------|
| **FED** | Available food units ≥ daily food requirement (NPCs only) | Day transition where consumption was successful | No debuff. |
| **HUNGRY** | Available food units < daily food requirement | Day transition where `consume_food()` returns `hunger_debuff_applied: true` | Debuff active: -50% speed (2× tick cost, no output change) for player and NPCs. |

**Transition rules:**
- **FED → HUNGRY:** Fires when day transition consumption fails (deficit > 0).
- **HUNGRY → FED:** Fires on the next `day_transition` where consumption succeeds. For the player, the debuff also clears immediately when energy rises above 0 (Player Character System Rule 2).

### Interactions with Other Systems

| System | Direction | Interaction | Data Flow | Interface |
|--------|-----------|-------------|-----------|-----------|
| **Inventory/Storage System** | Hunger delegates to | Delegates food deduction. | Hunger → Inventory: `consume_food(daily_food_requirement)`. Inventory → Hunger: `{hunger_debuff_applied: bool, ...}`. | Owned by Inventory. |
| **Tick System** | Hunger subscribes to | Receives `day_transition` signal. | Tick → Hunger: `day_transition()`. | Owned by Tick. |
| **NPC System** | Bidirectional | Hunger needs NPC count. NPC buildings consume debuff state. | NPC → Hunger: `get_npc_count()`. Hunger → NPC: `hunger_debuff_active: bool`. | Shared. |
| **Player Character System** | Hunger reads | Reads energy state for combined modifier display. Player uses food for energy (PC System). Hunger debuff is separate from energy depletion. | Hunger → PC: `energy_state()` (reads PC's existing HUD interface, no new PC API needed). Hunger → PC: `hunger_debuff_active: bool`. | Shared. |
| **Building System** | Hunger writes to | Building System reads debuff state to modify production cycle duration. | Hunger → Building: `on_hunger_debuff_change(active: bool)`. | Owned by Building. |
| **Population Tier System (deferred)** | Hunger reads | Future: tier-based consumption rates. | Tier → Hunger: `get_npc_consumption_rates()`. | Deferred. |
| **HUD System** | Hunger writes to | HUD displays food status and debuff indicator. | Hunger → HUD: `hunger_state(fed: bool, food_available: int, food_required: int)`. | Owned by HUD. |

## Formulas

### Formula 1: Daily Food Requirement

The `daily_food_requirement` formula is defined as:

`daily_food_requirement = npc_count × npc_food_unit`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| npc_count | N | int | 0–50 | Number of active, recruited NPCs from NPC System |
| npc_food_unit | F | float | 1.0 | Food units consumed per NPC per day (1.0 at VS; future tiers modify this) |
| daily_food_requirement | D | float | 0.0 | Total food units required for one day |

**Output Range:** [0, 50] food units at VS scope.

**Example (Day 2, 2 NPCs):**
```
N = 2, F = 1.0
D = 2 × 1.0 = 2.0 food units required
```

**Example (Day 1, 0 NPCs):**
```
N = 0, F = 1.0
D = 0 × 1.0 = 0 food units required
```

**Notes:**
- The player is NOT included in this calculation. The player's food consumption is handled through the Energy system (Player Character System Rule 6).
- At VS scope, all NPCs consume the same amount (1.0 unit). Tier-based consumption is deferred to Population Tier System.
- The Inventory/Storage System uses this value as the `daily_food_requirement` argument to `consume_food()`.

---

### Formula 2: Combined Debuff Stack

When both Energy depletion and hunger debuff are active, their effects stack multiplicatively:

`effective_tick_cost = base_tick_cost × depletion_tick_multiplier × hunger_tick_multiplier`
`effective_output = max(1, ceil(base_output × depletion_output_multiplier × 1.0))`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| base_tick_cost | T_base | int | 5–200 | Tick cost from action table (Player Character System Rule 3) |
| base_output | O_base | int | 1–5 | Expected output from action table |
| depletion_tick_multiplier | M_depl | float | 2.0 | From Player Character System (0 Energy penalty) |
| depletion_output_multiplier | M_depl_out | float | 0.5 | From Player Character System (0 Energy output penalty) |
| hunger_tick_multiplier | M_hung | float | 2.0 | Hunger System debuff (2× tick cost when HUNGRY) |
| hunger_output_multiplier | M_hung_out | float | 1.0 | Hunger does NOT modify output, only tick cost |
| effective_tick_cost | T_eff | int | 5–800 | Combined tick cost under both debuffs |
| effective_output | O_eff | int | 1–2 | Combined output under both debuffs |

**Output Range:** T_eff ∈ [5, 800] (4× baseline). O_eff ∈ [1, 2] (max 2× reduction).

**Example (single debuff — only hunger):**
```
Chop Tree: T_base = 80, O_base = 5
T_eff = 80 × 2.0 (hunger) = 160 ticks
O_eff = max(1, ceil(5 × 1.0)) = 5 (hunger doesn't affect output)
```

**Example (single debuff — only energy depletion):**
```
Chop Tree: T_base = 80, O_base = 5
T_eff = 80 × 2.0 (depletion) = 160 ticks
O_eff = max(1, ceil(5 × 0.5)) = max(1, 3) = 3
```

**Example (both debuffs active):**
```
Chop Tree: T_base = 80, O_base = 5
T_eff = 80 × 2.0 × 2.0 = 320 ticks (4× baseline)
O_eff = max(1, ceil(5 × 0.5 × 1.0)) = max(1, 3) = 3 (output penalty from depletion only)
```

**Design notes:**
- Hunger affects **tick cost only** (productivity penalty), not output quantity.
- Energy depletion affects **both tick cost AND output**.
- When only hunger is active, output is unchanged (5 from chop tree).
- The hunger multiplier is always 2.0 (not 1.5 or 1.0 — binary: you're either hungry or you're not).

---

### Formula 3: Food Unit Conversion

Each food item contributes a different number of food units toward daily consumption. This formula maps "item consumed" to "food units credited."

`food_units_from_item(resource_id, quantity) = quantity × resource_food_unit(resource_id)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| quantity | q | int | 0–∞ | Number of food items consumed from storage |
| resource_food_unit(r) | F_r | float | 0.5–4.0 | Food units per unit of resource `r`, defined in Recipe Database System or resource registry |
| food_units | F | float | 0.0–∞ | Total food units credited toward daily requirement |

**VS food items:**
| Resource | Food Units per Item |
|----------|---------------------|
| Berry | 1.0 |
| Bread | 2.0 |

**Example (1 berry consumed):**
```
q = 1, F_r(berry) = 1.0
food_units = 1 × 1.0 = 1.0 food unit
```

**Example (1 bread consumed):**
```
q = 1, F_r(bread) = 2.0
food_units = 1 × 2.0 = 2.0 food units (satisfies 2 NPCs' daily needs)
```

**Inventory/Storage integration:** In Formula 5 (`consume_food`), the deduction phase uses this formula to credit food units. When consuming from a food-eligible slot, the actual food units deducted from `total_to_consume` equals `consume_from_slot × resource_food_unit(slot.resource_id)`, not `consume_from_slot`.

---

### Formula 4: Days of Food Remaining

The `days_of_food_remaining` formula provides a player-facing estimate of how many days of food the village has:

`days_of_food_remaining = floor(total_food_units / daily_food_requirement)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| total_food_units | F_total | float | 0–∞ | Sum of food units across all storage containers (1 berry = 1, 1 bread = 2) |
| daily_food_requirement | D | float | 0–∞ | From Formula 1 |
| days_of_food_remaining | R | int | 0–∞ | Estimated days until food exhaustion |

**Output Range:** [0, 9999]. Floor of 0 = 0. Division by zero guard: if D = 0, return 9999 (aliased as `HUNGER_INFINITY`; HUD displays "Unlimited"). No NPCs = infinite food security.

**Example (30 berries, 2 NPCs):**
```
F_total = 30, D = 2
R = floor(30 / 2) = 15 days of food remaining
```

**Example (3 berries, 2 NPCs):**
```
F_total = 3, D = 2
R = floor(3 / 2) = 1 day of food remaining (enough for today, insufficient tomorrow)
```

**Example (0 NPCs):**
```
D = 0
Guard: return 9999 (HUNGER_INFINITY — no consumption, no risk)
```

**Usage:** This formula is used by the HUD System to display food status to the player (e.g., "3 days of food remaining" or "⚠️ Running low"). It is NOT used by gameplay logic — only for player-facing information.

**Output Guard:** If `D == 0` (no NPCs), return 9999 (`HUNGER_INFINITY`). The HUD displays "Unlimited" in this case. This guard prevents division by zero on Day 1 before NPC recruitment.

## Edge Cases

- **If food requirement is 0 (no NPCs):** The hunger system consumes nothing, applies no debuff, and remains in FED state indefinitely. The `consume_food()` algorithm in Inventory/Storage receives a requirement of 0 and exits immediately without scanning containers. This is the natural state on Day 1 before any NPCs are recruited.
- **If food requirement is 0 and then NPCs spawn mid-day:** The requirement is only evaluated at day transition. NPCs spawned during the day do not trigger a mid-day consumption event. The first evaluation with the new NPC count happens at the next day transition. This is consistent with the "once per day" billing model.
- **If a food item type is consumed as a food source but does not exist in any storage container:** The Inventory/Storage System's Formula 5 skips all slots (no food-eligible slots found). The total found is 0, which is < daily requirement, and the debuff is applied. This is correct behavior — no food means hungry.
- **If all food is consumed and a deficit remains:** The debuff is applied. The Inventory/Storage System clears any partially-consumed slots (sets `resource_id = null` when quantity reaches 0). No partial food units are tracked — if you need 2 units and have 1 berry (1 unit), the entire 1 berry is consumed and the deficit is 1. The system does not "owe" the village a partial unit.
- **If the player eats food while HUNGRY but NPCs are still unsatisfied:** The player's energy is restored and the player's debuff clears immediately. However, the NPC-side debuff persists because `consume_food()` at the next day transition will return `hunger_debuff_applied: true`. The player benefits from eating, but NPC buildings remain slowed until the village has enough food for all NPCs. This creates the key tension: "I can eat to work faster, but that uses food my NPCs need."
- **If all food is consumed from multiple containers:** The Inventory/Storage System's Formula 5 scans all containers, deducts from lowest-quantity slots first, clears empty slots (`resource_id = null`), and returns `remaining_deficit > 0`. The deficit is a positive integer indicating how many food units were short.
- **If a container is demolished while it holds food:** Food in the container is lost. The total `total_food_units` decreases, potentially dropping below the daily requirement and triggering the debuff. This is intentional — storage management matters.
- **If the same day transition fires twice (tick overflow or bug):** The Tick System guarantees `day_transition` fires exactly once per 1000-tick cycle. Guard: `consume_food()` checks that `tick mod 1000 == 0` before consuming — a no-op if invoked outside transition. This defensive check prevents double-deduction from engine-level signal bugs.
- **If food units equal the exact daily requirement (no surplus):** The debuff is NOT applied. `remaining_deficit = 0`, `hunger_debuff_applied = false`. The village is FED but has zero buffer. One bad day (harvest failure, unexpected NPC spawn) and the debuff triggers. This reinforces the "plan ahead" fantasy.
- **If the Inventory/Storage System is offline or its interface is broken:** Defensive fallback — if `consume_food()` returns null or errors, the hunger system defaults to `hunger_debuff_applied: true` (assume hungry if we can't verify fed). This prevents silent incorrect behavior where the village is actually starving but the system thinks it's fed.

## Dependencies

| System | Direction | Nature | Interface |
|--------|-----------|--------|-----------|
| **Inventory/Storage System** | Hunger reads | **Hard** — no consumption without it | `consume_food(requirement)` |
| **Tick System** | Hunger reads | **Hard** — triggers daily consumption | `day_transition` |
| **NPC System** | Bidirectional | **Hard** — needs NPC count, provides debuff state | `get_npc_count()`, `hunger_debuff_active` |
| **Player Character System** | Hunger reads | **Hard** — reads energy state for combined modifier display | `energy_state()` (PC's existing HUD interface), `hunger_debuff_active` |
| **Building System** | Hunger writes | **Hard** — buildings consume debuff to modify production | `on_hunger_debuff_change(active: bool)` |
| **HUD System** | Hunger writes | **Soft** — displays food status (can work without) | `hunger_state(fed, food_available, food_required)` |
| **Population Tier System** | Hunger reads | **Deferred** — future tier-based consumption | `get_npc_consumption_rates()` |

## Tuning Knobs

| Knob | Symbol | Default | Safe Range | Effect | Formula Ref |
|------|--------|---------|------------|--------|-------------|
| **Food unit per berry** | `berry_food_unit` | 1.0 | 0.5–2.0 | How much a single berry satisfies. Lower = berries less useful, bread more valuable. Higher = easy to sustain 1 NPC with berries alone. | Formula 3 |
| **Food unit per bread** | `bread_food_unit` | 2.0 | 1.0–4.0 | How much a single bread satisfies. Higher = bread is a luxury (fewer needed but more complex chain). Ratio to berry defines food tier strategy. | Formula 3 |
| **NPC food consumption per day** | `npc_food_unit` | 1.0 | 0.5–2.0 | How much each NPC consumes daily. Higher = food pressure comes sooner, automation is more urgent. Lower = slower pressure, more time to explore. | Formula 1 |
| **Hunger debuff tick multiplier** | `hunger_tick_multiplier` | 2.0 | 1.5–3.0 | How much slower actions become when hungry. Higher = stronger incentive to feed NPCs. Below 1.5 = hunger feels meaningless. Above 3.0 = hungry feels like a hard lock. | Formula 2 |
| **Consumption evaluation frequency** | `consumption_interval_ticks` | 1000 | 500–2000 | How often food is deducted. At 1000 = once per day. Lower = more frequent checks (tighter pressure), higher = less frequent (looser pressure). | Rule 1 |

**Notes on knob interdependence:**
- `berry_food_unit` and `bread_food_unit` form a single ratio knob. The recommended ratio is 1:2. Extreme ratios (1:1 or 1:3) change the food strategy entirely.
- `npc_food_unit` × `npc_count` = total daily pressure. At 2 NPCs and 1.0 unit/NPC, the player needs 2 food units/day — roughly 10 berries or 5 breads for a 5-day stretch. This is the default "feel zone" for the VS arc.
- `hunger_tick_multiplier` is independent of `depletion_tick_multiplier` from the Player Character System. Both default to 2.0, so the combined 4× effect is consistent with the intent: being hungry AND exhausted should feel dramatically worse than either alone.
- `consumption_interval_ticks` × `day_transition`: At 1000, consumption fires once per day (aligned with Tick System's `day_transition`). At 500, consumption fires twice per day — the Hunger System must maintain its own independent counter since `day_transition` still fires only once per 1000 ticks. At 2000, consumption fires once per 2 days. Values other than 1000 require the Hunger System to track its own `ticks_since_last_consumption` counter.

## Visual/Audio Requirements

The Hunger System is an infrastructure system — it doesn't produce direct visual or audio events. Its effects are communicated through other systems:

| System | How Hunger is communicated | Detail |
|--------|---------------------------|--------|
| **HUD System** | Food status indicator (surplus/deficit) | "X days of food remaining" or "⚠️ Running low" |
| **HUD System** | Debuff indicator | When HUNGRY, shows "HUNGRY — actions slowed" near energy bar |
| **Building System** | Production cycle visibly slower | NPC buildings take 2× time to produce |
| **Player Character System** | Action progress bars fill slower | Manual actions take 2× time when HUNGRY |

No direct hunger-specific visual or audio is needed beyond these indirect indicators.

## Acceptance Criteria

All acceptance criteria are independently testable. A QA tester should be able to run each test and mark PASS or FAIL.

### Core Mechanics

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC-1 | GIVEN 0 NPCs, WHEN day transition fires, THEN `consume_food(0)` returns no debuff and the village remains FED | Automated: mock NPC System returning 0, fire day transition, assert state = FED |
| AC-2 | GIVEN 2 NPCs and 3 food units in storage, WHEN day transition fires, THEN 2 food units are consumed and the village remains FED | Automated: place 3 berries in storage, fire day transition, assert storage has 1 berry, state = FED |
| AC-3 | GIVEN 2 NPCs and 1 food unit in storage, WHEN day transition fires, THEN 1 food unit is consumed, remaining_deficit = 1, and the village enters HUNGRY state | Automated: place 1 berry in storage, fire day transition, assert 1 berry consumed, deficit = 1, state = HUNGRY |
| AC-4 | GIVEN 2 NPCs and 0 food (HUNGRY state), WHEN 2 berries are added to storage and the next day transition fires, THEN 2 food units are consumed and the village returns to FED state with the debuff cleared | Manual: create HUNGRY state → add 2 berries → advance day → verify FED |
| AC-5 | GIVEN the village is HUNGRY, WHEN exactly enough food exists (food == requirement), THEN the debuff is NOT applied and the village remains FED | Automated: 2 NPCs, 2 berries → fire transition → state = FED, deficit = 0 |

### Debuff Behavior

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC-6 | GIVEN the village is HUNGRY, WHEN a manual action is executed, THEN the tick cost is `base_tick_cost × 2` (no output change from hunger) | Automated: set HUNGRY, execute action with base_tick_cost=80, assert tick_cost = 160, output unchanged |
| AC-7 | GIVEN the village is HUNGRY, WHEN the NPC has 0 Energy (energy depleted), THEN both debuffs stack multiplicatively: `tick_cost = base × 2 × 2 = base × 4` | Automated: set HUNGRY + 0 Energy, execute action with base=80, assert tick_cost = 320 |
| AC-8 | GIVEN the village is HUNGRY, WHEN an NPC building executes, THEN the production cycle takes 2× ticks | Automated: set HUNGRY, assign NPC to building with 100-tick cycle, assert cycle completes at 200 ticks |
| AC-9 | GIVEN the player eats food while HUNGRY (but NPCs remain unsatisfied), THEN the player's energy depletion debuff clears but the NPC-side debuff persists | Automated: set HUNGRY + 0 Energy → eat food → player actions use normal tick cost, NPC buildings still at 2× |
| AC-19 | GIVEN the player is HUNGRY and 0 Energy, WHEN player eats 1 berry from storage, THEN player's actions use normal tick cost (energy restored) but the village remains HUNGRY (NPC debuff persists, 1 less food unit available for NPCs) | Automated: mock state HUNGRY + Energy=0 → consume 1 berry → assert player tick multiplier = 1.0, hunger state = HUNGRY, storage food = original - 1 |

### Consumption Priority

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC-10 | GIVEN two storage containers with food quantities [3 berries, 50 bread], WHEN hunger consumes 10 units, THEN the 3-berry slot is emptied first, then 2 bread units | Automated: mirror Inventory/Storage Formula 5 test, assert consumption order = lowest-quantity-first |
| AC-11 | GIVEN two food slots with equal quantity (5 berries each) at slot indices 3 and 1, WHEN hunger consumes, THEN slot index 1 is consumed first | Automated: two slots with quantity=5, different indices, assert lower index consumed first |

### Edge Cases

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC-12 | GIVEN no NPCs on Day 1, WHEN day transition fires, THEN consume_food(0) exits immediately, no debuff applied, state = FED | Automated: mock NPC System returning 0, fire transition, assert no storage scan, state = FED |
| AC-13 | GIVEN 1 NPC spawned mid-day (after day transition), THEN the consumption does NOT fire until the next day transition | Manual: recruit NPC mid-day, verify no immediate food deduction, verify deduction fires at next day transition |
| AC-14 | GIVEN `consume_food()` is called outside a day transition (tick mod 1000 != 0), THEN it returns immediately as a no-op | Automated: call consume_food at tick 500, assert no food consumed, no state change |
| AC-15 | GIVEN the Inventory/Storage System's `consume_food()` interface returns an error, THEN the hunger system defaults to HUNGRY state (defensive fallback) | Automated: mock `consume_food()` to return null/error, assert state = HUNGRY |

### Days of Food Remaining (HUD)

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC-16 | GIVEN 30 food units and daily requirement of 2, WHEN computing `days_of_food_remaining`, THEN the result is 15 days | Automated: assert `floor(30/2) = 15` |
| AC-17 | GIVEN 3 food units and daily requirement of 2, WHEN computing `days_of_food_remaining`, THEN the result is 1 day (floor division) | Automated: assert `floor(3/2) = 1` |
| AC-18 | GIVEN 0 NPCs (daily requirement = 0), WHEN computing `days_of_food_remaining`, THEN the result is 9999 (displayed as "Unlimited") | Automated: assert guard returns max int value (e.g., 9999) when D = 0 |

## UI Requirements

| ID | Element | Description |
|----|---------|-------------|
| UI-1 | Food status indicator (HUD) | Small text near energy bar or in resource summary: "Food: 3 days remaining" or "⚠️ Low food" when ≤ 1 day |
| UI-2 | Debuff indicator (HUD) | When HUNGRY, shows "HUNGRY — actions slowed (2× tick cost)" with a brief description. Not at player eye level — secondary to energy bar. |
| UI-3 | Food breakdown (tooltip) | Hovering the food status shows: "N NPCs need N food units today. Total: X food units." (1 berry = 1 unit, 1 bread = 2 units) |
| UI-4 | Day transition food log (optional, MVP) | After day transition, brief HUD flash: "Day 2: consumed 2 food units (2 berries, 0 deficit)" |
