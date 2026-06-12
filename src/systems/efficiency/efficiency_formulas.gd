class_name EfficiencyFormulas
## Static helper class implementing all efficiency formulas (F1–F5).
## ADR: ADR-0012 (Efficiency System — Entity Property and Formula Architecture)
## All values are pure math — no state, no dependencies.

const EFFICIENCY_MIN: float = 0.0
const EFFICIENCY_MAX: float = 2.0
## Building efficiency cap (2026-06-12). Buildings top out at 100% = base speed: below 100%
## slows production (hungry worker / poor placement), never faster than base. Tunable knob —
## raise this later if buildings should be able to exceed base speed.
const BUILDING_EFFICIENCY_MAX: float = 1.0
## Base NPC efficiency with no food — tune here, overridden by config in Story 005.
const BASE_NPC_EFFICIENCY: float = 0.5
## Efficiency gained per consumed food unit (F5). 1 unit → +50% efficiency.
const FOOD_EFFICIENCY_PER_UNIT: float = 1.0

## --- Nutrition → efficiency curve (balancing 2026-06-12, v3) ---
## Efficiency depends on TOTAL nutrition consumed per day (amount × food nutrition), so foods
## are interchangeable by nutrition: 5 berries (5×1) == 1 bread (1×5) == 100%.
## eff = 0.25 (base) + min(0.15 × total_nutrition, 0.75 cap).  Food alone tops out at 100%
## (25% base + 75% from nutrition); over-feeding past 5 nutrition gives NOTHING extra.
## Anchors: 0 → 0.25 (starving), 1 → 0.40, 5 → 1.0 (full), >5 → 1.0 (capped).
## Bread is denser (1 item = 5 nutrition) → reaches 100% with 1/5 the items/logistics of berries.
const NUTRITION_UNFED_EFFICIENCY: float = 0.25  ## base efficiency at 0 nutrition (and floor)
const NUTRITION_PER_UNIT: float = 0.15          ## efficiency per nutrition point
const NUTRITION_MAX_BONUS: float = 0.75         ## nutrition adds at most +0.75 → food eff caps at 1.0

## F6 adjacency: eff = clamp(BASE + PER_TILE × tiles, FLOOR, CEIL).
## 2026-06-12: softened resource-tile impact to +10%/tile (was +25%) with a higher base, so the
## penalty for few tiles is small. 1 tile → 0.80, 2 → 0.90, 3+ → 1.00 (capped). All tunable knobs.
const ADJACENCY_EFFICIENCY_PER_TILE: float = 0.10
const ADJACENCY_BASE: float = 0.7
const ADJACENCY_FLOOR: float = 0.5
const ADJACENCY_CEIL: float = 1.0

## F1: NPC efficiency — BASE × modifiers, clamped to [0.0, 2.0].
## food_mod: 1.0 when unfed (50% efficiency), 2.0 when 1 food consumed (100%), etc.
## satisfaction_mod, equipment_mod: 1.0 at VS scope (future systems set these).
static func calculate_npc_efficiency(
		food_mod: float,
		satisfaction_mod: float,
		equipment_mod: float,
) -> float:
	return clampf(BASE_NPC_EFFICIENCY * food_mod * satisfaction_mod * equipment_mod,
			EFFICIENCY_MIN, EFFICIENCY_MAX)

## F2: Building efficiency — 1.0 base + sum of worker deltas + upgrade bonus, clamped.
## worker_efficiencies: array of each assigned worker's npc.efficiency value.
## upgrade_bonus: 0.0 at VS scope (future UpgradeSystem sets this).
static func calculate_building_efficiency(
		worker_efficiencies: Array[float],
		upgrade_bonus: float,
) -> float:
	var delta: float = 0.0
	for eff: float in worker_efficiencies:
		delta += (eff - 1.0)
	return clampf(1.0 + delta + upgrade_bonus, EFFICIENCY_MIN, BUILDING_EFFICIENCY_MAX)

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

## F5 (nutrition-driven): food modifier such that F1 (BASE × mod) yields the nutrition curve.
## Pass the TOTAL nutrition consumed that day (amount × food nutrition).
## total 0 → mod 0.5 (eff 0.25), 5 → mod 2.0 (eff 1.0), >5 → mod 2.0 (eff 1.0, capped).
static func calculate_food_modifier(nutrition: float) -> float:
	return efficiency_from_nutrition(nutrition) / BASE_NPC_EFFICIENCY

## Generic TOTAL-nutrition → NPC efficiency curve (the single tunable food curve).
## eff = 0.25 + min(0.15 × total_nutrition, 0.75).  5 nutrition → 100%, capped there.
static func efficiency_from_nutrition(nutrition: float) -> float:
	var bonus: float = minf(NUTRITION_PER_UNIT * maxf(0.0, nutrition), NUTRITION_MAX_BONUS)
	return NUTRITION_UNFED_EFFICIENCY + bonus

## Total nutrition required to reach full food efficiency (the "y" in the x/y UI display).
static func nutrition_for_full() -> float:
	return NUTRITION_MAX_BONUS / NUTRITION_PER_UNIT

## F6: Adjacency-based efficiency — clamp(BASE + tile_count × PER_TILE, FLOOR, CEIL).
## Used for buildings that require adjacent resource terrain tiles (e.g. Lumber Camp).
## 1 tile → 0.80, 2 → 0.90, 3+ → 1.00 (capped). Floor: never freezes purely from geometry.
static func calculate_adjacency_efficiency(tile_count: int) -> float:
	return clampf(ADJACENCY_BASE + float(tile_count) * ADJACENCY_EFFICIENCY_PER_TILE,
			ADJACENCY_FLOOR, ADJACENCY_CEIL)
