# From Scratch — Master Architecture

## Document Status

- Version: 1.0
- Last Updated: 2026-05-13
- Engine: Godot 4.6
- GDDs Covered: tick-system, resource-system, input-system, player-character-system, grid-map-system, inventory-storage-system, building-system, camera-system, npc-system, hunger-system, hud-system
- ADRs Referenced: none yet (10 required — see Required ADRs section)
- Technical Director Sign-Off: 2026-05-13 — APPROVED WITH CONDITIONS
- Condition: All 10 Required ADRs must be written before stories are created for covered systems

---

## Engine Knowledge Gap Summary

**LLM Training Covers:** up to approximately Godot 4.3
**Post-Cutoff Versions:** 4.4 (NEAR-CUTOFF), 4.5 (HIGH), 4.6 (HIGH)

### HIGH RISK Domains

- **Navigation (4.5):** Dedicated 2D nav server (no longer a proxy to 3D). NavigationRegion2D lost `avoidance_layers`. Use `NavigationAgent2D` for pathfinding. NPC vertical-slice design uses Manhattan movement (no NavigationAgent needed for VS scope — risk deferred).
- **Rendering (4.6):** Glow processes BEFORE tonemapping (visual output changed). D3D12 default on Windows (was Vulkan). SSR overhauled. Adjust WorldEnvironment glow settings after engine upgrade.
- **UI (4.6):** Dual-focus system — mouse/touch focus is now SEPARATE from keyboard/gamepad focus. Both `grab_focus()` paths must be tested. HUD must handle both simultaneously.

### MEDIUM RISK Domains

- **Input (4.5/4.6):** SDL3 gamepad driver — API unchanged but backend different. Dual-focus affects all UI interaction. Test gamepad navigation of HUD.
- **GDScript (4.5):** Variadic arguments and `@abstract` decorator now available. Can simplify abstract base classes for system components. No breaking risk, additive only.
- **Resources (4.5):** `duplicate_deep()` is a new explicit method. `duplicate()` on nested resources now behaves differently — use `duplicate_deep()` explicitly.

### LOW RISK Domains

- Core scripting (signal architecture, @onready, node lifecycle) — unchanged
- Camera2D pan/zoom — API stable
- FileAccess — return type changed to bool in 4.4, caught at compile time

### CRITICAL: Deprecated APIs to Avoid

| Do NOT use | Use instead |
|------------|-------------|
| `TileMap` | `TileMapLayer` (deprecated since 4.3) |
| `yield()` | `await signal` |
| `instance()` / `PackedScene.instance()` | `instantiate()` |
| `get_world()` | `get_world_3d()` |
| `connect("signal", obj, "method")` | `signal.connect(callable)` |
| `$NodePath` in `_process()` | `@onready var` cached reference |
| Untyped `Array` / `Dictionary` | `Array[Type]`, typed variables |
| `Texture2D` in shader parameters | `Texture` base type (changed 4.4) |
| `duplicate()` for nested resources | `duplicate_deep()` |
| `AnimationPlayer.playback_active` | `AnimationMixer.active` |

---

## Technical Requirements Baseline

Extracted from 11 GDDs | 56 total requirements

