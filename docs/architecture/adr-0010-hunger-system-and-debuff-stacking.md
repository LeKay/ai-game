# ADR-0010: Hunger System and Debuff Stacking Architecture

## Status
Accepted

## Date
2026-05-13

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | HIGH — 4.4–4.6 beyond LLM training data |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — all APIs used are stable since Godot 1.0 (`_enter_tree`, `Engine.get_singleton()`) |
| **Verification Required** | Verify `day_transition` signal fires exactly once per 1000-tick cycle; verify `consume_food()` call order within day transition; verify multiplicative debuff stacking produces correct effective tick costs at 60fps and 144fps |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (tick system — `day_transition` signal triggers daily consumption), ADR-0005 (inventory system — `consume_food(daily_food_requirement)` interface, `storage_changed` signal), ADR-0007 (player character system — energy depletion multiplier for combined debuff stacking), ADR-0008 (building system — reads `hunger_debuff_active` to modify production cycles), ADR-0009 (npc system — `get_npc_count()` for daily food calculation) |
| **Enables** | NPC lifecycle stories (food pressure drives NPC management), HUD food status display, all NPC building stories (production speed modifier) |
| **Blocks** | NPC system production stories (NPC buildings read hunger debuff), Player Character stories (debuff stacking applies to player actions), Building System production stories (building cycle duration modified by hunger) |
| **Ordering Note** | Must be Accepted before any story that involves NPC food consumption, hunger debuff effects, or combined debuff stacking can begin. ADR-0009's validation criteria AC-8 (NPC building at 2× ticks when hungry) depends on this ADR. |

## Context

### Problem Statement

The Hunger System represents the escalating cost of expansion: every NPC recruited increases the daily food requirement by one unit, and when food runs out, the entire village slows to half speed. The system must:

1. **Calculate daily food requirements** — based on active NPC count from the NPC System (1 food unit per NPC per day).
2. **Consume food at day transition** — delegate deduction to the Inventory/Storage System's `consume_food()` interface, triggered by the Tick System's `day_transition` signal.
3. **Track debuff state** — binary state (FED / HUNGRY) with state transitions at day transition.
4. **Propagate debuff** — expose `hunger_debuff_active` and `hunger_tick_multiplier` as queryable interfaces to Player Character System (combined with energy depletion), Building System (production cycle duration), and HUD System (visual indicator).
5. **Stack debuffs multiplicatively** — hunger (2× tick cost) and energy depletion (2× tick cost) combine as `base × 2.0 × 2.0 = base × 4.0` when both are active.

### Constraints

- **Foundation Autoload pattern** — the Hunger System uses an Autoload singleton (`HungerSystem`), consistent with ADR-0001 through ADR-0009.
- **Tick-driven consumption** — daily food consumption is triggered exclusively by `day_transition` (TickSystem). No per-frame polling.
- **Delegation to InventorySystem** — the Hunger System never defines its own food deduction algorithm. It calls `InventorySystem.consume_food(daily_food_requirement)` and reads back `{hunger_debuff_applied: bool}`.
- **Binary state only** — the Hunger System has two states: FED and HUNGRY. There is no partial starvation, no health bar, no gradual decline. If food suffices, FED. If it doesn't, HUNGRY.
- **Multiplicative debuff stacking** — the Hunger System exposes multipliers, not absolute values. The Player Character System and Building System read these multipliers and apply them multiplicatively with their own debuff multipliers.

### Requirements

- Must manage 2 states: FED, HUNGRY.
- Must subscribe to TickSystem `day_transition` for daily consumption.
- Must call InventorySystem `consume_food(daily_food_requirement)` at each day transition.
- Must query NPCSystem `get_npc_count()` to compute daily requirement.
- Must expose `hunger_tick_multiplier` (2.0 when HUNGRY, 1.0 when FED) for other systems to read.
- Must expose `hunger_debuff_active: bool` for HUD display.
- Must serialize state for Save/Load (per ADR-0006).
- Must handle edge case: 0 NPCs = 0 food requirement = FED indefinitely.
- Must include defensive check: `consume_food()` only runs when `tick_count mod 1000 == 0`.

## Decision

### Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                   HungerSystem (Autoload)                         │
│                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │  Debuff Tracker  │  │  Daily Calculator│  │  Debuff       │ │
│  │  - state: FED/   │  │  (Formula 1)     │  │  Propagation  │ │
│  │    HUNGRY        │  │  (npc_count ×    │  │  Engine       │ │
│  │  - tick_mult:    │  │   npc_food_unit) │  │  (queries     │ │
│  │    1.0/2.0       │  └──────────────────┘  │   for other   │ │
│  │  - output_mult:  │                        │   systems)    │ │
│  │    1.0           │  ┌──────────────────┐  └───────────────┘ │
│  └──────────────────┘  │  SaveLoadHandler │                         │
│                        │  (serialize/     │                         │
│                        │   deserialize)   │                         │
│                        └──────────────────┘                         │
└──────────────────────────────────────────────────────────────────┘
```

### Core Design

**HungerSystem** extends `Object` (no scene tree functionality needed) and is registered as a Godot Autoload (project settings → AutoLoad → `hunger_system.gd` → Path: `res://src/gameplay/hunger_system.gd`). This matches the Foundation Autoload pattern established in ADR-0001 through ADR-0009.

Singleton references are cached at class level to avoid repeated `Engine.get_singleton()` lookups:

```gdscript
var _tick: Node
var _inventory: Node
var _npc: Node

func _enter_tree() -> void:
	var tick := Engine.get_singleton("TickSystem")
	var inventory := Engine.get_singleton("InventorySystem")
	var npc := Engine.get_singleton("NPCSystem")

# Null-check each reference — Autoload initialization order is determined by
# the order listed in project settings. If a referenced Autoload is not yet
# loaded, get_singleton() returns null. _enter_tree() is the earliest hook
# where Engine.get_singleton() can resolve autoloads. If null is encountered,
# log a warning and defer operations until the dependency loads.
# In VS scope the game starts with all Autoloads loaded, so this is a safety net.
```

### Debuff Tracker

Binary state machine. Two states, two transitions.

```
const NPC_FOOD_UNIT: float = 1.0

enum DebuffState { FED, HUNGRY }

var state: DebuffState = DebuffState.FED
var hunger_tick_multiplier: float = 1.0
var hunger_debuff_active: bool = false

# Formula: F = N × F_npc (daily food requirement)
func get_daily_food_requirement(npc_count: int) -> float:
	return float(npc_count) * NPC_FOOD_UNIT

# Called by day_transition handler
func apply_daily_consumption() -> void:
	if _tick == null:
		return
	# Guard: only run during actual day transitions
	# Defensive check against spurious signals
	if _tick.tick_count % 1000 != 0:
		return

	var requirement := get_daily_food_requirement(_npc.get_npc_count())

	# Delegate consumption to InventorySystem.
	# InventorySystem.consume_food(requirement: int) -> FoodConsumptionResult
	# FoodConsumptionResult is a Dictionary with keys:
	#   "hunger_debuff_applied" (bool), "food_consumed" (int), "remaining_deficit" (int)
	var result: Dictionary = _inventory.call("consume_food", requirement)

	# Empty result or missing flag → assume hungry (defensive fallback)
	if result.is_empty() or not result.has("hunger_debuff_applied") or result.get("hunger_debuff_applied", true):
		state = DebuffState.HUNGRY
		hunger_tick_multiplier = 2.0
		hunger_debuff_active = true
		hunger_state_changed.emit(hunger_tick_multiplier)
	else:
		state = DebuffState.FED
		hunger_tick_multiplier = 1.0
		hunger_debuff_active = false
		hunger_state_changed.emit(hunger_tick_multiplier)
```

### Debuff Propagation

The Hunger System exposes multipliers as queryable state. Other systems read these values and apply them multiplicatively with their own debuffs.

```
# Called by Player Character System on manual action start:
#   effective_tick = base_tick × pc.depletion_tick_mult × hunger.tick_mult
# Called by Building System on production cycle start:
#   effective_cycle = base_cycle × hunger.tick_mult
# Called by HUD System for display:
#   hud.show_debuff_info(hunger_debuff_active, hunger_tick_multiplier)

signal hunger_state_changed(new_tick_multiplier: float)
signal hunger_display_updated(fed: bool, food_available: int, food_required: int)

func get_hunger_tick_multiplier() -> float:
	return hunger_tick_multiplier  # 1.0 (FED) or 2.0 (HUNGRY)

# Note: hunger_output_multiplier is always 1.0 — hunger does not affect output.
# Kept for API extensibility if future rules change this.
func get_hunger_output_multiplier() -> float:
	return 1.0
```

### Serialization

Per ADR-0006, each system serializes its own state to a plain Dictionary:

```
func serialize() -> Dictionary:
	return {
		"schema_version": 1,
		"state": state,
		"hunger_tick_multiplier": hunger_tick_multiplier,
		"hunger_debuff_active": hunger_debuff_active,
	}

func deserialize(data: Dictionary) -> void:
	state = data.get("state", DebuffState.FED)
	hunger_tick_multiplier = data.get("hunger_tick_multiplier", 1.0)
	hunger_debuff_active = hunger_tick_multiplier == 2.0
```

