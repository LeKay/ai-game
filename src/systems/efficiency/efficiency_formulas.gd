class_name EfficiencyFormulas
## Static helper class implementing all efficiency formulas (F1–F5).
## ADR: ADR-0012 (Efficiency System — Entity Property and Formula Architecture)
## All values are pure math — no state, no dependencies.

const EFFICIENCY_MIN: float = 0.0
const EFFICIENCY_MAX: float = 2.0
## Building efficiency cap. 2026-06-18: the artificial 100% brake was removed — buildings now
## follow their worker(s) and may exceed base speed (a >100% worker via levels/Master's Touch
## speeds production above base). Bounded only by the global EFFICIENCY_MAX (2.0), same ceiling
## as NPCs.
const BUILDING_EFFICIENCY_MAX: float = EFFICIENCY_MAX
## Base NPC efficiency with no food — tune here, overridden by config in Story 005.
const BASE_NPC_EFFICIENCY: float = 0.5

## --- Nutrition → efficiency curve (balancing 2026-06-18, v4: level-scaled cap) ---
## Efficiency depends on TOTAL nutrition consumed per day (amount × food nutrition), so foods
## are interchangeable by nutrition: 5 berries (5×1) == 1 bread (1×5).
## eff = 0.25 (floor) + min(0.05 × total_nutrition, bonus_cap).  The bonus cap is no longer
## fixed: it grows with NPC level and the Master's Touch perk (see nutrition_bonus_cap).
## At level 1 with no perks the cap is +0.25 → food tops out at 50% ("base max efficiency"),
## reached at exactly 5 nutrition (5 berries). Each level-up and Master's Touch raise the cap,
## but the extra ceiling must be FILLED with more nutrition (5%/nutrition) — feeding 5 berries
## still only yields 50%, levelling alone does not raise current efficiency.
## Anchors (lvl 1): 0 → 0.25 (starving), 1 → 0.30, 5 → 0.50 (full), >5 → 0.50 (capped).
const NUTRITION_UNFED_EFFICIENCY: float = 0.25  ## base efficiency at 0 nutrition (and floor)
const NUTRITION_PER_UNIT: float = 0.05          ## efficiency per nutrition point (5%/nutrition)
const NUTRITION_MAX_BONUS: float = 0.25         ## level-1 bonus cap → food eff caps at 0.50 (50%)
## Each level above 1 raises the reachable max efficiency by this much (must be fed to fill it).
## Lvl 1 max 0.50, lvl 10 max 0.95. Combines additively with the Master's Touch perk bonus.
const LEVEL_EFFICIENCY_PER_LEVEL: float = 0.05

## Building efficiency = additive model (2026-06-18, F2 v2):
##   building_eff = BUILDING_BASE_EFFICIENCY + resource_tiles × ADJACENCY_EFFICIENCY_PER_TILE
##                  + worker_efficiency (+ upgrade_bonus), clamped to [0, BUILDING_EFFICIENCY_MAX].
## Flat base every building has, then +5 % per adjacent resource tile (only for buildings with an
## adjacency requirement; 0 otherwise), then the assigned worker's NPC efficiency on top.
const BUILDING_BASE_EFFICIENCY: float = 0.25
const ADJACENCY_EFFICIENCY_PER_TILE: float = 0.05

## F1: NPC efficiency — BASE × modifiers, clamped to [0.0, 2.0].
## food_mod carries the (level- and perk-scaled) nutrition curve: 0.5 when unfed / 0 nutrition
## (25% eff), 1.0 when fed to the level-1 cap (50% eff); higher levels/perks push it further.
## satisfaction_mod, equipment_mod: 1.0 at VS scope (future systems set these).
static func calculate_npc_efficiency(
		food_mod: float,
		satisfaction_mod: float,
		equipment_mod: float,
) -> float:
	return clampf(BASE_NPC_EFFICIENCY * food_mod * satisfaction_mod * equipment_mod,
			EFFICIENCY_MIN, EFFICIENCY_MAX)