| Req ID | GDD | System | Requirement | Domain |
|--------|-----|--------|-------------|--------|
| TR-tick-001 | tick-system.md | Tick | 1000-tick/day float accumulator | Core |
| TR-tick-002 | tick-system.md | Tick | 3 speed modes (0.5×/1×/2×) + pause state | Core |
| TR-tick-003 | tick-system.md | Tick | Tick signal emission to all subscribers per tick | Core |
| TR-tick-004 | tick-system.md | Tick | Manual action tick advancement (player actions cost ticks) | Core |
| TR-tick-005 | tick-system.md | Tick | Day-transition event + auto-pause | Core |
| TR-tick-006 | tick-system.md | Tick | Determinism: same seed → same tick sequence | Core |
| TR-res-001 | resource-system.md | Resource | JSON data registry loaded at startup | Foundation |
| TR-res-002 | resource-system.md | Resource | Resource definition: id/name/category/stack_limit/weight/base_value/icons | Foundation |
| TR-res-003 | resource-system.md | Resource | Schema validation on load (fail fast) | Foundation |
| TR-res-004 | resource-system.md | Resource | O(1) id-keyed runtime lookup | Foundation |
| TR-res-005 | resource-system.md | Resource | Two categories: Consumables / Production Goods | Foundation |
| TR-input-001 | input-system.md | Input | Unified action mapping: keyboard+mouse + gamepad | Foundation |
| TR-input-002 | input-system.md | Input | Input context switching (WORLD_ACTIVE/UI_ACTIVE/PAUSED) | Foundation |
| TR-input-003 | input-system.md | Input | Context transition on UI open/close | Foundation |
| TR-input-004 | input-system.md | Input | Input debouncing for rapid presses | Foundation |
| TR-input-005 | input-system.md | Input | Mouse position → world tile coordinate conversion | Foundation |
| TR-player-001 | player-character-system.md | Player | Energy pool (0–100) with tick-based drain | Core |
| TR-player-002 | player-character-system.md | Player | Manual action dispatch (forage/pick/craft/chop/mine/transport) with energy cost | Core |
| TR-player-003 | player-character-system.md | Player | Drag-and-drop transport (carry item from tile to storage) | Core |
| TR-player-004 | player-character-system.md | Player | Energy depletion: 2× tick cost + 50% output at 0 energy | Core |
| TR-player-005 | player-character-system.md | Player | Food-to-energy refill on food consumption | Core |
| TR-player-006 | player-character-system.md | Player | Architect Mode lock after first NPC assigned | Core |
| TR-grid-001 | grid-map-system.md | Grid | 30×30 tile grid, 3-layer data model (Terrain/Resource/Building) | Core |
| TR-grid-002 | grid-map-system.md | Grid | TileMapLayer rendering (TileMap deprecated — must not use) | Core |
| TR-grid-003 | grid-map-system.md | Grid | Perlin noise procedural terrain generation at world init | Core |
| TR-grid-004 | grid-map-system.md | Grid | validate_placement gate (checks all 3 layers before any placement) | Core |
| TR-grid-005 | grid-map-system.md | Grid | Manhattan + Euclidean distance functions | Core |
| TR-grid-006 | grid-map-system.md | Grid | World-space ↔ tile-coordinate conversion | Core |
| TR-inv-001 | inventory-storage-system.md | Inventory | InventoryContainer with first-fit stacking algorithm | Core |
| TR-inv-002 | inventory-storage-system.md | Inventory | Resource state machine: DROPPED → IN_TRANSIT → STORED/LOST | Core |
| TR-inv-003 | inventory-storage-system.md | Inventory | Transport energy/tick cost formulas | Core |
| TR-inv-004 | inventory-storage-system.md | Inventory | Hunger consumption priority: lowest-quantity storage bin first | Core |
| TR-inv-005 | inventory-storage-system.md | Inventory | Storage Area (50 slots) + Storage Building (150 slots) | Core |
| TR-inv-006 | inventory-storage-system.md | Inventory | Items only consumed from STORED state | Core |
| TR-build-001 | building-system.md | Building | 1-tile footprint placement with cost deduction | Feature |
| TR-build-002 | building-system.md | Building | 4 building types for Vertical Slice: Storage Area, Storage Building, Residential House, Lumber Camp | Feature |
| TR-build-003 | building-system.md | Building | Tick-based build time progression | Feature |
| TR-build-004 | building-system.md | Building | Production cycle tick advancement | Feature |
| TR-build-005 | building-system.md | Building | NPC assignment slots per building | Feature |
| TR-cam-001 | camera-system.md | Camera | Pan: WASD/arrows/middle-drag/edge-scroll | Core |
| TR-cam-002 | camera-system.md | Camera | Zoom 0.85–2.0 anchored to mouse position | Core |
| TR-cam-003 | camera-system.md | Camera | Boundary clamping (cannot scroll outside world bounds) | Core |
| TR-cam-004 | camera-system.md | Camera | Screen → tile coordinate conversion (click → tile) | Core |
| TR-cam-005 | camera-system.md | Camera | Fit-to-view on R key | Core |
| TR-npc-001 | npc-system.md | NPC | NPC data: id/name/state/assignment/current_task | Feature |
| TR-npc-002 | npc-system.md | NPC | State machine: IDLE→TRAVEL→WORK→DEPOSIT→RETURN | Feature |
| TR-npc-003 | npc-system.md | NPC | Manhattan-distance movement (abstract, no sprites) | Feature |
| TR-npc-004 | npc-system.md | NPC | Recruitment: 2 NPCs per Residential House | Feature |
| TR-npc-005 | npc-system.md | NPC | Task assignment with storage selection | Feature |
| TR-npc-006 | npc-system.md | NPC | Demolition disconnects NPC assignment | Feature |
| TR-hunger-001 | hunger-system.md | Hunger | Daily consumption: 1 food unit per NPC per day | Feature |
| TR-hunger-002 | hunger-system.md | Hunger | Hunger debuff: 2× tick cost for travel/work | Feature |
| TR-hunger-003 | hunger-system.md | Hunger | Combined debuff: hunger × energy depletion = 4× tick cost | Feature |
| TR-hunger-004 | hunger-system.md | Hunger | Food unit conversion: berry=1, bread=2 | Feature |
| TR-hud-001 | hud-system.md | HUD | Real-time display: energy, day, time-of-day, resource counts | Presentation |
| TR-hud-002 | hud-system.md | HUD | Days-of-food-remaining calculation + display | Presentation |
| TR-hud-003 | hud-system.md | HUD | Notification system (building complete, NPC hungry, storage full) | Presentation |
| TR-hud-004 | hud-system.md | HUD | Time controls in HUD (speed buttons, pause) | Presentation |
| TR-hud-005 | hud-system.md | HUD | Dual-focus aware UI (mouse + keyboard/gamepad) | Presentation |

---