### Daily Consumption Flow

```
# Subscribed once during _enter_tree()
func _on_day_transition(_days_elapsed: int) -> void:
	apply_daily_consumption()
	# After consumption, emit display update for HUD
	var food_total := _compute_total_food_units()
	var requirement := get_daily_food_requirement(_npc.get_npc_count())
	hunger_display_updated.emit(state == DebuffState.FED, food_total, requirement)

# Compute total food units across all containers.
# HungerSystem iterates containers itself — this method is not registered
# in the InventorySystem interface because it is internal to the HungerSystem.
func _compute_total_food_units() -> int:
	var total: int = 0
	var vs_foods: Array[StringName] = ["berry", "bread"]  # VS food items
	for container_id in _inventory.get_all_containers():
		var container := _inventory.get_container(container_id)
		for slot in container.get_slots():
			if vs_foods.has(slot.resource_id):
				var food_units := slot.quantity * _get_food_unit_value(slot.resource_id)
				total += food_units
	return total

func _get_food_unit_value(resource_id: StringName) -> float:
	match resource_id:
		"bread": return 2.0
		_: return 1.0  # default: 1 unit per berry
```

### Key Interfaces

#### Public API (called by other systems)

```
# Queries for multipliers (read by Player Character System, Building System)
get_hunger_tick_multiplier() -> float      # 1.0 (FED) or 2.0 (HUNGRY)
get_hunger_output_multiplier() -> float    # always 1.0
is_hunger_debuff_active() -> bool

# Queries for HUD
# get_total_food_units() is not a public API — HungerSystem computes it internally
# via get_all_containers() + get_resource_quantity(). Only the public methods below
# are exposed to other systems.
get_daily_food_requirement(npc_count: int) -> float
get_days_of_food_remaining(total_food: int, daily_requirement: int) -> int

# Consumption (called internally on day_transition; external calls are a no-op guard)
# External interface: delegates to InventorySystem.consume_food(requirement: int) -> FoodConsumptionResult
consume_food(requirement: int) -> void  # calls _inventory.consume_food(requirement)
```

#### Signals emitted

```
# State changes (propagation to other systems)
hunger_state_changed(new_tick_multiplier: float)

# HUD display updates
hunger_display_updated(fed: bool, food_available: int, food_required: int)
```

#### Signals subscribed to

```
# From TickSystem
day_transition(days_elapsed: int)  # trigger daily food consumption
```

#### External interface usage (registry-cross-referenced)

| Interface | Direction | How Used |
|-----------|-----------|-----------|
| `InventorySystem.consume_food(requirement: int) -> FoodConsumptionResult` | Hunger → Inventory | Daily food deduction at day transition |
| `InventorySystem.get_all_containers() -> Array[StringName]` | Hunger → Inventory | Internal iteration for total food unit computation |
| `InventorySystem.get_container(id) -> InventoryContainer?` | Hunger → Inventory | Slot scan for food resources |
| `NPCSystem.get_npc_count() -> int` | Hunger → NPC | Calculate daily food requirement (Formula 1) |

## Alternatives Considered

### Alternative A: Debuff on TickSystem

**Description**: Instead of a separate HungerSystem, the TickSystem owns the debuff state. The TickSystem's `day_transition` handler calls into HungerSystem logic, and the TickSystem exposes `get_debuff_multiplier()` that any system can query.

**Pros**:
- Single central source for all debuff state
- No new Autoload to register

**Cons**:
- The TickSystem already owns time; adding debuff state mixes concerns (time management vs. food management). This violates the single-responsibility principle established across all Foundation ADRs.
- The Hunger System's `consume_food()` logic requires InventorySystem delegation — TickSystem would need to know about InventorySystem, creating a new dependency chain that doesn't fit.
- The Player Character System already owns its own depletion multiplier (energy). Debuff stacking across systems is cleaner when each system holds its own multiplier and multiplies at query time.
- Breaks the Foundation pattern: all non-infrastructure systems (PlayerCharacter, BuildingRegistry, InventorySystem) are Autoload singletons. The Hunger System is infrastructure but not temporal infrastructure — it belongs in its own Autoload.

**Rejection Reason**: Mixing debuff tracking with time management violates the separation of concerns that defines the Foundation architecture. Each system owns its own state and exposes queryable multipliers.

### Alternative B: Additive Debuff Stacking

**Description**: Instead of multiplicative stacking, both debuffs subtract from a common "effective speed" pool. E.g., hunger = -50% speed, energy depletion = -50% speed → combined = -75% (not -100%).

