# Story 005: Efficiency Config and UI Thresholds

> **Epic**: Efficiency System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Config/Data
> **Manifest Version**: 2026-05-14

## Context

**Quick Spec**: `design/quick-specs/efficiency-system-2026-06-03.md`
**Requirement**: `TR-efficiency-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0012: Efficiency System — Entity Property and Formula Architecture
**ADR Decision Summary**: All tuning values (modifier defaults, clamp bounds, UI thresholds) live in `assets/data/efficiency-config.json`. `EfficiencyFormulas` exposes constants that default to the JSON values. UI threshold constants (`THRESHOLD_GREEN`, `THRESHOLD_YELLOW`) are accessible to any UI component (route_lines.gd, building status HUD). No magic numbers in source code.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: JSON loading via `FileAccess.open()` — stable API. Schema validation with fail-fast per Foundation pattern (ADR-0002).

**Control Manifest Rules (Feature Layer)**:
- Required: Fail-fast JSON schema validation — reject invalid data with clear error, do not silently skip
- Required: All values loaded at startup before any system reads them
- Forbidden: No magic numbers for efficiency thresholds in UI code — use constants from EfficiencyFormulas

---

## Acceptance Criteria

*From Quick Spec `design/quick-specs/efficiency-system-2026-06-03.md`, scoped to this story:*

- [ ] `assets/data/efficiency-config.json` exists with all 8 tuning knobs from the quick spec
- [ ] `EfficiencyFormulas` loads (or embeds as fallback-defaults) values from the config file at startup
- [ ] No magic numbers for efficiency in source code — all tuning values trace back to the config file or named constants
- [ ] UI threshold constants exposed: `EfficiencyFormulas.THRESHOLD_GREEN = 1.0`, `EfficiencyFormulas.THRESHOLD_YELLOW = 0.5`
- [ ] `route_lines.gd` (or equivalent route visualization) uses `EfficiencyFormulas.THRESHOLD_GREEN` and `THRESHOLD_YELLOW` for color decisions (replaces any hardcoded 1.0/0.5 values)
- [ ] Schema validation: if `efficiency-config.json` is malformed, loading fails with a clear error message (not silently using wrong values)
- [ ] Smoke check: game starts, efficiency-config.json loads without errors, NPCs and buildings show correct base efficiency of 1.0

---

## Implementation Notes

*Derived from ADR-0012 Implementation Guidelines:*

**efficiency-config.json** (`assets/data/efficiency-config.json`):
```json
{
    "schema_version": 1,
    "base_efficiency": 1.0,
    "efficiency_min": 0.0,
    "efficiency_max": 2.0,
    "hunger_modifier_fed": 1.0,
    "hunger_modifier_hungry": 0.5,
    "satisfaction_modifier_min": 0.8,
    "satisfaction_modifier_max": 1.2,
    "upgrade_bonus_per_tier": 0.25,
    "ui_threshold_green": 1.0,
    "ui_threshold_yellow": 0.5
}
```

**EfficiencyFormulas constants** (update `efficiency_formulas.gd` from Stories 001–004):
```gdscript
# UI thresholds — read from config, exposed as class constants for UI components
static var THRESHOLD_GREEN: float = 1.0   # efficiency >= this → green
static var THRESHOLD_YELLOW: float = 0.5  # efficiency >= this → yellow; < this → red

# Modifier defaults — loaded from config
static var HUNGER_MODIFIER_FED: float = 1.0
static var HUNGER_MODIFIER_HUNGRY: float = 0.5
static var EFFICIENCY_MIN: float = 0.0
static var EFFICIENCY_MAX: float = 2.0

static func load_config() -> void:
    var path := "res://assets/data/efficiency-config.json"
    if not FileAccess.file_exists(path):
        push_warning("efficiency-config.json not found — using defaults")
        return
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open efficiency-config.json")
        return
    var json := JSON.new()
    var err := json.parse(file.get_as_text())
    if err != OK:
        push_error("efficiency-config.json parse error: " + json.get_error_message())
        return
    var data: Dictionary = json.get_data()
    if not data.has("schema_version"):
        push_error("efficiency-config.json missing schema_version — rejecting")
        return
    THRESHOLD_GREEN = data.get("ui_threshold_green", THRESHOLD_GREEN)
    THRESHOLD_YELLOW = data.get("ui_threshold_yellow", THRESHOLD_YELLOW)
    HUNGER_MODIFIER_FED = data.get("hunger_modifier_fed", HUNGER_MODIFIER_FED)
    HUNGER_MODIFIER_HUNGRY = data.get("hunger_modifier_hungry", HUNGER_MODIFIER_HUNGRY)
    EFFICIENCY_MIN = data.get("efficiency_min", EFFICIENCY_MIN)
    EFFICIENCY_MAX = data.get("efficiency_max", EFFICIENCY_MAX)
```

**Call `load_config()` at startup** — from NPCSystem._enter_tree() or a dedicated init call before any formula is used:
```gdscript
func _enter_tree() -> void:
    EfficiencyFormulas.load_config()
    # ... rest of init ...
```

**route_lines.gd update** — replace hardcoded thresholds with named constants:
```gdscript
# BEFORE (hardcoded in route_lines.gd):
if efficiency >= 1.0:
    color = Color.GREEN
elif efficiency >= 0.5:
    color = Color.YELLOW
else:
    color = Color.RED

# AFTER (named constants):
if efficiency >= EfficiencyFormulas.THRESHOLD_GREEN:
    color = Color.GREEN
elif efficiency >= EfficiencyFormulas.THRESHOLD_YELLOW:
    color = Color.YELLOW
else:
    color = Color.RED
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Stories 001–004]: Formula implementations — this story only concerns config loading and constant exposure
- Future: Satisfaction and equipment modifier values — those systems will add their own config keys

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**Manual check: Config file loads correctly**
  - Setup: Launch game from Godot editor or headless mode
  - Verify: No errors in output console referencing efficiency-config.json
  - Pass condition: Game starts cleanly; no push_error or push_warning about efficiency config

**Manual check: Base efficiency = 1.0 at game start**
  - Setup: Start a new game, no hunger (fed), no equipment
  - Verify: Any NPC inspected shows efficiency = 1.0; any building with an assigned worker shows building.efficiency = 1.0
  - Pass condition: efficiency = 1.0 across all entities at game start

**Manual check: UI thresholds match config**
  - Setup: Load game with an existing save where some routes exist; or manually set carrier.efficiency = 0.3
  - Verify: Route line color matches expected threshold (efficiency < 0.5 → red)
  - Pass condition: Route visualization colors match `ui_threshold_green` and `ui_threshold_yellow` values in config

**Manual check: Malformed config is rejected**
  - Setup: Temporarily edit efficiency-config.json to remove schema_version field
  - Verify: Error message appears in output: "efficiency-config.json missing schema_version — rejecting"
  - Pass condition: Game loads with defaults (not corrupted values), error is logged
  - Restore: Revert efficiency-config.json after test

**Manual check: smoke pass after Stories 001–004**
  - Setup: Run full game with all efficiency stories implemented
  - Verify: Hungry village → production building slows to 2× (same as pre-efficiency behavior)
  - Verify: Carrier travel time matches F4 calculation for given distance
  - Pass condition: No regressions from Stories 001–004

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: Smoke check pass — `production/qa/smoke-efficiency-2026-06-03.md` (create after manual checks above)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001–004 (all formula implementations must exist before smoke check)
- Unlocks: None — this is the final story in the efficiency epic