## System Layer Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                                          │
│                                                                              │
│  HUD System                                                                  │
│  (time controls, resource display, notifications, days-of-food)              │
│  ⚠️  HIGH: Dual-focus (4.6), AccessKit screen reader (4.5)                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  FEATURE LAYER                                                               │
│                                                                              │
│  Building System       NPC System              Hunger System                 │
│  (placement, build     (state machine,         (daily consumption,           │
│   time, prod cycles,    abstract movement,      debuff stacking,             │
│   NPC slots)            recruitment)            food priority)               │
│                        ⚠️  LOW (VS scope):                                   │
│                        Manhattan movement,                                   │
│                        no NavigationAgent2D needed                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  CORE LAYER                                                                  │
│                                                                              │
│  Grid Map System       Player Character        Camera System                 │
│  (30×30 3-layer data,  (energy pool,           (pan/zoom,                   │
│   TileMapLayer,         manual actions,         screen-to-tile,              │
│   Perlin gen,           drag-and-drop,          boundary clamp)              │
│   validate_placement)   Architect Mode)         LOW risk                     │
│  ⚠️  HIGH: TileMapLayer                         LOW risk                     │
│  (not TileMap)                                                               │
│                                                                              │
│  Inventory/Storage System                                                    │
│  (InventoryContainer, first-fit stacking,                                    │
│   DROPPED→IN_TRANSIT→STORED state machine,                                   │
│   storage bin priority)                                                      │
│  LOW risk                                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  FOUNDATION LAYER                                                            │
│                                                                              │
│  Tick System           Resource System         Input System                  │
│  (1000 tick/day,       (JSON registry,         (action mapping,              │
│   3 speeds + pause,     O(1) lookup,            context switching,           │
│   determinism,          schema validation)      debouncing)                  │
│   day transition)       LOW risk                ⚠️  MEDIUM: SDL3 (4.5),      │
│  LOW risk                                       dual-focus (4.6)             │
├─────────────────────────────────────────────────────────────────────────────┤
│  PLATFORM LAYER                                                              │
│  Godot 4.6 Engine API (TileMapLayer, Camera2D, Control, NavigationServer2D) │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer Assignment Summary

| System | Layer | Engine Risk | Risk Reason |
|--------|-------|-------------|-------------|
| HUD System | Presentation | HIGH | Dual-focus (4.6), AccessKit (4.5) |
| Building System | Feature | LOW | Pure data + Grid dependency |
| NPC System | Feature | LOW (VS scope) | Manhattan movement; no NavigationAgent2D needed |
| Hunger System | Feature | LOW | Pure data calculations |
| Grid Map System | Core | HIGH | TileMap deprecated → must use TileMapLayer |
| Player Character System | Core | LOW | Signal-based state, no engine-specific APIs |
| Camera System | Core | LOW | Camera2D API stable |
| Inventory/Storage System | Core | LOW | Pure data + signals |
| Tick System | Foundation | LOW | Core GDScript patterns, unchanged |
| Resource System | Foundation | LOW | FileAccess bool return caught at compile time |
| Input System | Foundation | MEDIUM | SDL3 (4.5), dual-focus affects context switching |

---

## Module Ownership

### Foundation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **TickSystem** | `current_tick: int`, `current_day: int`, `speed_multiplier: float`, `paused: bool`, `tick_accumulator: float` | signals: `tick_advanced(tick: int)`, `day_ended(day: int)`, `speed_changed(multiplier: float)`; methods: `set_speed()`, `pause()`, `resume()`, `advance_ticks(n)` | Nothing — drives all others | `_process(delta)`, `Time.get_ticks_msec()` |
| **ResourceRegistry** | `_definitions: Dictionary[StringName, ResourceDefinition]` loaded from JSON | `get_definition(id: StringName) -> ResourceDefinition`, `is_valid_id(id) -> bool`, `get_all_by_category(cat) -> Array[ResourceDefinition]` | JSON data file at startup only | `FileAccess` (returns bool in 4.4+) |
| **InputContext** | `_active_context: InputContextType` enum (WORLD_ACTIVE / UI_ACTIVE / PAUSED) | signals: `context_changed(new_ctx: InputContextType)`; methods: `push_context()`, `pop_context()`, `get_current() -> InputContextType` | Nothing | `InputMap`, `Input`, `_unhandled_input()` |

### Core Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **GridMap** | `_terrain: Array[Array[TerrainCell]]`, `_resources: Array[Array[ResourceCell]]`, `_buildings: Array[Array[BuildingCell]]` (all 30×30) | `validate_placement(pos, type) -> bool`, `place_building(pos, type)`, `get_cell(pos) -> GridCell`, `world_to_tile(world_pos) -> Vector2i`, `tile_to_world(tile_pos) -> Vector2`, `manhattan_dist(a,b)`, `euclidean_dist(a,b)` | `ResourceRegistry` (resource cell data), `TickSystem.tick_advanced` (resource respawn) | `TileMapLayer` (⚠️ HIGH: not TileMap), `FastNoiseLite` for Perlin gen |
| **PlayerCharacter** | `energy: float`, `carried_item: ItemStack?`, `mode: PlayerMode` (EXPLORER / ARCHITECT) | signals: `energy_changed(new_val)`, `mode_changed(new_mode)`, `action_performed(action_type)`; methods: `perform_action(type, target_pos) -> bool`, `refill_energy(food_item)`, `pick_up(item)`, `deposit(storage)` | `TickSystem.tick_advanced` (energy drain), `InputContext` (action gating), `GridMap` (action target validation), `InventorySystem` (deposit target) | `Node2D` (abstract — no physics body needed), input via `_unhandled_input` |
| **CameraController** | `_camera: Camera2D`, zoom state, pan velocity | `get_tile_at_screen(screen_pos: Vector2) -> Vector2i`, `fit_to_world()` | `InputContext` (pan/zoom gating), `GridMap.world_to_tile()` | `Camera2D`, `get_viewport()` |
| **InventorySystem** | All `InventoryContainer` instances, item `ResourceState` (DROPPED / IN_TRANSIT / STORED / LOST) | `find_best_storage(item_id) -> StorageContainer?`, `add_item(container, item) -> bool`, `remove_item(container, item_id, qty) -> bool`, `get_total_stored(item_id) -> int`, `get_days_of_food_remaining(npc_count) -> float` | `ResourceRegistry` (item definitions), `TickSystem.tick_advanced` (IN_TRANSIT aging) | None — pure GDScript data |

