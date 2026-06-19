# Efficiency System

> **Status**: Implemented — synced against `src/systems/efficiency/efficiency_formulas.gd` (2026-06-18)
> **Author**: User + Claude
> **Last Updated**: 2026-06-18 (nutrition curve rescaled; building efficiency switched to additive base + tiles + worker; efficiency hover tooltips added)
> **Implements Pillar**: Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)
> **Sync note**: Promoted from `design/quick-specs/efficiency-system-2026-06-03.md`
> (now superseded) and reverse-synced to the implementation. Key changes vs. the quick
> spec: NPC base efficiency is **0.5** (not 1.0), the binary hunger modifier became a
> **nutrition curve**. Building efficiency is now **additive** (base 0.25 + 0.05/resource tile +
> worker efficiency), the 100% building cap was **removed** (now 2.0 = global max), and the old
> multiplicative adjacency curve (F6) was folded into the additive tile term. ADR: ADR-0012 (incl.
> Amendments 2026-06-13 & 2026-06-18).

## Overview

The Efficiency System is the unified layer for "how well is this building or NPC
performing right now?" Every NPC carries an `efficiency` float computed from its food,
satisfaction, and equipment modifiers (F1); a building's efficiency is the additive sum of a
flat base, its adjacent resource tiles, and its worker's efficiency (F2); buildings divide
their production cycle time by their efficiency (F3, recomputed live every tick);
travelling NPCs and carriers divide their travel time by their efficiency (F4). All
math lives in one static, stateless class (`EfficiencyFormulas`) so every consumer
applies identical rules and the UI has a single number to display per entity.

## Player Fantasy

Efficiency is the village's pulse, made visible. One number on every worker and every
building answers "why is this slow?" — and every lever the player pulls (feeding,
placement, roads later equipment) visibly moves it. There is no hidden modifier stack:
a 55% building is a 55% building because its worker ate one berry and the camp touches
one tree, and both facts are on screen. Optimization becomes reading numbers, forming
a hypothesis, and watching the number rise.

## Detailed Rules

**Rule 1 — Efficiency divides tick durations.** Higher efficiency = shorter cycles and
faster travel: `effective_ticks = max(1, floor(base_ticks / efficiency))`. Efficiency
≤ 0 returns an INT_MAX sentinel ("frozen") — unreachable in normal play because all
curves floor above 0.

**Rule 2 — NPC efficiency (F1).** `npc.efficiency = clamp(0.5 × food_mod ×
satisfaction_mod × equipment_mod, 0.0, 2.0)`. The base is **0.5**: a never-fed NPC
with neutral modifiers runs at half speed. Feeding (Hunger System) is what lifts an
NPC toward 1.0. Satisfaction and equipment modifiers are 1.0 placeholders for future
systems.

**Rule 3 — Food modifier comes from the nutrition curve (F5).** The Hunger System
emits `food_modifier = efficiency_from_nutrition(total_nutrition, level, perk_cap) / 0.5`,
where `efficiency_from_nutrition(n) = 0.25 + min(0.05 × n, nutrition_bonus_cap)`.
At level 1 with no perks the cap is `+0.25` → food tops out at **0.50 (50%)**, reached at
exactly **5 nutrition (5 berries)**. Anchors (lvl 1): unfed → 0.25, 1 nutrition → 0.30,
5 → 0.50, beyond 5 → 0.50 (over-feeding gives nothing).

**Rule 3b — Level and perks raise the reachable max (the cap must be FED to fill it).**
`nutrition_bonus_cap = 0.25 + 0.05 × (level − 1) + perk_cap_bonus`. Each level-up adds
`+0.05` to the max efficiency; Master's Touch (Perk #3) adds `+0.20` to the same cap.
Levelling alone does **not** raise current efficiency — the extra ceiling is only realized
by feeding more (still 5%/nutrition). Examples: lvl 10 fed-to-cap → 0.95 (needs 14
nutrition); lvl 10 + Master's Touch fed-to-cap → 1.15 (needs 18 nutrition = 18 berries).

**Rule 4 — Building efficiency (additive, 2026-06-18).** One formula for all buildings:
`clamp(BUILDING_BASE_EFFICIENCY + resource_tiles × ADJACENCY_EFFICIENCY_PER_TILE
+ worker.efficiency + upgrade_bonus, 0.0, BUILDING_EFFICIENCY_MAX)`.
- **Base:** every building has a flat `BUILDING_BASE_EFFICIENCY = 0.25` floor.
- **Resource tiles:** `+0.05` per adjacent resource terrain tile, **only** for buildings with an
  adjacency requirement (Lumber Camp, Stone Mason, Gathering Hut); all others count 0 tiles.