## F2: Building efficiency (additive) — flat base + per-resource-tile bonus + worker efficiency.
## resource_tiles: adjacent resource terrain tiles (0 for buildings without an adjacency requirement).
## worker_efficiency: the assigned worker's npc.efficiency (sum if several workers; 0.0 if unstaffed).
## upgrade_bonus: 0.0 at VS scope (future UpgradeSystem sets this).
## Example: 3 tiles, worker at 0.50 → 0.25 + 0.15 + 0.50 = 0.90. Clamped to [0, BUILDING_EFFICIENCY_MAX].
static func calculate_building_efficiency(
		resource_tiles: int,
		worker_efficiency: float,
		upgrade_bonus: float = 0.0,
) -> float:
	return clampf(
			BUILDING_BASE_EFFICIENCY
			+ float(maxi(0, resource_tiles)) * ADJACENCY_EFFICIENCY_PER_TILE
			+ worker_efficiency
			+ upgrade_bonus,
			EFFICIENCY_MIN, BUILDING_EFFICIENCY_MAX)

## F3: Effective production cycle ticks — floor(base / efficiency), minimum 1.
## Returns INT_MAX (2147483647) when efficiency <= 0 — building is frozen (STALLED sentinel).
static func calculate_effective_cycle_ticks(base_ticks: int, building_efficiency: float) -> int:
	if building_efficiency <= 0.0:
		return 2147483647
	return maxi(1, floori(float(base_ticks) / building_efficiency))

## F4: Effective travel ticks — floor(base / efficiency), minimum 1.
## Returns INT_MAX (2147483647) when efficiency <= 0 — NPC cannot travel (frozen sentinel).
static func calculate_effective_travel_ticks(base_ticks: int, npc_efficiency: float) -> int:
	if npc_efficiency <= 0.0:
		return 2147483647
	return maxi(1, floori(float(base_ticks) / npc_efficiency))

## Additive cap on the nutrition bonus: level-1 base + per-level growth + perk ceiling.
## level: NPC level (>=1). extra_cap_bonus: flat additive ceiling from perks, e.g. Master's Touch
## (EFFECT_NPC_EFF_CAP, +0.20). Lvl 1 no perk → 0.25; lvl 10 → 0.70; lvl 10 + Master's Touch → 0.90.
static func nutrition_bonus_cap(level: int = 1, extra_cap_bonus: float = 0.0) -> float:
	return NUTRITION_MAX_BONUS \
			+ LEVEL_EFFICIENCY_PER_LEVEL * float(maxi(level, 1) - 1) \
			+ maxf(0.0, extra_cap_bonus)

## F5 (nutrition-driven): food modifier such that F1 (BASE × mod) yields the nutrition curve.
## Pass the TOTAL nutrition consumed that day (amount × food nutrition), the NPC level, and any
## additive perk ceiling. total 0 → mod 0.5 (eff 0.25); at lvl 1 no perk, 5 → mod 1.0 (eff 0.50).
static func calculate_food_modifier(nutrition: float, level: int = 1, extra_cap_bonus: float = 0.0) -> float:
	return efficiency_from_nutrition(nutrition, level, extra_cap_bonus) / BASE_NPC_EFFICIENCY

## Generic TOTAL-nutrition → NPC efficiency curve (the single tunable food curve).
## eff = 0.25 + min(0.05 × total_nutrition, nutrition_bonus_cap(level, extra_cap_bonus)).
## Lvl 10 + Master's Touch: cap 0.90 → max eff 1.15 (115%), reached at 18 nutrition (18 berries).
static func efficiency_from_nutrition(nutrition: float, level: int = 1, extra_cap_bonus: float = 0.0) -> float:
	var bonus: float = minf(NUTRITION_PER_UNIT * maxf(0.0, nutrition),
			nutrition_bonus_cap(level, extra_cap_bonus))
	return NUTRITION_UNFED_EFFICIENCY + bonus

## Total nutrition required to reach full food efficiency (the "y" in the x/y UI display).
## Scales with level and perk ceiling: a higher reachable max needs proportionally more nutrition.
static func nutrition_for_full(level: int = 1, extra_cap_bonus: float = 0.0) -> float:
	return nutrition_bonus_cap(level, extra_cap_bonus) / NUTRITION_PER_UNIT