### Feature Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **BuildingSystem** | `_buildings: Dictionary[Vector2i, Building]`, build queues | signals: `building_placed(pos, type)`, `building_completed(pos)`, `building_demolished(pos)`; methods: `place(pos, type) -> bool`, `demolish(pos)`, `get_building(pos) -> Building?` | `GridMap.validate_placement()` + `place_building()`, `InventorySystem` (cost deduction), `TickSystem.tick_advanced` (build time + production cycle) | None — pure GDScript |
| **NpcSystem** | `_npcs: Dictionary[int, NpcData]`, assignment state per NPC | signals: `npc_assigned(npc_id, building_pos)`, `npc_state_changed(npc_id, state)`, `npc_hungry(npc_id)`; methods: `assign(npc_id, building_pos)`, `get_all_npcs() -> Array[NpcData]`, `get_npc(id) -> NpcData?` | `TickSystem.tick_advanced` (state machine steps), `BuildingSystem` (assignment targets + demolition events), `InventorySystem` (deposit actions), `HungerSystem` (hunger state read) | None — abstract movement via Manhattan math |
| **HungerSystem** | `_hunger_state: Dictionary[int, HungerData]` keyed by npc_id | signals: `npc_hunger_changed(npc_id, is_hungry)`, `food_consumed(item_id, qty)`; methods: `get_tick_cost_multiplier(npc_id) -> float`, `get_days_remaining() -> float` | `TickSystem.day_ended` (trigger daily consumption), `InventorySystem.remove_item()` (lowest-qty bin), `NpcSystem` (npc list) | None — pure GDScript |

### Presentation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **HudSystem** | UI scene tree (Control nodes), notification queue | None outward — display only | `TickSystem` (day, speed display), `PlayerCharacter.energy_changed`, `InventorySystem.get_total_stored()`, `HungerSystem.get_days_remaining()`, `BuildingSystem.building_completed`, `NpcSystem.npc_hungry` | `Control`, `Label`, `Button`, `ProgressBar`; ⚠️ HIGH: dual-focus (4.6) — keyboard `grab_focus()` separate from mouse hover |

### Ownership Invariants

1. **GridMap owns all world state** — no other module writes to the 3 layer arrays directly; all writes go through GridMap's API.
2. **InventorySystem owns all item state** — including `ResourceState` transitions. No other module mutates item state directly.
3. **TickSystem drives everything** — it emits; systems subscribe. No system polls the tick count.
4. **HudSystem is read-only** — it consumes signals and read methods. It owns no game state.
5. **NpcSystem owns NPC identity and state machine** — HungerSystem reads the NPC list but does not mutate NPC records.

---

## Data Flow

### Scenario 1: Frame Update Path

```
_process(delta)
│
├─► TickSystem._process(delta)
│     accumulator += delta * speed_multiplier
│     while accumulator >= TICK_DURATION:
│         accumulator -= TICK_DURATION
│         emit tick_advanced(current_tick)    ──────────────────────────────┐
│         if current_tick % 1000 == 0:                                       │
│             emit day_ended(current_day)  ──────────────────────┐           │
│                                                                │           │
├─► CameraController._process(delta)        │           tick_advanced subscribers:
│     read InputContext (WORLD_ACTIVE?)      │           ├── GridMap (resource respawn)
│     apply pan velocity from WASD/edge     │           ├── PlayerCharacter (energy drain)
│     clamp to world bounds                 │           ├── InventorySystem (IN_TRANSIT aging)
│     Camera2D.position = clamped_pos       │           ├── BuildingSystem (build time + prod)
│                                           │           └── NpcSystem (state machine step)
│                                           │
│                              day_ended subscribers:
│                              ├── HungerSystem (consume 1 food/NPC)
│                              └── HudSystem (refresh day display)
│
└─► HudSystem._process(delta)  [display polling only]
      read InventorySystem.get_total_stored() per tracked resource
      update resource count labels
```

**Communication types:**
- `TickSystem → subscribers`: signal (async, decoupled)
- `CameraController → Camera2D`: direct property set (same node)
- `HudSystem → InventorySystem`: synchronous method call (read-only polling, display only)

---

