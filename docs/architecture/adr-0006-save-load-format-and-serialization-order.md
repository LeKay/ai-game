# ADR-0006: Save and Load Format and Serialization Order

## Status

Accepted

## Date

2026-05-13

## Last Verified

2026-05-13

## Decision Makers

Technical Director, Lead Programmer, Producer (save compatibility commitment)

## Summary

Defines the Save/Load architecture as a JSON file format with schema versioning, orchestrated by a `WorldSaveManager` Autoload that enforces a deterministic load-order invariant. Each system implements `serialize() -> Dictionary` and `deserialize(Dictionary) -> void` with the orchestrator collecting and writing the merged data. Save slots use platform-specific user data paths. Cross-version compatibility is handled via `schema_version` fields — deserializers reject unknown future versions and gracefully handle missing fields in older versions. The file path follows Godot's `user://` directory with versioned subdirectories.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — FileAccess, JSON.parse(), JSON.stringify(), and user:// path are stable APIs covered pre-cutoff. FileAccess return type changed to bool in 4.4 but is compile-time caught. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/architecture/architecture.md` Scenario 4 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (TickSystem serialize/deserialize), ADR-0002 (ResourceRegistry loaded before any system — no save/load needed, always from JSON), ADR-0004 (GridMap serialize with grid_size), ADR-0005 (InventoryContainer + TransitItem serialize), ADR-0003 (InputContext state is ephemeral — no save/load needed, context resets on load) |
| **Enables** | All system stories that reference Save/Load as Hard dependency — player-character, building-system, npc-system, hunger-system |
| **Blocks** | Any story that implements a system's serialize()/deserialize() methods, any story using save slots or migration between versions |
| **Ordering Note** | Foundation-layer ADR — must be Accepted before any system's serialization implementation can begin. The load-order invariant defined here is consumed by every system's deserialization story. |

## Context

### Problem Statement

The architecture document defines a `WorldSaveManager` orchestrator and a load-order invariant (`ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick`) but no ADR governs the save file format, schema versioning strategy, or cross-version compatibility. Without this decision:

- Each system's programmer may choose different serialization formats (JSON dict vs. custom string encoding vs. `to_dict()` vs. `duplicate()`), producing incompatible save files that the orchestrator cannot merge
- No schema versioning strategy exists — when a new system is added (e.g., Logistics System in MVP), older saves lack its data fields, and deserializers may crash on missing keys
- No error handling policy for corrupted saves is defined — a single bad byte should not crash the game
- Save slot management (file naming, slot numbering, platform path) is undefined

### Constraints

- Must follow the JSON file format already defined in `architecture.md` Scenario 4 — not `.tres`/`ResourceSaver` (human-editable requirement)
- ResourceRegistry is NOT saved — it is always loaded from JSON at startup (ADR-0002). Only gameplay state is saved.
- Each system owns its own serialization — `WorldSaveManager` orchestrates order only, it does not serialize system data itself
- Serialization must be deterministic — slots serialized in index order, containers in container_id order — for save comparison and testing
- Must handle cross-version compatibility: older saves loading into newer game versions (missing fields) and newer saves rejected by older game versions (future schema)
- Godot 4.4+ `FileAccess` methods return `bool` for success/failure (compile-time enforced)
- Save files stored in `user://saves/` directory

### Requirements

- **Architecture**: `WorldSaveManager` orchestrator — collect `serialize()` dicts, merge, write JSON
- **Load order invariant**: `ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick`
- **Schema versioning**: Each serialized dictionary includes `schema_version`; deserializer rejects future versions
- **Deterministic serialization**: Index order for arrays, sorted keys for dictionaries
- **Error handling**: Corrupted save = show error dialog, return to title screen. Do not crash.
- **Save slots**: At least 3 concurrent save slots
- **No circular serialization**: A system's serialize() must not call another system's serialize() — all systems serialize to plain dictionaries

## Decision

