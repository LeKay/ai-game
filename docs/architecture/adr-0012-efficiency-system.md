# ADR-0012: Efficiency System — Entity Property and Formula Architecture

## Status
Accepted

## Date
2026-06-03

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Gameplay |
| **Knowledge Risk** | LOW — pure GDScript math, no post-cutoff APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None — `clampf`, `floori`, `maxi` are stable since Godot 4.0 |
| **Verification Required** | Verify `clampf` behaves correctly at 0.0 boundary; verify `floori` matches expected rounding for negative float inputs (should not occur but guard anyway) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0009 (NPC State Machine — NPCData class, assignment hooks), ADR-0008 (Building System — BuildingData class, production cycle), ADR-0010 (Hunger System — `hunger_state_changed` signal used as efficiency update trigger), ADR-0011 (Logistics System — carrier travel ticks computation) |
| **Enables** | Equipment System (equipment_modifier hook already present on NPCData), Satisfaction System (satisfaction_modifier hook), Building Upgrade System (upgrade_bonus field) |
| **Blocks** | None — efficiency system is additive on top of existing systems; does not gate any other ADR |
| **Ordering Note** | Must be Accepted before any story that uses `building.efficiency` or `npc.efficiency` to modify cycle or travel ticks. ADR-0010 stories that apply the hunger debuff must route through this system rather than applying a direct 2× multiplier. |

## Context

### Problem Statement

Multiple systems need to express "how well is this building or NPC currently performing?" The Hunger System applies a 2× tick cost debuff; the future Equipment and Satisfaction systems will add further modifiers. Without a unified efficiency layer these modifiers accumulate as ad-hoc multipliers scattered across Building, NPC, and Logistics systems. This creates:

1. **Duplicate debuff logic** — Hunger applies 2× to buildings directly, but the same concept (reduced efficiency) will be re-implemented for equipment and satisfaction.
2. **No unified read surface** — UI components (route lines, building status) must query multiple systems to display "current performance."
3. **Formula fragmentation** — F3 and F4 (cycle ticks, travel ticks) are defined in the quick spec but have no single implementation location.

The efficiency system defines a unified numeric property (0.0–2.0, base 1.0) on entities and the formulas to apply it.

### Constraints

- **No new Autoload** — efficiency is a computed property on existing entity data classes (NPCData, BuildingData). The Hunger System already has an Autoload; this system piggybacks on existing signals rather than introducing new infrastructure.
- **Pure math only** — efficiency formulas have no state dependencies beyond their inputs. They live in a static class.
- **Signal-driven updates** — efficiency recalculates when modifiers change (signal subscription), not on every tick (no polling).
- **Config-driven** — all tuning values come from `assets/data/efficiency-config.json`, never hardcoded.
- **Backward-compatible debuff** — the Hunger System's existing 2× cycle behavior must be preserved, just re-routed through the efficiency layer.

### Requirements

- NPCData must expose `efficiency: float` and `recalculate_efficiency()`.
- BuildingData must expose `efficiency: float` and `recalculate_efficiency(workers)`.
- A static `EfficiencyFormulas` class must implement F1–F4.
- NPCSystem must subscribe to `HungerSystem.hunger_state_changed` and propagate to all NPCs.
- BuildingRegistry must call `building.recalculate_efficiency()` on worker assign/unassign.
- LogisticsSystem must use F4 for carrier travel ticks instead of the raw Manhattan formula.
- BuildingRegistry must use F3 for production cycle ticks instead of the raw base value.

## Decision

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                  EfficiencyFormulas (static class)               │
│  F1: calculate_npc_efficiency(h, s, e) -> float                 │
│  F2: calculate_building_efficiency(workers, upgrade) -> float   │
│  F3: calculate_effective_cycle_ticks(base, eff) -> int          │
│  F4: calculate_effective_travel_ticks(base, eff) -> int         │
└──────────────────────────┬──────────────────────────────────────┘
                           │ (used by)
              ┌────────────┴────────────┐
              ▼                         ▼
   ┌──────────────────┐      ┌──────────────────────┐
   │    NPCData       │      │    BuildingData       │
   │  efficiency: float│     │  efficiency: float    │
   │  hunger_modifier  │     │  upgrade_bonus: float │
   │  satisfaction_mod │     │  recalculate_         │
   │  equipment_mod    │     │  efficiency(workers)  │
   │  recalculate_     │     └──────────────────────┘
   │  efficiency()     │
   └──────────────────┘
          ▲
          │ hunger_state_changed(multiplier)
   ┌──────────────┐
   │ HungerSystem │
   └──────────────┘