### Scenario 2: Player Action Path

```
Player clicks tile
│
├─► InputContext.get_current() → WORLD_ACTIVE? (gate)
│     if UI_ACTIVE or PAUSED → swallow input, no action
│
├─► CameraController.get_tile_at_screen(click_pos) → tile: Vector2i
│
├─► GridMap.get_cell(tile) → GridCell
│     check ResourceLayer for forageable resource
│
├─► PlayerCharacter.perform_action(FORAGE, tile)
│     compute energy_cost = base_cost * tick_cost_multiplier
│     if energy < energy_cost → emit action_failed, return
│     energy -= energy_cost
│     emit energy_changed(energy)             ──► HudSystem (energy bar update)
│     TickSystem.advance_ticks(energy_cost)   ──► all tick subscribers fire
│
├─► GridMap.remove_resource(tile)
│     resource drops to DROPPED state
│     InventorySystem.register_drop(item_id, tile_pos)
│
└─► [Player drag-and-drop to storage]
      PlayerCharacter.pick_up(item)
        carried_item = item
        InventorySystem.set_state(item, IN_TRANSIT)
      PlayerCharacter.deposit(storage_container)
        InventorySystem.add_item(storage_container, carried_item) → bool
        InventorySystem.set_state(item, STORED)
        carried_item = null
```

**Communication types:**
- `InputContext`: synchronous read (gate check)
- `PlayerCharacter → TickSystem`: synchronous call (`advance_ticks`)
- `PlayerCharacter → GridMap`: synchronous call (validation + mutation)
- `PlayerCharacter → InventorySystem`: synchronous call (state transition)
- `PlayerCharacter → HudSystem`: signal (`energy_changed`)

---

### Scenario 3: NPC Tick Step

```
TickSystem emits tick_advanced(tick)
│
└─► NpcSystem._on_tick(tick)
      for each npc in _npcs:
          multiplier = HungerSystem.get_tick_cost_multiplier(npc.id)
          npc.tick_accumulator += 1.0 / multiplier
          if npc.tick_accumulator >= npc.ticks_per_step:
              npc.tick_accumulator = 0
              _advance_state(npc)

_advance_state(npc):
  match npc.state:
    IDLE → (no assignment) stay IDLE
    TRAVEL_TO_BUILDING →
        remaining = GridMap.manhattan_dist(npc.pos, npc.target_building)
        if remaining == 0: npc.state = WORK
    WORK →
        npc.work_ticks_remaining -= 1
        if npc.work_ticks_remaining == 0:
            BuildingSystem.complete_production_cycle(npc.assignment)
            → InventorySystem.add_item(building_output_storage, produced_item)
            npc.state = TRAVEL_TO_STORAGE
    TRAVEL_TO_STORAGE →
        remaining = GridMap.manhattan_dist(npc.pos, npc.target_storage)
        if remaining == 0: npc.state = DEPOSIT
    DEPOSIT →
        InventorySystem.add_item(target_storage, npc.carried_output)
        npc.state = RETURN_TO_BASE
    RETURN_TO_BASE →
        remaining = GridMap.manhattan_dist(npc.pos, BASE_POS)
        if remaining == 0: npc.state = TRAVEL_TO_BUILDING
```

**Communication types:**
- `NpcSystem → HungerSystem`: synchronous read (`get_tick_cost_multiplier`)
- `NpcSystem → GridMap`: synchronous read (manhattan distance, no mutation)
- `NpcSystem → BuildingSystem`: synchronous call (complete production cycle)
- `BuildingSystem → InventorySystem`: synchronous call (deposit output)

---

### Scenario 4: Save/Load Path

```
SAVE:
WorldSaveManager.save_game(slot)
│
├─► TickSystem.serialize() → { tick, day, speed, paused }
├─► GridMap.serialize() → { terrain[][], resources[][], buildings[][] }
├─► InventorySystem.serialize() → { containers: [...], items: [...] }
├─► BuildingSystem.serialize() → { buildings: {...} }
├─► NpcSystem.serialize() → { npcs: {...} }
├─► HungerSystem.serialize() → { hunger_state: {...} }
├─► PlayerCharacter.serialize() → { energy, mode, carried_item }
└─► FileAccess.open(path, WRITE)
    FileAccess.store_string(JSON.stringify(data))
    [store_* returns bool in Godot 4.4+ — check return value]

LOAD:
WorldSaveManager.load_game(slot)
│
├─► FileAccess.open(path, READ) → JSON string
├─► JSON.parse(string) → Dictionary
├─► ResourceRegistry (must be loaded first — no save/load needed, always from disk)
├─► GridMap.deserialize(data.grid)
├─► InventorySystem.deserialize(data.inventory)
├─► BuildingSystem.deserialize(data.buildings)
├─► NpcSystem.deserialize(data.npcs)
├─► HungerSystem.deserialize(data.hunger)
├─► PlayerCharacter.deserialize(data.player)
└─► TickSystem.deserialize(data.tick)  ← last: resumes tick emission
```

**Format:** JSON (human-readable).
**Serialization ownership:** Each module serializes its own data; `WorldSaveManager` orchestrates order only.
**Load order invariant:** `ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick`

---