### Architecture: WorldSaveManager Orchestrator with Schema Versioning

The `WorldSaveManager` is an Autoload singleton that:
1. Provides `save_game(slot: int)` and `load_game(slot: int)` methods
2. Collects serialized data from each system via a registered system list
3. Merges all dictionaries into a top-level save document with `schema_version`
4. Writes/reads JSON to/from `user://saves/save_<slot>.json`

```
┌─────────────────────────────────────────────┐
│           WorldSaveManager (Autoload)         │
│                                              │
│  _registered_systems: Array[String]           │
│  _save_path: String = "user://saves/"         │
│  _max_slots: int = 10                         │
│                                              │
│  func register_save_system(name: String)     │
│  func save_game(slot: int) -> bool            │
│  func load_game(slot: int) -> bool            │
│  func delete_save(slot: int) -> bool          │
│  func get_save_info(slot: int) -> Dictionary? │
│  func get_available_slots() -> Array[int]     │
│                                              │
│  _collect_serialize_data() -> Dictionary      │
│  _collect_deserialize_data() -> Dictionary    │
│  _write_file(path: String, data: Dictionary) -> bool │
│  _read_file(path: String) -> Dictionary?      │
│  _validate_schema_version(data: Dictionary) -> bool │
│                                              │
│  _on_save_system_serialize(name) -> Dictionary  ← called per system
│  _on_save_system_deserialize(name, data) -> void ← called per system
└──────────┬──────────────────┬────────────────┘
           │                   │
    ┌──────┴──────┐    ┌──────┴────────┐
    │ System A    │    │ System B      │
    │ serialize() │    │ deserialize() │
    │ -> Dict     │    │ -> void       │
    └─────────────┘    └───────────────┘
```

### Key Interfaces

```gdscript
## WorldSaveManager.gd — Autoload singleton
extends Node

const SCHEMA_VERSION: int = 1
const SAVE_PATH: String = "user://saves/"
const MAX_SLOTS: int = 10

# Registration (called by each system in its _ready())
func register_save_system(name: String) -> void
func get_available_slots() -> Array[int]
func get_save_info(slot: int) -> Dictionary?

# Public API
func save_game(slot: int) -> bool
func load_game(slot: int) -> bool
func delete_save(slot: int) -> bool

# Internal orchestration
func _collect_serialize_data() -> Dictionary
func _process_deserialize_order(data: Dictionary) -> void

# File I/O
func _write_file(path: String, data: Dictionary) -> bool
func _read_file(path: String) -> Dictionary?

# Schema validation
func _validate_schema_version(data: Dictionary) -> bool
```

### Schema Versioning Strategy

The save file has a single top-level `schema_version` that represents the **entire save format**. When a game update changes the save format (adds new system data, changes field names), the top-level `schema_version` is incremented.

**Loading rules:**
1. If save's `schema_version < current`: **MIGRATION** — iterate through migration steps (version N → N+1 → ... → current). Each migration step adds default values for missing fields.
2. If save's `schema_version == current`: **DIRECT LOAD** — each system deserializes its data directly.
3. If save's `schema_version > current`: **REJECT** — save created by a newer game version, not compatible. Show "Save file from newer game version" error.

**Migration strategy (current approach for VS):**
For the Vertical Slice, migrations are simple: each system's `deserialize()` must handle missing fields gracefully by using default values. No migration script is needed because all changes are additive (new systems, new fields). The deserializer checks for the presence of each expected key and uses a default if absent:

```gdscript
func deserialize(data: Dictionary) -> void:
    var saved_version = data.get("schema_version", 0)
    # Handle missing fields from older saves
    var grid_data = data.get("grid", {})
    var terrain = grid_data.get("terrain", [])
    if terrain.is_empty():
        terrain = _generate_default_terrain()  # fallback for v0 save
```