**Pros**:
- More forgiving at extremes (player never hits 0% speed)
- Intuitive "speed bar" visualization

**Cons**:
- The GDD explicitly defines multiplicative stacking: `T_eff = T_base × M_depl × M_hung` (Formula 2). The additive model would require rewriting the GDD formulas.
- Multiplicative stacking has clearer mathematical properties: each debuff is independently tunable and independently means exactly "2× slower" or "half output." Additive stacking makes the combined effect non-intuitive.
- The GDD's player fantasy is "growth has a cost" — multiplicative stacking makes the cost steeper (4× baseline) and reinforces the urgency that drives the design loop.

**Rejection Reason**: The GDD (Formula 2) explicitly specifies multiplicative stacking. The design intent is clear: being hungry AND exhausted should feel dramatically worse than either alone. Additive stacking would weaken this core tension.

### Alternative C: Debuff as Action-Level Flag

**Description**: Instead of a global HungerSystem Autoload, each action (PlayerCharacter System, Building System) independently queries food levels and computes its own debuff.

**Pros**:
- No new system to register
- Actions are self-contained

**Cons**:
- Each action would need its own `get_food_units()` and `get_npc_count()` calls — duplicated logic across two systems.
- No single source of truth for hunger state (is the village FED or HUNGRY?). The HUD needs this to display food status.
- Debuff stacking would require each system to independently know about the other's multiplier — circular dependency between PlayerCharacter and Building via food state.
- Breaks the Foundation pattern: the Hunger System's `consume_food()` logic (daily food calculation, InventorySystem delegation, state tracking) is a system-level concern, not an action-level one.

**Rejection Reason**: The Hunger System's responsibilities (daily consumption, state tracking, debuff propagation) are system-level concerns that don't fit in action-specific code. A centralized Autoload is the correct home.

## Consequences

### Positive

- **Centralized debuff authority** — HungerSystem owns the food ledger and debuff state. Other systems query multipliers; they never compute food state themselves.
- **Clean multiplicative stacking** — each system owns its own multiplier and multiplies at query time. No coupling between debuff sources beyond the shared multiplication pattern.
- **Consistent with Foundation pattern** — Autoload singleton matches ADR-0001 through ADR-0009.
- **Defensive guardrails** — `tick_count % 1000 == 0` guard prevents double-deduction; null-fallback defaults to HUNGRY (assume worst case).
- **Delegation discipline** — HungerSystem never implements food deduction; it delegates to InventorySystem. This keeps consumption logic in one place.

### Negative

- **Autoload global state** — the HungerSystem is a global singleton, making isolated unit testing harder. Tests must mock or stub the Autoload.
- **Cross-Autoload dependency chain** — HungerSystem depends on NPCSystem (count), InventorySystem (consumption), and TickSystem (day_transition). Any of these being null at startup requires deferred initialization.
- **Binary state limits granularity** — the FED/HUNGRY binary means there's no "warning" state where the village is close to starvation. The HUD can compute `days_of_food_remaining`, but the system state itself is all-or-nothing.

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Double `day_transition` signal | If a spurious signal fires, the village could be double-charged for food. | `tick_count % 1000 == 0` guard ensures consumption only runs during actual day boundaries. The TickSystem guarantees exactly one `day_transition` per 1000-tick cycle. |
| InventorySystem interface change | If `consume_food()` signature changes, the Hunger System breaks at compile time (GDScript static typing). | The ADR explicitly documents the interface contract. Any signature change must update this ADR first. |
| NPC count stale at consumption time | If NPCs spawn/die between the last day transition and the current one, the requirement is based on the count at consumption time. | This is correct behavior — requirements are evaluated at consumption time, not at day start. Mid-day NPC spawns are documented in the GDD (EC-13). |
| Debuff query race condition | If a Player Character System reads `get_hunger_tick_multiplier()` while the Hunger System is processing `day_transition`, the value may be inconsistent. | `day_transition` fires synchronously — the hunger state is updated before any other system receives the signal. All other systems subscribe to `ticks_advanced()` which fires after `day_transition`. No race condition possible. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| hunger-system.md | Rule 1: Daily food consumption | `_on_day_transition()` calls `apply_daily_consumption()`, delegates to InventorySystem.consume_food() |
| hunger-system.md | Rule 2: Food unit values | `get_daily_food_requirement()` uses npc_food_unit = 1.0; food unit conversion handled by InventorySystem |
| hunger-system.md | Rule 3: Debuff activation/deactivation | Binary FED/HUNGRY state, `hunger_state_changed` signal propagates multiplier to other systems |
| hunger-system.md | Rule 4: NPC count | `get_daily_food_requirement(npc.get_npc_count())` queries NPCSystem |
| hunger-system.md | Rule 5: Consumption order | Delegates entirely to InventorySystem.consume_food() |
| hunger-system.md | Rule 6: No death — debuff only | State machine produces FED/HUNGRY binary — no death mechanics |
| hunger-system.md | Formula 1: Daily Food Requirement | `get_daily_food_requirement()` = npc_count × npc_food_unit |
| hunger-system.md | Formula 2: Combined Debuff Stack | Exposes `hunger_tick_multiplier` (1.0/2.0) for multiplicative stacking |
| hunger-system.md | Formula 4: Days of Food Remaining | `get_days_of_food_remaining()` with division-by-zero guard |
| hunger-system.md | EC-12: 0 NPCs = FED indefinitely | `get_daily_food_requirement(0) = 0`, `consume_food(0)` exits immediately |
| hunger-system.md | EC-14: consume_food guard | `tick_count % 1000 == 0` check in `apply_daily_consumption()` |
| hunger-system.md | AC-6 through AC-9: Debuff behavior | `get_hunger_tick_multiplier()` returns 2.0 when HUNGRY, verified by validation criteria |

