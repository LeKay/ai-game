# Control Manifest

> **Engine**: Godot 4.6
> **Last Updated**: 2026-05-14
> **Manifest Version**: 2026-05-14
> **ADRs Covered**: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005, ADR-0006, ADR-0007, ADR-0008, ADR-0009, ADR-0010
> **Status**: Active — regenerate with `/create-control-manifest update` when ADRs change

`Manifest Version` is the date this manifest was generated. Story files embed
this date when created. `/story-readiness` compares a story's embedded version
to this field to detect stories written against stale rules. Always matches
`Last Updated` — they are the same date, serving different consumers.

This manifest is a programmer's quick-reference extracted from all Accepted ADRs,
technical preferences, and engine reference docs. For the reasoning behind each
rule, see the referenced ADR.

---

## Foundation Layer Rules

*Applies to: scene management, event architecture, save/load, engine initialisation*

### Required Patterns
- **Autoload singleton for all Foundation systems** — TickSystem, ResourceRegistry, InputContext, InventorySystem, WorldSaveManager, HungerSystem, PlayerCharacter, BuildingRegistry, NPCSystem all use `extends Node` + project settings Autoload registration — source: ADR-0001, ADR-0002, ADR-0003, ADR-0005, ADR-0006, ADR-0007, ADR-0008, ADR-0009, ADR-0010
- **Push/pop context stack for input gating** — `push_context()` / `pop_context()` with `Context.WORLD_ACTIVE` as default (depth 0). Stack max depth should not exceed 3 — source: ADR-0003
- **StringName action constants** — declare all input action names as `static var` StringName in `constants/input_actions.gd`, never use string literals — source: ADR-0003
- **ResourceRegistry loads at startup before any system** — `load_from_file()` must succeed before any `get_definition()` call. O(1) `Dictionary[StringName, _ResourceDefinition]` cache — source: ADR-0002
- **JSON save format with schema versioning** — `schema_version` at top level, namespaced system data (`"tick"`, `"world"`, `"player"`), `WorldSaveManager` orchestrates collect/merge/write — source: ADR-0006
- **Load order invariant**: ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick — source: ADR-0006
- **Null-check Autoload references** — use `Engine.get_singleton("Name")` in `_enter_tree()`, check for null, log warning and defer if dependency not loaded — source: ADR-0007, ADR-0008, ADR-0009, ADR-0010
- **Fail-fast schema validation on JSON load** — reject invalid data with clear error message, do not silently skip — source: ADR-0002

### Forbidden Approaches
- **Never use scene-instanced Autoloads** — Foundation systems must not be child nodes of any scene — source: ADR-0002, ADR-0003, ADR-0006
- **Never use custom input mapping files** — use Godot's native InputMap with StringName constants — source: ADR-0003
- **Never use hardcoded resource definitions** — all resource metadata must come from ResourceRegistry — source: ADR-0002, ADR-0005
- **Never call TileMapLayer.get_cell()** — gameplay code reads from Grid data only — source: ADR-0004

### Performance Guardrails
- **ResourceRegistry load_from_file()**: max 2ms for 30 resources — source: ADR-0002
- **InputContext**: < 0.001ms per unhandled input event — source: ADR-0003
- **TickSystem._process()**: 0.1ms — source: ADR-0001

---

## Core Layer Rules

*Applies to: core gameplay loops, main player systems, physics, collision*