**Future migrations** (MVP+): When the schema changes significantly (e.g., field renaming, type changes), implement explicit migration functions in `WorldSaveManager._migrate_to_v2()`, `_migrate_to_v3()`, etc. These produce a fully-populated dictionary at the target schema version.

### Save File Format

```json
{
    "schema_version": 1,
    "timestamp": 1715600000,
    "game": {
        "tick": {
            "tick_count": 450,
            "current_day": 3,
            "speed_multiplier": 1.0,
            "is_paused": true,
            "tick_remainder": 0.0
        }
    },
    "world": {
        "grid": {
            "grid_size": 30,
            "terrain": [[...], [...], ...],
            "resources": [[...], [...], ...],
            "buildings": [[...], [...], ...]
        },
        "inventory": {
            "containers": [
                {
                    "container_id": "storage_main",
                    "name": "Main Storage",
                    "capacity": 50,
                    "slots": [
                        {"resource_id": "wood", "quantity": 12, "current_charge": 1200.0},
                        {"resource_id": null, "quantity": 0, "current_charge": 0.0}
                    ]
                }
            ],
            "transit_items": [
                {
                    "transit_id": "transit_001",
                    "source_tile": [5, 12],
                    "target_container_id": "storage_main",
                    "resource_id": "wood",
                    "quantity": 5,
                    "remaining_ticks": 40
                }
            ]
        },
        "buildings": {
            "storage_main": {
                "type": "storage",
                "tile": [8, 8],
                "build_progress": 120,
                "capacity": 150,
                "assigned_containers": ["storage_main"]
            }
        },
        "npcs": {},
        "hunger": {
            "daily_food_requirement": 10,
            "hunger_debuff_active": false
        }
    },
    "player": {
        "energy": 85,
        "mode": "architect",
        "position": [15, 15]
    }
}
```

**Top-level structure:**
- `schema_version` — integer, single source of truth for save format version
- `timestamp` — Unix epoch int (seconds since 1970-01-01), used for save listing
- `game` — namespace for TickSystem data
- `world` — namespace for all world state (Grid, Inventory, Buildings, NPCs, Hunger)
- `player` — namespace for PlayerCharacter state

**Namespacing rationale:** Namespaces prevent key collisions between systems. If both BuildingSystem and NPCSystem use a `position` field, namespaces (`world.buildings` vs `world.npcs`) keep them isolated. Each system knows its own namespace path.

### Serialization Contract (Required Per-System)

Every system that owns persistent state MUST implement:

```gdscript
# Returns a plain dictionary — NOT a node, NOT a reference
# Must be deterministic: same state → identical output every time
func serialize() -> Dictionary

# Restores state from a dictionary produced by serialize()
# Must handle missing keys gracefully (older save file)
# Must NOT call another system's serialize()/deserialize()
func deserialize(data: Dictionary) -> void
```

**Contract rules:**
1. `serialize()` returns a plain `Dictionary` — the orchestrator handles merging and JSON encoding
2. `deserialize()` takes a `Dictionary` — the orchestrator passes each system's data chunk
3. Both methods must be **pure functions** — no file I/O, no signal emission (except `save_completed`/`load_completed` from the orchestrator)
4. `serialize()` must produce **deterministic output** — arrays in index order, no random elements
5. `deserialize()` must use `.get()` with defaults for optional/missing keys — **never** direct dictionary access with `[key]` that raises on missing keys

### Load Order Invariant

```
ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick
```

**Why this order:**
1. **ResourceRegistry** (first, not via save) — loaded from JSON at startup. Every other system's deserialize may reference resource IDs that must already exist in the registry.
2. **GridMap** — Buildings reference tile coordinates. Inventory references grid tile drops. Buildings must be placed on the grid before buildings themselves deserialize.
3. **Inventory** — Buildings reference storage containers. Inventory containers must exist before buildings assign them.
4. **Buildings** — NPCs reference building assignments (which building they work at). Buildings must be created before NPCs.
5. **NPCs** — Hunger depends on NPC count (daily food requirement). NPC list must be known.
6. **Hunger** — Player energy state may depend on hunger debuff. Hunger state must be applied before player.
7. **Player** — Standalone state (energy, position, mode). Does not depend on other systems' data.
8. **TickSystem** (last) — Tick emission must resume AFTER all state is restored. Resuming ticks too early would fire signals before subscribers are ready, causing missed events or state mutations during a half-loaded save.