```

### EfficiencyFormulas Static Class

Location: `res://src/systems/efficiency/efficiency_formulas.gd`

```gdscript
class_name EfficiencyFormulas

const EFFICIENCY_MIN: float = 0.0
const EFFICIENCY_MAX: float = 2.0

# F1: NPC efficiency — multiplicative modifiers clamped to [0.0, 2.0]
static func calculate_npc_efficiency(
    hunger_mod: float,
    satisfaction_mod: float,
    equipment_mod: float
) -> float:
    return clampf(1.0 * hunger_mod * satisfaction_mod * equipment_mod,
                  EFFICIENCY_MIN, EFFICIENCY_MAX)

# F2: Building efficiency — 1.0 base + sum of worker deltas + upgrade bonus, clamped
static func calculate_building_efficiency(
    worker_efficiencies: Array[float],
    upgrade_bonus: float
) -> float:
    var delta: float = 0.0
    for eff in worker_efficiencies:
        delta += (eff - 1.0)
    return clampf(1.0 + delta + upgrade_bonus, EFFICIENCY_MIN, EFFICIENCY_MAX)

# F3: Effective production cycle ticks — base / building.efficiency, minimum 1
# At efficiency=0.0: returns sentinel MAX_INT to represent "frozen"
static func calculate_effective_cycle_ticks(base_ticks: int, building_efficiency: float) -> int:
    if building_efficiency <= 0.0:
        return 2147483647  # INT_MAX sentinel: building is frozen
    return maxi(1, floori(float(base_ticks) / building_efficiency))

# F4: Effective travel ticks — base / npc.efficiency, minimum 1
static func calculate_effective_travel_ticks(base_ticks: int, npc_efficiency: float) -> int:
    if npc_efficiency <= 0.0:
        return 2147483647  # INT_MAX sentinel: NPC cannot travel
    return maxi(1, floori(float(base_ticks) / npc_efficiency))
```

### NPCData Extension

Add to existing NPCData (or NPC entity class, wherever NPCs store per-entity data):

```gdscript
# Efficiency modifiers — set by external systems via signals
var hunger_modifier: float = 1.0        # set by HungerSystem
var satisfaction_modifier: float = 1.0  # set by future SatisfactionSystem
var equipment_modifier: float = 1.0     # set by future EquipmentSystem

# Computed efficiency — call recalculate_efficiency() after any modifier changes
var efficiency: float = 1.0

func recalculate_efficiency() -> void:
    efficiency = EfficiencyFormulas.calculate_npc_efficiency(
        hunger_modifier, satisfaction_modifier, equipment_modifier
    )
```

### BuildingData Extension

Add to existing BuildingData (or building instance class):

```gdscript
var upgrade_bonus: float = 0.0  # set by future UpgradeSystem; 0.0 at VS scope
var efficiency: float = 1.0

func recalculate_efficiency(assigned_workers: Array) -> void:
    var worker_efficiencies: Array[float] = []
    for worker in assigned_workers:
        worker_efficiencies.append(worker.efficiency)
    efficiency = EfficiencyFormulas.calculate_building_efficiency(
        worker_efficiencies, upgrade_bonus
    )
```

### Signal Integration — Hunger → NPC Efficiency

NPCSystem subscribes to HungerSystem.hunger_state_changed in `_enter_tree()`:

```gdscript
func _enter_tree() -> void:
    # ... existing singleton setup ...
    var hunger := Engine.get_singleton("HungerSystem")
    if hunger != null:
        hunger.hunger_state_changed.connect(_on_hunger_state_changed)

func _on_hunger_state_changed(new_tick_multiplier: float) -> void:
    # hunger_modifier = inverse of tick_multiplier
    # tick_multiplier 2.0 = slow → hunger_modifier 0.5 (half speed)
    # tick_multiplier 1.0 = normal → hunger_modifier 1.0
    var hunger_mod: float = 1.0 / new_tick_multiplier if new_tick_multiplier > 0.0 else 0.0
    for npc in get_all_npcs():
        npc.hunger_modifier = hunger_mod
        npc.recalculate_efficiency()
    # Trigger building efficiency recalculation for all buildings with assigned workers
    _propagate_worker_efficiency_change()
```

