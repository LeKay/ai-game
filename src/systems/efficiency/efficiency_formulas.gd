class_name EfficiencyFormulas
## Static helper class implementing all efficiency formulas (F1–F5).
## ADR: ADR-0012 (Efficiency System — Entity Property and Formula Architecture)
## All values are pure math — no state, no dependencies.

const EFFICIENCY_MIN: float = 0.0
const EFFICIENCY_MAX: float = 2.0
## Base NPC efficiency with no food — tune here, overridden by config in Story 005.
const BASE_NPC_EFFICIENCY: float = 0.5
## Efficiency gained per consumed food unit (F5). 1 unit → +50% efficiency.
const FOOD_EFFICIENCY_PER_UNIT: float = 1.0
## F6: efficiency gained per adjacent required resource tile. 1 tile → 25%.
const ADJACENCY_EFFICIENCY_PER_TILE: float = 0.25

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
	return clampf(1.0 + delta + upgrade_bonus, EFFICIENCY_MIN, EFFICIENCY_MAX)

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

## F5: Food modifier from daily consumption — 1.0 + units_consumed × FOOD_EFFICIENCY_PER_UNIT.
## 0 units → 1.0 (NPC unfed, stays at BASE 50%), 1 unit → 2.0 (100%), 2 units → 3.0 (150%).
static func calculate_food_modifier(units_consumed: int) -> float:
	return 1.0 + float(units_consumed) * FOOD_EFFICIENCY_PER_UNIT

## F6: Adjacency-based efficiency — tile_count × ADJACENCY_EFFICIENCY_PER_TILE, clamped.
## Used for buildings that require adjacent resource terrain tiles to operate (e.g. Lumber Camp).
## Base is 0.0: no qualifying tiles → building is effectively stalled.
static func calculate_adjacency_efficiency(tile_count: int) -> float:
	return clampf(float(tile_count) * ADJACENCY_EFFICIENCY_PER_TILE, EFFICIENCY_MIN, EFFICIENCY_MAX)