### Required Patterns
- **Tick-based timing for all action durations** — action progress, travel timers, production cycles advance via `ticks_advanced()` signal, never `_process()` delta — source: ADR-0001, ADR-0007, ADR-0008, ADR-0009
- **Single-loop tick subscription** — subscribe to `ticks_advanced()` once, iterate all entities in a single loop (no per-entity `_process()`) — source: ADR-0008, ADR-0009
- **Autoload dependency injection via `_enter_tree()`** — cache `Engine.get_singleton()` references, null-check each — source: ADR-0007, ADR-0008, ADR-0009, ADR-0010
- **Energy pool clamped to [0, max]** — `try_spend()` for normal check, `spend_unchecked()` for 0-energy actions — source: ADR-0007
- **One-way Architect Mode transition** — once `locked = true`, never returns to false. Triggers on first NPC assignment — source: ADR-0007
- **First-fit stacking algorithm** — phase 1: extend existing matching slots, phase 2: fill empty slots, phase 3: FAILURE if no room — source: ADR-0005
- **Deterministic container modification order** each tick: 1) Hunger consumption, 2) Building withdrawals (container_id ascending), 3) Carrier transport deposits (carrier NPC `try_deposit()` calls — production output always full base_output, no distance reduction), 4) Day-transition events — source: ADR-0005
- **7-state NPC task cycle** — IDLE, TRAVEL_TO_BUILDING, WORK_AT_BUILDING, TRAVEL_TO_STORAGE, DEPOSIT, RETURN_TO_BASE, WAITING — source: ADR-0009
- **Manhattan distance for NPC travel** — `ticks_per_tile = 3.0`, no pathfinding at VS scope — source: ADR-0009
- **Binary hunger state** — FED or HUNGRY, no partial starvation. `hunger_tick_multiplier` = 1.0 (FED) or 2.0 (HUNGRY) — source: ADR-0010
- **Multiplicative debuff stacking** — `effective = base × depletion_multiplier × hunger_multiplier`, max 4x — source: ADR-0010
- **Day transition guard** — consume food only when `tick_count % 1000 == 0` — source: ADR-0010
- **Delegation discipline** — HungerSystem never implements food deduction, delegates to InventorySystem.consume_food() — source: ADR-0010
- **Inventory state machine** — DROPPED → IN_TRANSIT → STORED/LOST, items only consumed from STORED — source: ADR-0005
- **Typed snapshot classes for serialization** — `_ContainerSnapshot`, `_SlotSnapshot`, `_TransitSnapshot` with `schema_version` — source: ADR-0005

### Forbidden Approaches
- **Never use OS-level clock** — only use engine delta for tick accumulation — source: ADR-0001
- **Never apply speed_multiplier to manual action costs** — manual costs are always base value — source: ADR-0001
- **Never carry overflow ticks past 1000** — each day is a clean boundary, discard overflow — source: ADR-0001
- **Never implement per-scene _process() for building timers** — single-loop subscription only — source: ADR-0008
- **Never use personal carry-inventory** — carried items exist only in IN_TRANSIT state — source: ADR-0005

### Performance Guardrails
- **PlayerCharacter._process()**: 0.5ms during active action, < 0.1ms idle — source: ADR-0007
- **BuildingRegistry single-loop**: 1.0ms for 50 buildings — source: ADR-0008
- **HungerSystem day transition**: 0.002ms per day — source: ADR-0010
- **InventorySystem._process()**: 0.05ms — source: ADR-0005
- **NPCSystem ticks_advanced handler**: 0.05ms for 8 NPCs — source: ADR-0009

---

## Feature Layer Rules

*Applies to: secondary mechanics, AI systems, NPC management*

### Required Patterns
- **4-stage building lifecycle** — PLACE → CONSTRUCT → OPERATE → DEMOLISH — source: ADR-0008
- **Single gate placement validation** — all systems call `GridMap.validate_placement()`, never implement own logic — source: ADR-0004, ADR-0008
- **PackedScene visual rendering** — buildings are PackedScene instances at tile centers, not TileMapLayer tiles — source: ADR-0008
- **Visual pool pattern** — recycled scene templates, registry owns all state, scene instances are pure visuals — source: ADR-0008
- **NPC disconnection on demolition** — building/ storage/house demolition triggers `release_npc()`, NPC returns home — source: ADR-0009
- **WAITING state for full storage** — NPC waits, resumes on `storage_changed` signal — source: ADR-0009
- **Production carrier transport** — output is never deposited directly by the Building System. `production_output_ready` is emitted and output held in building buffer; carrier NPC (TransportationSystem) calls `collect_output()` to pick up and `InventorySystem.try_deposit()` at storage. Input carrier calls `deliver_input()` to stock building input buffer — source: ADR-0008, GDD building-system.md
- **Carrier travel time formula** — carrier round-trip time: `carrier_travel_ticks = floor(distance × ticks_per_tile)`. Distance does NOT modify production output or cycle duration — source: ADR-0008