## Performance Implications

- **CPU**: 0.002ms per day transition (one NPC count query, one InventorySystem.consume_food call, one state comparison). Zero per-frame cost — no `_process()`. The `hunger_state_changed` signal fires once per day transition.
- **Memory**: ~100 bytes per HungerSystem instance (2 floats, 1 enum, 2 StringName, 1 bool). Negligible.
- **Load Time**: HungerSystem deserializes state from WorldSaveManager (ADR-0006). Instant — no scene instantiation.
- **Network**: N/A — single-player game.

## Migration Plan

This ADR creates a new Foundation system. No migration from existing code is needed — the Hunger System has not yet been implemented. Implementation should begin after ADR-0001 (Tick System), ADR-0005 (Inventory System), ADR-0007 (Player Character), ADR-0008 (Building Registry), and ADR-0009 (NPC System) are accepted, as the Hunger System depends on all of them.

### Implementation Order

1. **HungerSystem core** — state machine, `get_daily_food_requirement()`, `get_hunger_tick_multiplier()`. Standalone, no dependencies.
2. **Day Transition Handler** — `apply_daily_consumption()`. Depends on TickSystem and InventorySystem stubs.
3. **Debuff Propagation** — `hunger_state_changed` signal emission. Depends on NPCSystem stub.
4. **Save/Load Integration** — depends on WorldSaveManager (ADR-0006).
5. **HungerSystem (full)** — ties everything together, signal subscriptions, HUD interface.

## Validation Criteria

| # | Criteria | Method |
|---|----------|--------|
| 1 | 0 NPCs → consume_food(0) → FED state, no storage scan | Automated: mock NPC System returning 0, fire day transition, assert state = FED |
| 2 | 2 NPCs, 3 food → consume 2, FED, 1 remaining | Automated: place 3 berries, fire transition, assert 1 berry left, state = FED |
| 3 | 2 NPCs, 1 food → consume 1, HUNGRY, deficit 1 | Automated: place 1 berry, fire transition, assert 0 berries, state = HUNGRY |
| 4 | HUNGRY → add 2 food → next day transition → FED | Automated: create HUNGRY → add berries → fire transition → assert FED |
| 5 | Hunger tick multiplier is 1.0 when FED, 2.0 when HUNGRY | Automated: assert multipliers before/after day transition |
| 6 | Multiplicative stacking: hunger (2.0) × depletion (2.0) = 4.0 | Automated: set HUNGRY + 0 Energy, execute action base=80, assert effective=320 |
| 7 | `tick_count % 1000 != 0` guard prevents consumption outside day transition | Automated: call consume_food at tick 500, assert no food consumed |
| 8 | `consume_food()` returns null → defaults to HUNGRY | Automated: mock consume_food to return null, assert state = HUNGRY |

## Related Decisions

- ADR-0001: Tick System Design and Time Management (day_transition signal, tick accumulation)
- ADR-0005: Inventory and Item State Machine (consume_food interface, storage queries)
- ADR-0007: Player Character Energy Model and Manual Action System (depletion multiplier for combined debuff)
- ADR-0008: Building Placement and Production System (building reads hunger debuff for production cycle)
- ADR-0009: NPC State Machine and Movement (get_npc_count for daily food calculation)
- GDD: design/gdd/hunger-system.md (full mechanical specification, 361 lines)
- GDD: design/gdd/player-character-system.md (energy depletion for combined debuff stacking)