## API Boundaries

### TickSystem

```gdscript
class_name TickSystem extends Node

signal ticks_advanced(delta_ticks: int)
signal day_transition(days_elapsed: int)
signal speed_changed(new_speed: float)
signal pause_state_changed(is_paused: bool)

const TICKS_PER_DAY: int = 1000
const TICKS_PER_SECOND_BASE: float = 10.0
const MAX_TICKS_PER_FRAME: int = 100
const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

var tick_remainder: float = 0.0
var tick_count: int = 0
var current_day: int = 1
var speed_multiplier: float = 1.0
var is_paused: bool = true

func set_speed(multiplier: float) -> void   # clamps to nearest SPEED_OPTIONS value
func set_pause(paused: bool) -> void        # toggles pause; calls set_process() accordingly
func advance_ticks_manual(cost: int) -> void# called by PlayerCharacter/ManualLabor; cost >= 1

# Caller invariants: set_speed() passes SPEED_OPTIONS values (clamped internally);
#                   advance_ticks_manual() called with positive integer costs only
# Guarantees: ticks_advanced fires synchronously with accumulated delta each frame;
#             day_transition fires when tick_count >= TICKS_PER_DAY (max 1 per frame);
#             set_process(false) when paused — zero CPU cost during pause
# Serialization: { tick_count, current_day, speed_multiplier, is_paused, tick_remainder }
```

### ResourceRegistry

```gdscript
class_name ResourceRegistry extends Node

func load_from_file(path: String) -> bool                                 # false = halt
func get_definition(id: StringName) -> ResourceDefinition                 # null if not found
func is_valid_id(id: StringName) -> bool
func get_all_by_category(category: ResourceCategory) -> Array[ResourceDefinition]

# Caller invariants: load_from_file() must succeed before any get_definition() calls;
#                   treat returned ResourceDefinition as immutable
# Guarantees: get_definition() is O(1); returns null (not crash) for unknown ids
```

### InputContext

```gdscript
class_name InputContext extends Node

enum ContextType { WORLD_ACTIVE, UI_ACTIVE, PAUSED }

signal context_changed(new_context: ContextType)

func get_current() -> ContextType
func push_context(ctx: ContextType) -> void   # stacks; UI_ACTIVE over WORLD_ACTIVE
func pop_context() -> void                    # restores previous

# Caller invariants: every push_context() must have a matching pop_context()
# Guarantees: get_current() always returns a valid ContextType;
#             context_changed fires on every push/pop that changes the active context
```

### GridMap

```gdscript
class_name GridMap extends Node

const GRID_WIDTH: int = 30
const GRID_HEIGHT: int = 30
const TILE_SIZE: int = 48   # pixels

func validate_placement(tile: Vector2i, building_type: BuildingType) -> bool
func place_building(tile: Vector2i, building_type: BuildingType) -> void  # call after validate
func remove_building(tile: Vector2i) -> void
func remove_resource(tile: Vector2i) -> void
func get_cell(tile: Vector2i) -> GridCell     # read-only snapshot
func is_in_bounds(tile: Vector2i) -> bool
func world_to_tile(world_pos: Vector2) -> Vector2i
func tile_to_world(tile: Vector2i) -> Vector2  # returns tile centre
func manhattan_dist(a: Vector2i, b: Vector2i) -> int
func euclidean_dist(a: Vector2i, b: Vector2i) -> float

# Caller invariants: always call validate_placement() before place_building();
#                   all tile args must pass is_in_bounds()
# Guarantees: validate_placement() never mutates state;
#             get_cell() returns a copy — mutating it has no effect on grid state
# ⚠️  Uses TileMapLayer internally (not TileMap) — Godot 4.3+ required
```

### InventorySystem

```gdscript
class_name InventorySystem extends Node

enum ResourceState { DROPPED, IN_TRANSIT, STORED, LOST }

func register_drop(item_id: StringName, tile: Vector2i) -> ItemHandle
func set_state(handle: ItemHandle, state: ResourceState) -> void
func find_best_storage(item_id: StringName) -> StorageContainer   # null if none available
func get_total_stored(item_id: StringName) -> int
func get_days_of_food_remaining(npc_count: int) -> float
func add_item(container: StorageContainer, item_id: StringName, qty: int) -> bool
func remove_item(container: StorageContainer, item_id: StringName, qty: int) -> bool

# Caller invariants: remove_item() only on STORED items;
#                   add_item() returns false if no slot — caller handles rejection
# Guarantees: find_best_storage() returns lowest-quantity bin (hunger priority rule);
#             IN_TRANSIT/DROPPED items never included in get_total_stored()
```

### PlayerCharacter

```gdscript
class_name PlayerCharacter extends Node2D

enum PlayerMode { EXPLORER, ARCHITECT }
enum ActionType { FORAGE, PICK, CRAFT, CHOP, MINE, TRANSPORT }

signal energy_changed(new_energy: float)
signal mode_changed(new_mode: PlayerMode)
signal action_failed(reason: StringName)

var energy: float         # [0.0, 100.0]
var mode: PlayerMode
var carried_item: ItemHandle   # null if not carrying

func perform_action(action: ActionType, target_tile: Vector2i) -> bool
func pick_up(handle: ItemHandle) -> void
func deposit(container: StorageContainer) -> void
func refill_energy(food_item_id: StringName) -> void

# Caller invariants: do not call perform_action() when InputContext != WORLD_ACTIVE;
#                   deposit() only valid when carried_item != null
# Guarantees: perform_action() returns false (not crash) if energy < cost;
#             ARCHITECT mode is one-way after first NPC assigned;
#             energy clamped to [0.0, 100.0]
```