### Save Slot Management

- **File naming**: `{SAVE_PATH}save_{slot}.json` (e.g., `user://saves/save_1.json`)
- **Slot numbering**: 1-based, configurable up to `_max_slots` (default 10)
- **Metadata**: Each save slot file also gets a companion `{SAVE_PATH}save_{slot}.meta.json` with:
  - `schema_version`
  - `timestamp` (Unix epoch)
  - `current_day`
  - `tick_count`
  - `container_count`
  - This enables listing saves in a UI without loading full JSON (faster, safer)
- **Atomic writes**: Write to `.tmp` file first, then rename to final path. If write crashes, `.tmp` is orphaned (ignored) and the previous save is intact.

### Error Handling Policy

| Error | Handling |
|-------|----------|
| File not found | Return `false`, show "Save slot {slot} is empty" |
| JSON parse failure (corrupted file) | Return `false`, show "Save file is corrupted — cannot load" |
| Schema version too new | Return `false`, show "Save file is from a newer version of the game" |
| Missing required field | Use default value (graceful degradation) or show "Save file is incomplete" |
| FileAccess failure (disk full, permissions) | Return `false`, show "Failed to write save — disk may be full" |
| Deserialize exception | Catch, log to debug console, show "Save file is corrupted — cannot load" |

**Crucial: Never crash on save errors.** A corrupted save should never prevent the player from loading a different slot or starting a new game.

## Alternatives Considered

### Alternative 1: Godot Resource (.tres) + ResourceSaver

Use Godot's built-in serialization: each system's state is a `Resource` subclass saved via `ResourceSaver.save()`.

- **Pros**: Automatic serialization — no `serialize()`/`deserialize()` boilerplate. Inspector-compatible. Built-in resource graph.
- **Cons**: `.tres` is not human-editable in plain text (Godot-specific format). Not version-control friendly — `.tres` files use Godot's internal format with property IDs, not clean JSON. Cannot be compared with `diff`. Designers cannot manually tweak save state for testing.
- **Rejection Reason**: The architecture.md explicitly requires JSON (human-readable). `.tres` violates this constraint.

### Alternative 2: Binary Format (Custom or Engine)

Use `FileAccess.store_*` with a custom binary format, or Godot's `pack()`/`unpack()` for Array/Dictionary.

- **Pros**: Smaller file size. Faster I/O. Slightly harder to cheat/tamper with save files.
- **Cons**: Completely opaque — cannot be inspected, debugged, or manually edited. Binary format changes between engine versions (Pack/unpack may break across Godot minor versions). No diff support. Debugging a broken save requires writing a binary dumper.
- **Rejection Reason**: JSON's debuggability outweighs the minimal size difference (Vertical Slice saves are expected to be < 100KB). Binary format fragility across engine updates is an unacceptable risk.

### Alternative 3: Per-System Files

Each system writes its own JSON file (`tick.json`, `grid.json`, `inventory.json`, etc.) rather than a single merged file.

- **Pros**: Systems are completely isolated — save one system without touching others. Smaller individual files. Parallel I/O possible.
- **Cons**: No atomicity — if the game crashes during save, some system files are updated and others are not, producing a corrupted partial-save state. No single `schema_version` to check — different files could have different versions. Save file listing requires reading multiple files. More complex error recovery (rollback inconsistent systems on load).
- **Rejection Reason**: The single-file approach provides atomicity — either the entire save is written or nothing changes. This is critical for save integrity. The slight I/O overhead (one large JSON write) is negligible for VS-scale data.