**Important**: `hunger_tick_multiplier` in HungerSystem is 2.0 when hungry, 1.0 when fed.
`hunger_modifier` in EfficiencyFormulas is 0.5 when hungry, 1.0 when fed.
These are inverses: `hunger_modifier = 1.0 / hunger_tick_multiplier`.
The signal carries the tick multiplier (HungerSystem's existing API); NPCSystem converts on receive.

### Production Cycle Integration

BuildingRegistry replaces the direct `base_cycle_ticks` usage:

```gdscript
# Before (current implementation):
var effective_ticks: int = base_cycle_ticks * hunger_system.get_hunger_tick_multiplier()

# After (with efficiency system):
var effective_ticks: int = EfficiencyFormulas.calculate_effective_cycle_ticks(
    base_cycle_ticks, building.efficiency
)
# building.efficiency already incorporates the hunger effect via worker NPC efficiency
```

The Hunger System's direct `hunger_tick_multiplier` read on buildings is removed; the effect flows through `worker.hunger_modifier → npc.efficiency → building.efficiency → effective_cycle_ticks`.

### Carrier Travel Integration

LogisticsSystem replaces the raw Manhattan calculation:

```gdscript
# Before (current implementation):
var travel_ticks: int = floori(manhattan_distance * ticks_per_tile)

# After (with efficiency system):
var base_travel_ticks: int = floori(manhattan_distance * ticks_per_tile)
var travel_ticks: int = EfficiencyFormulas.calculate_effective_travel_ticks(
    base_travel_ticks, carrier_npc.efficiency
)
```

### Config Loading

`EfficiencyConfig` singleton (Autoload, lightweight) reads `assets/data/efficiency-config.json` at startup and exposes constants. `EfficiencyFormulas` uses `EfficiencyConfig.HUNGER_MODIFIER_HUNGRY` etc. rather than magic numbers.

Alternatively, constants can live directly in `EfficiencyFormulas` with the JSON loader as a separate `_load_config()` method called from NPCSystem._enter_tree(). The simpler approach for VS scope is to embed defaults in `EfficiencyFormulas` and override from JSON if present.

### Key Interfaces

```gdscript
# EfficiencyFormulas (static — no instance needed)
EfficiencyFormulas.calculate_npc_efficiency(h, s, e) -> float
EfficiencyFormulas.calculate_building_efficiency(workers, bonus) -> float
EfficiencyFormulas.calculate_effective_cycle_ticks(base, eff) -> int
EfficiencyFormulas.calculate_effective_travel_ticks(base, eff) -> int

# NPCData (extended)
npc.efficiency: float                    # read by BuildingData, LogisticsSystem
npc.hunger_modifier: float               # written by NPCSystem on hunger_state_changed
npc.recalculate_efficiency() -> void     # called after any modifier changes

# BuildingData (extended)
building.efficiency: float               # read by BuildingRegistry cycle computation
building.recalculate_efficiency(workers) # called on worker assign/unassign
```

## Alternatives Considered

### Alternative A: EfficiencySystem Autoload Singleton

**Description**: A new `EfficiencySystem` Autoload that manages all efficiency state, similar to HungerSystem.

**Pros**: Consistent with Foundation pattern; centralized read surface.

**Cons**: The efficiency property is fundamentally per-entity data (each NPC and building has its own value). A singleton would need to maintain Dictionary[npc_id → efficiency] maps. This is the same as adding a property to the entity data class, but with an extra indirection layer. No new state machine or daily computation logic justifies a singleton.

**Rejection Reason**: Entity data belongs on entity classes. A singleton adds indirection without adding value. EfficiencyFormulas as a static class provides the same centralized formula location without the overhead.

### Alternative B: Polling in Production Cycle

**Description**: BuildingRegistry reads `HungerSystem.get_hunger_tick_multiplier()` directly in each production cycle tick, as it does today. Add equipment and satisfaction reads similarly.

**Pros**: Simple, no new classes or properties needed.

**Cons**: As the number of modifiers grows (hunger + equipment + satisfaction + upgrades), the production cycle becomes a list of `get_X_multiplier()` calls scattered across multiple singletons. Each new modifier requires editing `building_registry.gd`. There is no single place that computes "current building efficiency."

**Rejection Reason**: Violates single-responsibility. The efficiency formula should live in one place, not be scattered across caller sites.

### Alternative C: Efficiency Recomputed Every Tick

**Description**: Instead of signal-driven recomputation, call `recalculate_efficiency()` on every production tick for all entities.

**Pros**: Always up-to-date; no risk of stale cached values.

**Cons**: Unnecessary CPU overhead. Efficiency modifiers change infrequently (only at day transition for hunger, only on equipment change). Per-tick recalculation for 50+ NPCs and 20+ buildings wastes ~0.01ms/frame for no benefit.

**Rejection Reason**: Signal-driven updates are correct and sufficient. Efficiency changes are event-driven (day transition, assignment, equipment change), not continuous.

## Consequences

### Positive

- **Unified formula surface** — all efficiency math in `EfficiencyFormulas`; no scattered multipliers.
- **Forward-compatible modifier hooks** — `satisfaction_modifier` and `equipment_modifier` fields exist on NPCData from day one; future systems just set them and call `recalculate_efficiency()`.
- **Regression-safe** — the hunger 2× behavior is preserved exactly: `hunger_mod=0.5 → npc.efficiency=0.5 → building.efficiency=0.5 → effective_cycle_ticks = base × 2`.
- **No new Autoload** — consistent with the spirit of the Foundation pattern without adding infrastructure overhead.

### Negative

- **Indirect hunger propagation** — the hunger effect now flows through three steps (HungerSystem signal → NPCSystem → NPC.efficiency → Building.efficiency) instead of a direct read. This is more correct architecturally but adds debugging complexity.
- **Stale efficiency risk** — if a worker is assigned mid-cycle and building.recalculate_efficiency() is not called, the building may use a stale efficiency value until the next assignment event. The fix is to call recalculate at assignment time, which must be enforced in BuildingRegistry.

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| HungerSystem signal not connected | NPCs keep efficiency=1.0 even when hungry — hunger debuff silently missing | Unit test: mock hunger_state_changed, assert npc.efficiency=0.5 after emit |
| Worker assigned without recalculate call | Building uses stale efficiency for one cycle | BuildingRegistry always calls recalculate on assign/unassign — enforced by integration test |
| tick_multiplier=0 (edge case) | Division by zero in hunger_modifier conversion | Guard: `1.0 / new_tick_multiplier if new_tick_multiplier > 0.0 else 0.0` |
| efficiency=0.0 at production cycle | INT_MAX sentinel causes visual freeze | F3/F4 return INT_MAX; BuildingRegistry must treat this as STALLED, not produce at tick INT_MAX |

## GDD Requirements Addressed

| Quick Spec | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| efficiency-system-2026-06-03.md | Rule 1: Efficiency as speed multiplier | F3 and F4: `effective_ticks = floor(base / efficiency)` |
| efficiency-system-2026-06-03.md | Rule 2: NPC efficiency (multiplicative) | F1: `clamp(1.0 × h × s × e, 0, 2)` in EfficiencyFormulas |
| efficiency-system-2026-06-03.md | Rule 3: Building efficiency (worker delta) | F2: `clamp(1.0 + Σ(w-1.0) + upgrade, 0, 2)` in EfficiencyFormulas |
| efficiency-system-2026-06-03.md | Rule 4: Production cycle | BuildingRegistry uses F3 instead of raw base_cycle_ticks |
| efficiency-system-2026-06-03.md | Rule 5: Carrier travel | LogisticsSystem uses F4 instead of raw Manhattan ticks |
| efficiency-system-2026-06-03.md | Rule 6: UI thresholds | Constants in EfficiencyFormulas: ≥1.0 green, 0.5–1.0 yellow, <0.5 red |

## Performance Implications

- **CPU**: Zero per-frame overhead — recalculation is event-driven. Each recalculate call is O(workers) per building (max ~2 at VS scope). At day transition: O(npcs) for hunger propagation, ~0.01ms total.
- **Memory**: ~24 bytes per NPC (3 modifier floats + 1 efficiency float). ~8 bytes per building (upgrade_bonus + efficiency). Negligible.
- **Load Time**: EfficiencyFormulas is a static class with no initialization. Config JSON read is O(config entries), instant.

## Related Decisions

- ADR-0008: Building Placement and Production System (building cycle ticks — F3 replaces direct multiplier read)
- ADR-0009: NPC State Machine and Movement (NPCData extended with efficiency property)
- ADR-0010: Hunger System and Debuff Stacking (hunger_state_changed signal drives NPC efficiency update)
- ADR-0011: Logistics System (carrier travel ticks — F4 replaces direct Manhattan formula)
- Quick Spec: design/quick-specs/efficiency-system-2026-06-03.md