### BuildingSystem

```gdscript
class_name BuildingSystem extends Node

signal building_placed(tile: Vector2i, building_type: BuildingType)
signal building_completed(tile: Vector2i)
signal building_demolished(tile: Vector2i)

func place(tile: Vector2i, building_type: BuildingType) -> bool
func demolish(tile: Vector2i) -> void
func get_building(tile: Vector2i) -> Building    # null if none
func get_npc_slots(tile: Vector2i) -> int        # 0 if no building
func complete_production_cycle(tile: Vector2i) -> void   # NpcSystem only

# Caller invariants: complete_production_cycle() called only by NpcSystem
# Guarantees: place() internally validates via GridMap — callers need not pre-check;
#             building_demolished fires before GridMap cell is cleared;
#             build cost deducted from InventorySystem atomically inside place()
```

### NpcSystem

```gdscript
class_name NpcSystem extends Node

signal npc_assigned(npc_id: int, building_tile: Vector2i)
signal npc_state_changed(npc_id: int, new_state: NpcState)
signal npc_hungry(npc_id: int)

func assign(npc_id: int, building_tile: Vector2i) -> bool   # false = slots full
func unassign(npc_id: int) -> void
func get_all_npcs() -> Array[NpcData]
func get_npc(npc_id: int) -> NpcData   # null if not found

# Caller invariants: assign() only to buildings with available slots
# Guarantees: building_demolished automatically triggers unassign() for all NPCs at tile;
#             npc_hungry emitted once per day (not every tick)
```

### HungerSystem

```gdscript
class_name HungerSystem extends Node

signal npc_hunger_changed(npc_id: int, is_hungry: bool)
signal food_consumed(item_id: StringName, qty: int)

func get_tick_cost_multiplier(npc_id: int) -> float  # 1.0 / 2.0 / 4.0
func get_days_remaining() -> float

# Caller invariants: get_tick_cost_multiplier() is read-only
# Guarantees: npc_hunger_changed fires only on state flip (not every tick);
#             food_consumed fires after InventorySystem.remove_item() succeeds;
#             combined multiplier capped at 4.0×
```

### HudSystem

```gdscript
class_name HudSystem extends CanvasLayer

# No public API — display only. Wires signals in _ready():
#   TickSystem.tick_advanced, day_ended, speed_changed
#   PlayerCharacter.energy_changed
#   BuildingSystem.building_completed
#   NpcSystem.npc_hungry
# Polls in _process():
#   InventorySystem.get_total_stored(id) per tracked resource
#   HungerSystem.get_days_remaining()

# Invariants: MUST NOT call any mutating method on any system
# ⚠️  Godot 4.6: keyboard grab_focus() and mouse hover are separate — test both paths
```

### WorldSaveManager (Foundation — orchestrator only)

```gdscript
class_name WorldSaveManager extends Node

func save_game(slot: int) -> bool
func load_game(slot: int) -> bool

# Load order invariant (must be respected exactly):
#   ResourceRegistry → GridMap → InventorySystem → BuildingSystem →
#   NpcSystem → HungerSystem → PlayerCharacter → TickSystem
# Guarantees: no game logic lives here — orchestration only
```

---

## ADR Audit

**Current ADR count:** 0 (no ADRs have been written yet)

All decisions made during this architecture session are currently undocumented in ADR form. The traceability table below shows the full gap.

### Traceability Coverage

| Req ID | Requirement | ADR | Status |
|--------|-------------|-----|--------|
| TR-tick-001…006 | Tick system (accumulator, speeds, determinism, day transition) | — | ❌ GAP |
| TR-res-001…005 | Resource registry (JSON, schema validation, O(1) lookup, categories) | — | ❌ GAP |
| TR-input-001…005 | Input context system and action mapping | — | ❌ GAP |
| TR-player-001…006 | Player energy, manual actions, Architect Mode | — | ❌ GAP |
| TR-grid-001…006 | Grid data model, TileMapLayer, Perlin, coordinate conversion | — | ❌ GAP |
| TR-inv-001…006 | Inventory containers, ResourceState machine, storage priority | — | ❌ GAP |
| TR-build-001…005 | Building placement, costs, build time, production cycles | — | ❌ GAP |
| TR-cam-001…005 | Camera pan/zoom/clamp/screen-to-tile | — | ❌ GAP |
| TR-npc-001…006 | NPC state machine, Manhattan movement, recruitment, demolition | — | ❌ GAP |
| TR-hunger-001…004 | Hunger consumption, debuff stacking, food conversion | — | ❌ GAP |
| TR-hud-001…005 | HUD display, notifications, time controls, dual-focus | — | ❌ GAP |

**Coverage: 0 / 56 requirements.** All decisions need ADRs before coding begins.