### Forbidden Approaches
- **Never use TileMap for rendering** — always TileMapLayer, one node per visual layer — source: ADR-0004
- **Never use FastNoiseLite for terrain generation** — use FastNoise with `TYPE_PERLIN` — source: ADR-0004

### Performance Guardrails
- **Grid query (get_tile_view)**: < 0.002ms — source: ADR-0004
- **Grid query (get_tiles_in_radius, 30x30)**: < 0.01ms — source: ADR-0004
- **Map generation (Perlin, 900 tiles)**: 5–20ms one-time — source: ADR-0004

---

## Presentation Layer Rules

*Applies to: rendering, audio, UI, VFX, shaders, animations*

### Required Patterns
- **Depth ordering via Node2D.y_sort_enabled** — not legacy YSort node (deprecated since 4.0) — source: ADR-0004
- **TileMapLayer per visual layer** — one node per layer (TerrainLayer, ResourceOverlay, BuildingSlots), each with `TileSet.tile_size = Vector2i(48, 48)` — source: ADR-0004
- **Data-visual separation** — TileMapLayer cells are derived from Grid data via batch `set_cell()` calls, gameplay code never reads TileMapLayer directly — source: ADR-0004
- **Y-sort for all game objects** — buildings, characters, items must be children of Node2D with `y_sort_enabled = true` — source: ADR-0004

### Forbidden Approaches
- **Never use YSort node** — use `Node2D.y_sort_enabled` property instead — source: ADR-0004, deprecated-apis.md

### Performance Guardrails
- N/A — no per-frame presentation budgets defined at this stage

---

## Global Rules (All Layers)

### Naming Conventions
| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `PlayerController`, `BuildingRegistry` |
| Variables/functions | snake_case | `move_speed`, `advance_ticks()` |
| Signals | snake_case past tense | `health_changed`, `day_transition` |
| Files | snake_case matching class | `player_controller.gd` |
| Constants | UPPER_SNAKE_CASE | `MAX_HEALTH`, `TICKS_PER_DAY` |

### Performance Budgets
| Target | Value |
|--------|-------|
| Framerate | 60 fps |
| Frame budget | 16.6ms |
| Draw calls | < 1000 for main gameplay view |
| Memory ceiling | 512 MB soft, 1 GB hard |

### Approved Libraries / Addons
- None configured — no addons approved yet

### Deprecated APIs (Godot 4.6)
These APIs are deprecated or unverified for Godot 4.6. Use the replacement instead:

- **`TileMap`** — replaced by `TileMapLayer` (since 4.3) — source: deprecated-apis.md
- **`YSort` node** — replaced by `Node2D.y_sort_enabled` property (since 4.0) — source: deprecated-apis.md
- **`VisibilityNotifier2D`** — replaced by `VisibleOnScreenNotifier2D` (since 4.0) — source: deprecated-apis.md
- **`yield()`** — replaced by `await signal` (GDScript 2.0) (since 4.0) — source: deprecated-apis.md
- **`PackedScene.instance()`** — replaced by `PackedScene.instantiate()` (since 4.0) — source: deprecated-apis.md
- **`connect("signal", obj, "method")`** — replaced by `signal.connect(callable)` (since 4.0) — source: deprecated-apis.md
- **`OS.get_ticks_msec()`** — replaced by `Time.get_ticks_msec()` (since 4.0) — source: deprecated-apis.md
- **`PerlinNoise`** — renamed to `FastNoise` (since 4.5, use `TYPE_PERLIN`) — source: ADR-0004
- **`FastNoiseLite`** — not used for terrain generation; use `FastNoise` with `TYPE_PERLIN` — source: ADR-0004

### Cross-Cutting Constraints
- **No circular dependencies** — Foundation systems have zero circular references. Feature systems may reference Foundation but never the reverse. Source: all ADRs
- **Serialized state must be a plain Dictionary** — no Node references, no callable objects, no circular_serialization — source: ADR-0006
- **deserialize() must use `.get()` with defaults** — never direct `[key]` access that raises on missing keys — source: ADR-0006
- **All Foundation systems use Autoload pattern** — consistency over testability for this project's scale (single-player, no scene reloading) — source: ADR-0001