### Alternative 4: Compression

Compress the JSON with `ZIPPACK` or `deflate` before writing.

- **Pros**: Smaller save files. Faster disk writes.
- **Cons**: Adds CPU overhead on every save/load. Compressed data is opaque (cannot debug by reading the file). Godot 4.6's `ZIPPACK` is limited — full compression requires `StreamPeerGZIP` or external libraries. Adds another dependency.
- **Rejection Reason**: VS save sizes are expected to be small (< 100KB). Compression is optimization, not a requirement. Defer until profiling shows I/O is a bottleneck.

## Consequences

### Positive

- Deterministic load order prevents race conditions during save loading
- Schema versioning provides a clear migration path for future updates
- Human-readable JSON enables manual save debugging and testing
- Namespaced data structure prevents key collisions between systems
- Metadata files enable fast save listing without full JSON parsing
- Atomic writes (write-then-rename) protect against corruption during crashes
- Error handling policy prevents crashes on corrupted saves — player can always fall back to another slot

### Negative

- JSON is verbose — save files may grow larger than binary alternatives (acceptable for VS)
- `JSON.parse()` on a corrupted file returns an Error code — must be wrapped in `var err = JSON.parse(content)` / `if err != OK`
- Single-file save means the entire file must be read/written — no incremental saves
- Schema version bumps are a breaking change — all existing saves of the previous version must be migrated
- `FileAccess` return value checking (Godot 4.4+) adds boilerplate — must check every I/O call

### Neutral

- `WorldSaveManager` is an Autoload — accessible globally, which can encourage loose coupling if systems call it directly instead of using signal-based save completion notifications
- The metadata file approach doubles disk I/O (read/write two files per slot) — but metadata files are tiny (1KB)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Corrupted JSON from crashed save write | Low | High | Atomic write (write to .tmp, rename). If .tmp exists on startup, log and ignore. |
| JSON parse failure on corrupted file | Medium | High | Wrap `JSON.parse()` in error handling. Never crash. Fall back to title screen. |
| Schema version mismatch (future save loaded by old game) | Low | Medium | Explicitly check `data.schema_version > SCHEMA_VERSION` → reject with clear error message. |
| Schema version mismatch (old save loaded by new game) | High (on updates) | Medium | Deserializers use `.get()` with defaults. Add migration functions when schema changes significantly. |
| Forgetting to add new system to register_save_system() | Medium | High | Add code review checklist item. Test that all registered systems have corresponding serialize()/deserialize() methods. |
| Large saves causing frame hitches | Low | Medium | JSON serialization of 100KB is ~5ms in GDScript. Split large saves into background thread? Not needed for VS. |
| Save file tampering (cheating) | Medium | Low | Not a priority for single-player. Add checksum in MVP if anti-cheat becomes relevant. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (save operation) | 0ms | ~10ms | 50ms — JSON.stringify() of ~50KB, file I/O. Acceptable for a manual action (player-initiated, not per-frame). |
| CPU (load operation) | 0ms | ~15ms | 50ms — JSON.parse() + each system's deserialization. Load screen handles the wait. |
| Memory | baseline | +200KB | ~50KB JSON data + 150KB parse overhead. Trivial. |
| Load Time | baseline | +15ms | Save load is fast — no asset loading, only state restoration. |
| Disk I/O | baseline | ~50KB per save | Small file, single write. Negligible. |

## Migration Plan