---

## Required ADRs

### Must have before any coding starts (Foundation + Core)

| # | ADR Title | Covers | Key Decision |
|---|-----------|--------|--------------|
| 1 | Tick system design and time management strategy | TR-tick-001…006 | 1000 ticks/day, float accumulator, speed multipliers, determinism, manual advance |
| 2 | Resource data registry format and loading | TR-res-001…005 | JSON format, schema validation, O(1) lookup, two-category model |
| 3 | Input context system and action mapping | TR-input-001…005 | Context enum, push/pop stack, keyboard+gamepad mapping, dual-focus (Godot 4.6) |
| 4 | Grid map data model and TileMapLayer rendering | TR-grid-001…006 | 30×30 3-layer array, TileMapLayer (not TileMap), Perlin gen, coordinate conversion |
| 5 | Inventory and item state machine | TR-inv-001…006 | DROPPED→IN_TRANSIT→STORED→LOST, first-fit stacking, storage bin priority |
| 6 | Save and load format and module serialisation order | All serialize TRs | JSON format, WorldSaveManager orchestrator, load order invariant |

### Should have before the relevant system is built (Feature)

| # | ADR Title | Covers | Key Decision |
|---|-----------|--------|--------------|
| 7 | Player character energy model and action system | TR-player-001…006 | Energy pool, tick-based drain, depletion multipliers, Architect Mode lock |
| 8 | Building placement, costs, and production cycles | TR-build-001…005 | 1-tile footprint, atomic cost deduction, tick-based build and production |
| 9 | NPC state machine and abstract movement model | TR-npc-001…006 | Manhattan movement (no NavigationAgent2D for VS), tick accumulator, cycle pattern |
| 10 | Hunger and debuff stacking model | TR-hunger-001…004 | 1 food/NPC/day, 2× debuff, 4× combined cap, lowest-qty bin priority |

### Can defer to implementation

| ADR Title | Rationale |
|-----------|-----------|
| Camera pan/zoom implementation details | Camera2D API stable, behaviour fully specified in GDD |
| HUD layout and dual-focus wiring | Visual; engine-risk covered by input context ADR |
| Rendering backend selection (Forward+ vs Mobile) | Needs performance profiling first; no gameplay impact |

---

## Architecture Principles

**1. Tick is the universal clock — nothing runs outside it.**
Every system that advances game state subscribes to `TickSystem.tick_advanced`. No system tracks its own wall-clock time or uses `_process()` for game logic. This guarantees determinism and makes save/load trivial.

**2. GridMap is the single source of truth for world state.**
All three layers (Terrain, Resource, Building) are owned exclusively by GridMap. Other systems may read via GridMap's API but never write directly to the layer arrays. This keeps placement validation centralised and prevents conflicting state.

**3. Data flows down; signals flow up.**
Foundation layer modules (Tick, ResourceRegistry, InputContext) never reference Feature or Presentation layer modules. Communication upward goes through signals only. No Presentation module mutates game state — it reads and displays.

**4. Systems own their state and serialise themselves.**
No external serialiser walks another system's internals. Each module exposes `serialize() -> Dictionary` and `deserialize(data: Dictionary) -> void`. WorldSaveManager is an orchestrator, not an inspector.

**5. Engine APIs are verified, not assumed.**
Any Godot API used in code must be cross-referenced against `docs/engine-reference/godot/` before use. The LLM's training data covers ~4.3; this project targets 4.6. TileMapLayer, dual-focus, FileAccess bool returns, and the dedicated 2D navigation server are all post-cutoff — treat all engine calls as unverified until confirmed against the reference docs.

---

## Open Questions

The following must be resolved before the corresponding systems are built:

1. **Autoload vs scene-instanced singletons for Foundation systems.** Should TickSystem, ResourceRegistry, and InputContext be Godot Autoloads (project-level singletons) or instanced nodes in a dedicated `World.tscn` root? Autoloads are globally accessible but harder to unit-test; scene-instanced nodes require dependency injection. *Must resolve before Foundation ADRs are written.*

2. **Player visual representation.** The GDD says the player is abstract during the Vertical Slice — is there a sprite, or is the player represented solely by a cursor/selection highlight? This determines what `PlayerCharacter` extends (Node2D with sprite? AnimatedSprite2D? Pure Node?). *Must resolve before player character implementation.*

3. **NPC visual representation.** GDD says NPCs have no sprites for the VS. Are they a coloured rectangle, a label, or nothing visible (implied by HUD only)? This determines whether NpcSystem needs any scene nodes or is purely data. *Must resolve before NPC implementation.*

4. **Perlin noise seed strategy.** Does procedural generation use a fixed seed per save slot, a random seed on new game, or a user-entered seed? The determinism guarantee (TR-tick-006) implies save files must store the seed. *Must resolve before GridMap ADR is written.*

5. **Storage Area vs Storage Building class model.** The GDD defines Storage Area (50 slots, free) and Storage Building (150 slots, costs 8W+2S) as distinct entities. Are these two `StorageContainer` subclasses or one configurable class? The choice affects how `find_best_storage()` priority logic works. *Must resolve before Inventory ADR is written.*
