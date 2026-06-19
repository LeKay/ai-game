class_name ExperienceFormulas
## Static helper class implementing the NPC Experience System curve (F1–F3).
## Design: design/gdd/experience-system.md
## All values are pure math — no state, no dependencies. These helpers drive XP accrual, level
## derivation, and UI display. Level is NOT cosmetic: it raises the NPC efficiency cap by
## +5%/level (EfficiencyFormulas.nutrition_bonus_cap), and each level-up grants a perk choice.

# ---- Tuning knobs (single source of truth — see GDD Tuning Knobs) -------------

## XP granted for one *reference-length* completed activity (F1). XP is time-based: an activity
## (production cycle or carrier delivery) earns XP in proportion to the ticks it nominally takes,
## so a building with a short cycle no longer out-levels a slow one for the same working time.
const XP_PER_REFERENCE_CYCLE: int = 10
## The nominal duration (ticks) that `XP_PER_REFERENCE_CYCLE` corresponds to (F1). This is the
## base producer's cycle length, so a base-producer cycle still earns exactly XP_PER_REFERENCE_CYCLE.
const REFERENCE_CYCLE_TICKS: int = 250
## XP cost of the first level-up (1→2); scales the whole curve (F2).
const BASE_XP: int = 100
## Curve steepness (F2). 1.0 = linear; higher = late levels cost disproportionately more.
const LEVEL_EXPONENT: float = 1.5
## Level thresholds are rounded to this step for clean display (F2).
const XP_ROUNDING: int = 10
## Hard level cap. XP keeps accruing past it, but level does not increase.
const MAX_LEVEL: int = 10

## Role multiplier applied to a production worker's per-cycle XP (F1). < 1.0 makes building
## workers level slower than the shared base rate. Tunes role pacing relative to carriers.
const PRODUCTION_XP_MULTIPLIER: float = 0.75
## Role multiplier applied to a carrier's per-delivery XP (F1). > 1.0 makes carriers level faster
## than the shared base rate. Counterpart to PRODUCTION_XP_MULTIPLIER.
const CARRIER_XP_MULTIPLIER: float = 1.25

# ---- F1: Time-based XP grant --------------------------------------------------

## XP earned for a completed activity that nominally took `duration_ticks` ticks (F1).
## Linear in duration and rounded to the nearest integer: a REFERENCE_CYCLE_TICKS-long activity
## earns exactly XP_PER_REFERENCE_CYCLE × `role_multiplier`. `duration_ticks` is the *nominal*
## (efficiency-independent) length, so hunger/efficiency change how many activities finish per day,
## not the XP per activity. `role_multiplier` biases XP per role (production vs. carrier); prefer the
## `xp_for_production`/`xp_for_carrier` wrappers at call sites. Non-positive durations grant nothing.
static func xp_for_duration(duration_ticks: int, role_multiplier: float = 1.0) -> int:
	if duration_ticks <= 0:
		return 0
	var base: float = float(XP_PER_REFERENCE_CYCLE) * float(duration_ticks) / float(REFERENCE_CYCLE_TICKS)
	return int(round(base * role_multiplier))

## XP for a completed production cycle of nominal length `duration_ticks` (applies
## PRODUCTION_XP_MULTIPLIER). Call site: NPC System on `production_output_ready`.
static func xp_for_production(duration_ticks: int) -> int:
	return xp_for_duration(duration_ticks, PRODUCTION_XP_MULTIPLIER)

## XP for a completed carrier delivery of nominal length `duration_ticks` (applies
## CARRIER_XP_MULTIPLIER). Call site: Logistics System on cargo unload.
static func xp_for_carrier(duration_ticks: int) -> int:
	return xp_for_duration(duration_ticks, CARRIER_XP_MULTIPLIER)

# ---- F2: Level curve ----------------------------------------------------------

## XP required to advance from `level` to `level + 1`, rounded to XP_ROUNDING.
## Returns 0 at or beyond MAX_LEVEL (no further level to reach).
static func xp_to_advance(level: int) -> int:
	if level < 1:
		level = 1
	if level >= MAX_LEVEL:
		return 0
	var raw: float = float(BASE_XP) * pow(float(level), LEVEL_EXPONENT)
	return int(round(raw / float(XP_ROUNDING))) * XP_ROUNDING

## Cumulative XP required to *reach* `level` (the threshold at which the NPC is that level).
## cumulative_xp(1) == 0. Clamped to [1, MAX_LEVEL].
static func cumulative_xp(level: int) -> int:
	var total: int = 0
	for k in range(1, clampi(level, 1, MAX_LEVEL)):
		total += xp_to_advance(k)
	return total

## Level for a given total lifetime XP, clamped to [1, MAX_LEVEL] (inclusive thresholds).
static func level_for_total_xp(total_xp: int) -> int:
	var level: int = 1
	for l in range(2, MAX_LEVEL + 1):
		if total_xp >= cumulative_xp(l):
			level = l
		else:
			break
	return level

# ---- F3: Progress within a level (UI) -----------------------------------------

## XP accrued since reaching the current level. Always >= 0.
static func xp_into_level(total_xp: int, level: int) -> int:
	return maxi(0, total_xp - cumulative_xp(level))

## XP needed to clear the current level. 0 at MAX_LEVEL (UI shows a "MAX" state).
static func xp_span_of_level(level: int) -> int:
	return xp_to_advance(level)

## Fraction [0.0–1.0] for the XP bar fill. Returns 1.0 at MAX_LEVEL (full bar, no ratio).
static func progress_in_level(total_xp: int, level: int) -> float:
	var span: int = xp_span_of_level(level)
	if span <= 0:
		return 1.0
	return clampf(float(xp_into_level(total_xp, level)) / float(span), 0.0, 1.0)
