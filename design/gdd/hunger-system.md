# Hunger System

> **Status**: Implemented — synced against `src/gameplay/hunger_system.gd` (2026-06-13)
> **Author**: User + Claude
> **Last Updated**: 2026-06-13
> **Implements Pillar**: Pillar 1 (Earned Automation), Pillar 2 (Information Transparency)
> **Sync note**: Reverse-synced to the implementation. The original village-wide
> FED/HUNGRY debuff design was replaced during implementation by a **per-NPC food
> assignment + nutrition curve** model (ADR-0010, balancing pass 2026-06-11/12,
> `tools/balance/balance-findings.md`). Player-side hunger debuffs no longer exist —
> the player has only the Energy system.

## Overview

The Hunger System is the village's daily feeding ledger — but the unit of decision is
the individual NPC, not the village. The player assigns each NPC a food type and a
daily amount via the NPC detail panel. At every day transition (1440 ticks) the system
tries to consume each NPC's ration from storage and converts the **total nutrition**
consumed (amount × the food's nutrition value) into that NPC's efficiency for the next
day. A starving NPC still works — at 25% efficiency. A fully fed NPC (5 nutrition/day)
works at 100%. There is no death and no village-wide debuff: hunger is a per-worker
throughput dial, and feeding is the cheapest upgrade in the game. Food production
matters because every berry your gatherers pick literally makes your other workers
faster.

## Player Fantasy

You earned automation through consequence, not explanation.

Yesterday you only had to feed yourself. Today an NPC appeared in the new house and
you opened their panel, assigned them berries, and watched the "Nutrition: 1/5" label.
The next morning the lumber camp ran a little faster. Nobody told you "food =
efficiency" — you saw the cycle bar fill quicker and made the connection yourself.
That's earned understanding (Pillar 1), and it sticks.

The deeper game arrives with bread: one loaf carries the nutrition of five berries.
Suddenly the question isn't "do I have food?" but "which food, hauled by whom, to
which worker?" Five berries fed to a carrier mean five items dragged across the map;
one bread does the same job in one delivery. Hunger turns the food chain into a
logistics optimization — exactly the meditative bottleneck-hunting the game is about.

Reference: Factorio's first coal shortage, Anno's quiet panic when the food balance
dips. The same feeling, but resolved per worker: you can always see exactly *who* is
slow and *why*.

## Detailed Rules

**Rule 1: Per-NPC Food Assignment**
The player assigns a food resource and a daily amount to each NPC via the NPC detail
panel (`assign_food(npc_id, resource_id)`, `set_food_amount(npc_id, amount)`).

- Default amount on first assignment: 1. Minimum: 1 (enforced by `set_food_amount`).
- An NPC without an assignment is simply unfed (no error, no warning dialog).
- Assignments persist in save files (`serialize`/`deserialize`).

**Rule 2: Daily Consumption**
On each `TickSystem.day_transition` (every 1440 ticks), `apply_daily_consumption()`
runs once for every registered NPC:

1. No assignment → NPC is unfed (nutrition 0).
2. Assignment exists → the system finds a storage container holding the food and
   consumes `amount` units.
3. Consumption succeeds → total nutrition = `amount × nutrition(resource)` is fed into
   the efficiency curve (Formula 1).
4. Consumption fails (not enough food) → NPC is unfed (nutrition 0). No partial
   crediting.

After all NPCs are processed, `food_consumed_daily(items)` is emitted with the actual
consumed quantities — consumed food appears as its own line in the Day Ledger, separate
from general inventory deltas.

**Rule 3: Nutrition Values (data-driven)**
Each resource carries a `nutrition` field in `data/resources.json` (0 = inedible):

| Resource | Nutrition per item | Items needed for 100% |
|----------|--------------------|------------------------|
| Berry | 1 | 5 |
| Bread | 5 | 1 |

Foods are interchangeable by nutrition: 5 berries ≡ 1 bread ≡ 100% efficiency. Bread's
value is logistical — one-fifth of the items to haul and store.

**Rule 4: Effect — NPC Efficiency, Nothing Else**
Hunger affects exactly one thing: the NPC's `food_modifier`, and through it the NPC's
efficiency (Efficiency System F1/F5, ADR-0012). NPC efficiency in turn scales:

- production cycle time of the building the NPC works at (F3, live recalculation),
- the NPC's own travel time (F4) — as worker and as logistics carrier.

There is **no** player debuff, **no** output-quantity penalty, and **no** village-wide
state. The player's slowdown mechanics live entirely in the Player Character System's
Energy model (ADR-0007).

**Rule 5: No Death — Floor at 25% (Design Decision)**
NPCs never die or stop from starvation. The nutrition curve floors at 0.25 efficiency:
a starving worker runs buildings at quarter speed (cycle ×4) and walks at quarter
speed, but never freezes. The pressure is "can I automate food fast enough?", not
"can I avoid losing my workforce?" — correctable, meditative, never irreversible.

**Rule 6: Over-Feeding Gives Nothing**
The nutrition bonus caps at +0.75 (reached at 5 nutrition/day). Assigning 10 berries
wastes 5 — the panel shows "Nutrition: x/5" so the player can see the cap (Pillar 2).
Food alone can never push an NPC past 100%; headroom up to the F1 clamp of 2.0 is
reserved for future satisfaction/equipment modifiers.

## Formulas

### Formula 1: Nutrition → NPC Efficiency Curve

`efficiency = NUTRITION_UNFED_EFFICIENCY + min(NUTRITION_PER_UNIT × total_nutrition, NUTRITION_MAX_BONUS)`

i.e. `eff = 0.25 + min(0.15 × total_nutrition, 0.75)`

**Variables** (constants in `EfficiencyFormulas`):
| Variable | Symbol | Type | Default | Description |
|----------|--------|------|---------|-------------|
| Total nutrition consumed today | `total_nutrition` | float | 0–∞ | `amount × nutrition(resource)` from the successful daily consumption; 0 if unfed |
| Base/floor efficiency | `NUTRITION_UNFED_EFFICIENCY` | float | 0.25 | Efficiency at 0 nutrition — the starving floor |
| Efficiency per nutrition point | `NUTRITION_PER_UNIT` | float | 0.15 | Slope of the curve |
| Maximum food bonus | `NUTRITION_MAX_BONUS` | float | 0.75 | Cap — food alone tops out at 1.0 total |

**Anchors:** 0 → 0.25 (starving) · 1 → 0.40 (one berry) · 3 → 0.70 · 5 → 1.00 (full) ·
\>5 → 1.00 (capped, over-feeding wasted).

**Output Range:** [0.25, 1.0].

**Plumbing:** The Hunger System emits `npc_food_efficiency_changed(npc_id,
food_modifier)` where `food_modifier = efficiency / BASE_NPC_EFFICIENCY` (= eff / 0.5),
so that Efficiency Formula F1 (`0.5 × food_mod × satisfaction_mod × equipment_mod`)
reproduces the curve. NPCSystem applies the modifier, recalculates NPC efficiency, and
propagates it to the assigned building (`_propagate_worker_efficiency_change`).

**Example (2 berries assigned):**
```
total_nutrition = 2 × 1 = 2.0
eff = 0.25 + min(0.15 × 2, 0.75) = 0.55
food_modifier = 0.55 / 0.5 = 1.10
```

**Example (1 bread assigned):**
```
total_nutrition = 1 × 5 = 5.0
eff = 0.25 + 0.75 = 1.00  → building runs at base speed
```

### Formula 2: Required Nutrition for Full Efficiency

`nutrition_for_full = NUTRITION_MAX_BONUS / NUTRITION_PER_UNIT = 0.75 / 0.15 = 5`

Used by the NPC detail panel for the "Nutrition: x/5" display. Changing either curve
constant automatically moves the UI target value.

### Formula 3: Daily Food Demand (planning aid)

`daily_demand(resource) = Σ over NPCs assigned that resource of amount_npc`

There is no system-level aggregate consumption formula — demand is simply the sum of
the per-NPC assignments. The Day Ledger reports actual consumption after the fact via
`food_consumed_daily`.

## Edge Cases

- **No assignment:** NPC is unfed → nutrition 0 → efficiency 0.25. Silent; visible in
  the NPC panel and through the slow building.
- **Insufficient food at day transition:** Consumption is all-or-nothing per NPC. If
  the ration cannot be consumed in full, the NPC gets nothing that day (no partial
  nutrition credit) and the food stays in storage.
- **Food spread across containers:** Consumption draws on total storage across
  containers (deterministic container order). An NPC's ration may be sourced from
  multiple containers in one transition.
- **Multiple NPCs share a scarce food:** NPCs are processed in registry order; earlier
  NPCs eat first. Later NPCs whose ration can no longer be filled go unfed. The order
  is deterministic across save/load.
- **NPC spawned mid-day:** Not fed until the next day transition. A freshly assigned
  worker/carrier therefore runs at 0.5 NPC efficiency (modifier 1.0 default) until the
  first feeding — buildings start at half speed on day one (known feel issue, see
  balance findings: consider auto-feed UX later).
- **Food assigned but resource removed from the registry:** `nutrition` lookup returns
  0 → consuming it yields 0 nutrition (eff 0.25). Data error, not a crash.
- **Day transition with 0 NPCs:** `food_consumed_daily({})` is emitted, nothing else
  happens.
- **Dependencies unavailable (tests/startup):** `apply_daily_consumption` warns and
  skips — never crashes, never consumes.

## Dependencies

| System | Direction | Nature | Interface |
|--------|-----------|--------|-----------|
| **Tick System** | Hunger subscribes | **Hard** — triggers daily consumption | `day_transition` signal (1440 ticks/day) |
| **Inventory System** | Hunger consumes | **Hard** — ration deduction | `find_container_with()`, `try_consume()` |
| **NPC System** | Bidirectional | **Hard** — NPC list in, efficiency out | `all_npcs` / `get_npc_count()` in; `npc_food_efficiency_changed` → `_on_npc_food_efficiency_changed` out |
| **Resource System** | Hunger reads | **Hard** — nutrition values | `ResourceRegistry.get_definition(id).nutrition` |
| **Efficiency System** | Hunger uses | **Hard** — curve + modifier math | `EfficiencyFormulas.calculate_food_modifier()`, `efficiency_from_nutrition()` |
| **Building System** | Indirect | Worker efficiency reaches production via NPCSystem propagation | `BuildingInstance.recalculate_efficiency()` |
| **Day Ledger / Day Overview UI** | Hunger writes | **Soft** — daily consumption report | `food_consumed_daily(items)` signal |
| **NPC Detail Panel (UI)** | UI writes/reads | **Soft** — assignment controls + "Nutrition: x/5" display | `assign_food()`, `set_food_amount()`, `get_assigned_food()`, `get_food_amount()` |
| **Save/Load System** | Bidirectional | **Hard** — assignments persist | `serialize()` / `deserialize()` |

## Tuning Knobs

| Knob | Symbol | Default | Safe Range | Effect | Formula Ref |
|------|--------|---------|------------|--------|-------------|
| **Starving floor** | `NUTRITION_UNFED_EFFICIENCY` | 0.25 | 0.1–0.5 | Efficiency of an unfed NPC. Lower = harsher starvation (cycles up to ×10); higher = food matters less. Never set to 0 — that would freeze buildings. | Formula 1 |
| **Curve slope** | `NUTRITION_PER_UNIT` | 0.15 | 0.05–0.3 | Efficiency per nutrition point. Together with the cap this sets the "full" target (0.75/0.15 = 5). | Formulas 1–2 |
| **Food bonus cap** | `NUTRITION_MAX_BONUS` | 0.75 | 0.5–1.5 | Maximum efficiency from food alone (floor + cap = food ceiling). At 0.75 food tops out at exactly 100%; raising it lets food push NPCs past base speed. | Formulas 1–2 |
| **Berry nutrition** | `resources.json: berry.nutrition` | 1 | 0.5–2 | Items-to-nutrition ratio of the basic food. | Rule 3 |
| **Bread nutrition** | `resources.json: bread.nutrition` | 5 | 2–8 | Density of the processed food. At 5 = exactly one bread per NPC per day for 100% — the logistics reward for the bread chain. | Rule 3 |

**Knob interdependence:** `floor + cap` should equal 1.0 if food alone is meant to top
out at base speed (current design). `cap / slope` is the daily nutrition target shown
in the UI — keep it a round number. Bread nutrition ÷ berry nutrition is the logistics
compression factor of the bread chain (currently 5×).

## Visual/Audio Requirements

The Hunger System is an infrastructure system — its effects are communicated through
other systems:

| Surface | How hunger is communicated |
|---------|---------------------------|
| **NPC Detail Panel** | Food assignment dropdown + amount spinner; "Nutrition: x/5" readout |
| **NPC Overlay / Detail** | NPC efficiency percentage |
| **Building Detail Panel** | Building efficiency % and visibly slower cycle bar when the worker is hungry |
| **Day Overview (Day Ledger)** | "Food consumed" line per day from `food_consumed_daily` |

No dedicated hunger VFX/audio.

## Acceptance Criteria

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC-1 | GIVEN an NPC with no food assignment, WHEN the day transition fires, THEN `npc_food_efficiency_changed` is emitted with the modifier for nutrition 0 (efficiency 0.25) | Automated |
| AC-2 | GIVEN an NPC assigned 2 berries and ≥2 berries in storage, WHEN the day fires, THEN 2 berries are consumed and the modifier corresponds to nutrition 2.0 (efficiency 0.55) | Automated |
| AC-3 | GIVEN an NPC assigned 1 bread and ≥1 bread in storage, WHEN the day fires, THEN the modifier corresponds to nutrition 5.0 (efficiency 1.0) | Automated |
| AC-4 | GIVEN an NPC assigned 3 berries but only 2 in storage (total, across all containers), WHEN the day fires, THEN nothing is consumed for that NPC and the unfed modifier is emitted | Automated |
| AC-5 | GIVEN an NPC assigned 10 berries with 10 in storage, WHEN the day fires, THEN all 10 are consumed but efficiency caps at 1.0 (over-feeding gives nothing) | Automated |
| AC-6 | GIVEN a fed worker NPC assigned to a Lumber Camp, WHEN its efficiency changes at day transition, THEN the building's efficiency and current cycle duration update (F3 live) | Automated/Integration |
| AC-7 | GIVEN food split across two containers (1 berry + 4 berries) and a ration of 5, WHEN the day fires, THEN the full ration is consumed across both containers | Automated |
| AC-8 | GIVEN daily consumption ran, WHEN `food_consumed_daily` is emitted, THEN it contains exactly the consumed quantities per resource (assignments that failed are absent) | Automated |
| AC-9 | GIVEN food assignments exist, WHEN the game is saved and reloaded, THEN assignments (resource + amount) are restored | Automated |
| AC-10 | GIVEN 0 NPCs, WHEN the day fires, THEN `food_consumed_daily({})` is emitted and no storage is touched | Automated |