1. Create `src/systems/save_world_save_manager.gd` as Autoload — name must match project's Autoload registration
2. Initialize `_registered_systems` inline: `var _registered_systems: Array[String] = []` (not in `_ready()`) — prevents Autoload ready-order race
3. Implement `register_save_system()`, `save_game()`, `load_game()`, file I/O helpers
4. Add `DirAccess.make_dir_absolute(SAVE_PATH)` call before first write — ensure directory exists
5. Add startup cleanup: scan for orphaned `.tmp` files, delete or log warning
6. Implement `_collect_serialize_data()` — iterate `_registered_systems`, call each system's `serialize()`, merge into top-level dict
7. Implement `_process_deserialize_order()` — iterate load order, call each system's `deserialize()` with its data chunk
8. Each system implements `serialize()` and `deserialize()` per this ADR's contract
9. Wire each system into `WorldSaveManager` via `register_save_system()` in `_ready()`
10. Implement metadata file read/write for save listing
11. Test: save → load roundtrip for all systems, verify state equality
12. Test: corrupted file error handling — verify no crash, show error dialog
13. Test: schema version rejection — create a save with `schema_version: 999`, verify load is rejected

**Rollback plan**: Remove `WorldSaveManager` Autoload, delete `src/systems/save_world_save_manager.gd`. Each system's `serialize()`/`deserialize()` methods become unused but harmless. No other systems are affected.

## Validation Criteria

- [ ] Save file is valid JSON with `schema_version` field at top level
- [ ] Load order invariant is strictly enforced: ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick
- [ ] TickSystem deserializes last — ticks do not resume until after all other systems are loaded
- [ ] Schema version too new → save rejected with clear error message, no crash
- [ ] Schema version too old → deserializers use defaults for missing fields, no crash
- [ ] Corrupted JSON → error handled gracefully, player can return to title screen
- [ ] Serialization is deterministic: two saves of the same state produce identical JSON
- [ ] Metadata files correctly report `current_day`, `tick_count`, and `schema_version` without loading full save
- [ ] Atomic write: saving during a simulated crash (write to .tmp only) does not corrupt existing save
- [ ] All registered systems have corresponding `serialize()` and `deserialize()` methods

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `tick-system.md` | Tick | Save/Load System: Serializes full tick state for save files | `TickSystem.serialize()` → `{ tick_count, current_day, speed_multiplier, is_paused, tick_remainder }`; deserializes last in load order |
| `grid-map-system.md` | Grid | Map Loading Edge Cases: building_id not found, coordinate bounds mismatch | `GridMap.deserialize()` handles missing building_ids (destroy instance, restore resource tiles) and out-of-bounds coordinates (discard with log warning) |
| `inventory-storage-system.md` | Inventory | EC-H3: Transport IN_TRANSIT During Save-Load — serialize source tile, target container, quantity, remaining ticks | `InventorySystem.serialize()` includes `transit_items` array in save; `deserialize()` restores transit state, resuming tick countdown on next `ticks_advanced` |
| `inventory-storage-system.md` | Inventory | Dependencies: Save/Load System — `serialize()` returns `Array[container_snapshot]`, `deserialize()` creates containers | Typed `_ContainerSnapshot` and `_SlotSnapshot` classes defined in ADR-0005; serialization in deterministic index order |
| `player-character-system.md` | Player | Save/Load: Serializes energy, mode, carried_item | `PlayerCharacter.serialize()` → `{ energy, mode, position, carried_item? }` |
| `architecture.md` (global) | All | Serialization ownership: each module serializes its own data; `WorldSaveManager` orchestrates order | `WorldSaveManager._collect_serialize_data()` calls each registered system's `serialize()`, merges to top-level dict |
| `architecture.md` (global) | All | Load order invariant: ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick | Enforced by `WorldSaveManager._process_deserialize_order()` — systems registered in this order, deserialized sequentially |

## Related

- ADR-0001: Tick System — tick state serialization
- ADR-0002: Resource Data Registry — always from JSON at startup, never from save
- ADR-0004: Grid Map Data Model — grid state serialization, building_id edge cases
- ADR-0005: Inventory System — container + transit item serialization
- `docs/architecture/architecture.md` Scenario 4: Save/Load Path (existing architecture doc)
- `design/gdd/inventory-storage-system.md` EC-H3, EC-L2 (save/load edge cases)