- **Worker:** the assigned worker's NPC efficiency is **added** on top (sum if several; 0 if
  unstaffed — production is still gated separately by `npc_required`). `upgrade_bonus` is 0.0 at
  VS scope.
- **Cap:** `BUILDING_EFFICIENCY_MAX = 2.0` (= global `EFFICIENCY_MAX`); no artificial 100% brake.
- Example: Lumber Camp, 3 tiles, worker at 0.50 → 0.25 + 0.15 + 0.50 = **0.90**. Tool Workshop,
  worker at 0.50 → 0.25 + 0 + 0.50 = **0.75**.

**Rule 5 — Resource-tile bonus.** Each adjacent required-terrain tile adds a flat `+0.05` to the
building (part of Rule 4's sum), counted only for adjacency buildings. Recomputed whenever adjacent
terrain
changes (`terrain_tile_changed`).

**Rule 6 — Wiring is live.**
- F3 is applied at production-cycle start AND re-derived from the current efficiency
  on every tick of a running cycle — feeding a worker mid-cycle speeds up the cycle
  immediately.
- F4 is applied once per travel-leg start (NPC assignment travel, carrier legs).
- Efficiency changes propagate: HungerSystem → NPCSystem (`food_modifier`,
  `recalculate_efficiency`) → every building with that worker
  (`_propagate_worker_efficiency_change`).

**Rule 7 — UI readability.** Efficiency is displayed as a percentage on NPC and
building panels. Color convention: ≥ 1.0 green, 0.5–1.0 yellow, < 0.5 red.

## Formulas

All formulas are static functions in `EfficiencyFormulas` (pure math, no state).

**F1 — NPC efficiency:**
`clamp(BASE_NPC_EFFICIENCY × food_mod × satisfaction_mod × equipment_mod, 0.0, 2.0)`,
`BASE_NPC_EFFICIENCY = 0.5`.
Example (lvl 1): fed 3 nutrition → food_mod = 0.40/0.5 = 0.8 → eff = 0.5 × 0.8 = 0.40.

**F2 — Building efficiency (additive):**
`clamp(0.25 + resource_tiles × 0.05 + worker_eff + upgrade_bonus, 0.0, BUILDING_EFFICIENCY_MAX)`.
Example: 2 tiles, 1 worker at 0.70 → 0.25 + 0.10 + 0.70 = 1.05. No-tile building, worker 0.70 → 0.95.

**F3 — Effective cycle ticks:**
`max(1, floor(base_cycle_ticks / building_efficiency))`; INT_MAX sentinel at ≤ 0.
Example: base 250, eff 0.70 → floor(250/0.70) = 357 ticks.

**F4 — Effective travel ticks:**
`max(1, floor(base_travel_ticks / npc_efficiency))`; INT_MAX sentinel at ≤ 0.
Example: base 50 (10 tiles × 5), eff 0.25 → 200 ticks.

**F5 — Nutrition → efficiency curve (level- and perk-scaled cap):**
`nutrition_bonus_cap(level, perk_cap) = 0.25 + 0.05 × (level − 1) + perk_cap`;
`efficiency_from_nutrition(n, level, perk_cap) = 0.25 + min(0.05 × max(0, n), nutrition_bonus_cap)`;
`calculate_food_modifier(n, level, perk_cap) = efficiency_from_nutrition(...) / 0.5`;
`nutrition_for_full(level, perk_cap) = nutrition_bonus_cap / 0.05` (the "x/y" UI target).
Example: lvl 10 + Master's Touch → cap 0.90 → max eff 1.15, `nutrition_for_full = 18`.

**F6 — (removed 2026-06-18).** The multiplicative adjacency curve was replaced by the additive
resource-tile term in F2 (`+0.05` per adjacent resource tile). There is no separate F6 anymore.

## Edge Cases

- **Efficiency 0:** F3/F4 return INT_MAX (entity frozen, no crash, no input loss).
  NPC efficiency cannot reach 0 through food alone (floor 0.25); a building could only reach
  0 if base+tiles+worker were all stripped, which the 0.25 base prevents.
- **No worker assigned:** the worker term is 0, so the building sits at base + resource tiles
  (e.g. 0.25, or 0.40 with 3 tiles). Production is still gated separately by `npc_required`, so
  this efficiency is informational until a worker is assigned.
- **Worker efficiency above 1.0** (levels / Master's Touch / future equipment): the surplus is
  added on top — base + tiles + 1.15 can exceed 1.0, driving the building faster than base.
  Bounded only at the global 2.0 ceiling.
- **Multiple workers:** F2 sums each worker's efficiency; current gameplay assigns at most one
  worker per building, so the sum has one term.
- **Mid-cycle efficiency drop:** the running cycle's duration grows on the next tick
  (live recalc) — progress ticks are kept, only the target moves.
- **Save/load:** efficiency is recomputed from serialized modifiers on load
  (`_deserialize_npc` calls `recalculate_efficiency`); building efficiency is
  serialized directly and re-propagated on the first change.

## Dependencies

| System | Direction | Interface |
|--------|-----------|-----------|
| **Hunger System** | feeds in | `calculate_food_modifier` / `efficiency_from_nutrition` (F5); emits `npc_food_efficiency_changed` |
| **NPC System** | owns NPC values | `NPCInstance.efficiency`, `recalculate_efficiency()` (F1), travel via F4, propagation to buildings |
| **Building System** | owns building values | `BuildingInstance.recalculate_efficiency()` (additive F2), cycle duration via F3 (live) |
| **Logistics System** | consumes | carrier travel legs via F4 (`_set_carrier_state`) |
| **Resource System** | indirect | nutrition values for F5 inputs |
| **UI (NPC/Building panels, overlays)** | reads | efficiency percentages, "Nutrition: x/y" via `nutrition_for_full(level, perk_cap)` |
| **Experience System** | feeds in | NPC `level` raises `nutrition_bonus_cap` by `+0.05`/level — levels are **no longer cosmetic**; they lift the reachable max efficiency (must be fed to realize). See `design/gdd/experience-system.md`. |
| **Perk System** | feeds in | Master's Touch (`EFFECT_NPC_EFF_CAP`, +0.20) adds to `nutrition_bonus_cap`, same channel as level. See `design/perks/perk-catalog.md`. |

## Tuning Knobs

All knobs are `const` in `EfficiencyFormulas` (config externalization to
`assets/data/efficiency-config.json` is planned — efficiency Story 005, tracked as
tech debt).

| Knob | Default | Safe Range | Effect |
|------|---------|------------|--------|
| `BASE_NPC_EFFICIENCY` | 0.5 | 0.3–1.0 | Speed of a neutral (never-fed) NPC. Raising it weakens the feeding incentive. |
| `EFFICIENCY_MAX` | 2.0 | 1.5–3.0 | NPC ceiling (future equipment headroom). |
| `BUILDING_EFFICIENCY_MAX` | 2.0 (= `EFFICIENCY_MAX`) | 1.0–2.0 | Building ceiling. As of 2026-06-18 set to the global max (no artificial 100% brake) so >100% workers speed buildings up. Lower to 1.0 to restore the brake. |
| `NUTRITION_UNFED_EFFICIENCY` | 0.25 | 0.1–0.5 | Starving floor (see Hunger System knobs). |
| `NUTRITION_PER_UNIT` | 0.05 | 0.02–0.15 | Curve slope (efficiency gained per nutrition point). |
| `NUTRITION_MAX_BONUS` | 0.25 | 0.15–0.75 | Level-1 food bonus cap → fed max efficiency 0.50. |
| `LEVEL_EFFICIENCY_PER_LEVEL` | 0.05 | 0.0–0.15 | Max-efficiency gained per NPC level (added to the food cap). |
| `BUILDING_BASE_EFFICIENCY` | 0.25 | 0.0–0.5 | Flat base every building has before tiles/worker (additive F2). |
| `ADJACENCY_EFFICIENCY_PER_TILE` | 0.05 | 0.0–0.25 | Additive bonus per adjacent resource tile (adjacency buildings only). |

## Acceptance Criteria

- [x] NPC exposes `efficiency: float`; default = `BASE_NPC_EFFICIENCY` (0.5)
- [x] F1: NPC efficiency = clamp(0.5 × food × satisfaction × equipment, 0, 2)
- [x] F5 (lvl 1): unfed → 0.25, 1 nutrition → 0.30, 5 → 0.50, >5 → 0.50 (capped)
- [x] F5 cap scales: lvl 10 → max 0.95 (14 nutrition); lvl 10 + Master's Touch → max 1.15 (18 nutrition)
- [x] F2 (additive): building = 0.25 base + tiles × 0.05 + worker_eff + upgrade_bonus, clamped [0, 2.0]
- [x] Resource tiles add +5% each, only for adjacency buildings (Lumber Camp / Stone Mason / Gathering Hut)
- [x] No-worker building sits at base + tiles (worker term 0); production still gated by `npc_required`
- [x] Building efficiency may exceed 1.0 when base+tiles+worker do (no artificial 100% brake)
- [x] NPC and building detail panels show a hover tooltip breaking the efficiency into its parts
- [x] F3 drives production cycle duration and is recomputed live during a running cycle
- [x] F4 drives NPC assignment travel and carrier travel legs
- [x] Efficiency ≤ 0 yields the INT_MAX frozen sentinel in F3/F4
- [ ] Curve constants externalized to config file (Story 005 — open)
- [ ] Unit tests updated to the amended formulas (post-balancing — open)
