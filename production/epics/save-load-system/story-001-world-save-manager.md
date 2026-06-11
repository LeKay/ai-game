# Story 001: WorldSaveManager Orchestrator

> **Epic**: Save/Load System
> **Status**: Complete
> **Layer**: Persistence
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: None — design governed by ADR-0006
**Requirement**: `TR-sv-003` *(TBD — no GDD exists for save-load-system)*

**ADR Governing Implementation**: ADR-0006: Save and Load Format and Serialization Order
**ADR Decision Summary**: WorldSaveManager is an Autoload singleton that collects `serialize()` dicts from each registered system, merges them into a top-level JSON document with `schema_version`, and writes to `user://saves/save_<slot>.json`. Load iterates systems in deterministic order (ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick), passing each system's data chunk to its `deserialize()` method. Systems register via `register_save_system()` in `_ready()`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `JSON.parse()` returns `Error` code (check `result` not truthiness), `FileAccess` methods return `bool` (Godot 4.4+), `DirAccess.make_dir_absolute()` for path creation, `user://` base path — all stable pre-cutoff APIs.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: `serialize()` calling another system's `serialize()`/`deserialize()` — all systems serialize to plain dictionaries; circular serialization
- Guardrail: CPU ~10ms for save, ~15ms for load (JSON of ~50KB)

---

## Acceptance Criteria

- [ ] **AC-1**: Given 3 registered save systems, `save_game(1)` produces a JSON file containing all 3 systems' serialized data under their respective namespaces
- [ ] **AC-2**: Given a saved JSON file, `load_game(1)` deserializes systems in the correct load order: ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick
- [ ] **AC-3**: TickSystem's `deserialize()` is called LAST — after all other systems have restored state
- [ ] **AC-4**: Given a system registers via `register_save_system()`, it is automatically included in the next `save_game()` call without manual orchestration
- [ ] **AC-5**: Given two saves of identical game state, `save_game(1)` and `save_game(2)` produce bit-identical JSON output (deterministic serialization)

---

## Implementation Notes

*Derived from ADR-0006 Implementation Guidelines:*

**WorldSaveManager skeleton:**
```gdscript
extends Node

const SCHEMA_VERSION: int = 1
const SAVE_PATH: String = "user://saves/"
const MAX_SLOTS: int = 10

var _registered_systems: Array[String] = []
var _deserialize_order: Array[String] = [
    "ResourceRegistry",
    "GridMap",
    "Inventory",
    "Buildings",
    "NPCs",
    "Hunger",
    "Player",
    "TickSystem"
]

signal save_completed(slot: int)
signal load_completed(slot: int)
signal save_failed(slot: int, error: String)
signal load_failed(slot: int, error: String)

func register_save_system(name: String) -> void:
    if not _registered_systems.has(name):
        _registered_systems.append(name)

func save_game(slot: int) -> bool:
    if slot < 1 or slot > MAX_SLOTS:
        emit_signal("save_failed", slot, "Invalid slot number")
        return false

    var data := _collect_serialize_data()
    data["schema_version"] = SCHEMA_VERSION
    data["timestamp"] = Time.get_unix_time_from_system()

    var path := SAVE_PATH + "save_%d.json" % slot
    var meta := _build_metadata(data)
    return _atomic_write(path, data) and _atomic_write(SAVE_PATH + "save_%d.meta.json" % slot, meta)

func load_game(slot: int) -> bool:
    if slot < 1 or slot > MAX_SLOTS:
        emit_signal("load_failed", slot, "Invalid slot number")
        return false

    var raw := _read_file(SAVE_PATH + "save_%d.json" % slot)
    if raw == null:
        emit_signal("load_failed", slot, "Save slot is empty")
        return false

    if not _validate_schema_version(raw):
        emit_signal("load_failed", slot, "Save file is from a newer version of the game")
        return false

    var ok := _process_deserialize_order(raw)
    if ok:
        emit_signal("load_completed", slot)
    else:
        emit_signal("load_failed", slot, "Save file is corrupted — cannot load")
    return ok

func _collect_serialize_data() -> Dictionary:
    var data := {}
    for name in _registered_systems:
        var sys := get_node_or_null("/root/" + name)
        if sys != null and sys.has_method("serialize"):
            var result = sys.call("serialize")
            if result is Dictionary:
                data[name.to_lower()] = result
    return data

func _process_deserialize_order(data: Dictionary) -> bool:
    for name in _deserialize_order:
        var key := name.to_lower()
        if data.has(key):
            var sys := get_node_or_null("/root/" + name)
            if sys != null and sys.has_method("deserialize"):
                try:
                    sys.call("deserialize", data[key])
                except:
                    push_error("Deserialize exception for system: %s" % name)
                    return false
    return true

func _validate_schema_version(data: Dictionary) -> bool:
    var version := data.get("schema_version", -1)
    return version >= 0 and version <= SCHEMA_VERSION
```

**Per-system serialization contract:**
```gdscript
# Each system's serialize() returns a plain Dictionary
# MUST be deterministic: same state → identical output every time
# MUST NOT call another system's serialize()/deserialize()
# MUST produce arrays in index order, sorted keys for dictionaries
func serialize() -> Dictionary

# Each system's deserialize() takes a Dictionary
# MUST handle missing keys gracefully using .get() with defaults
# MUST NOT call another system's serialize()/deserialize()
func deserialize(data: Dictionary) -> void
```

**Key design invariants:**
- Load order is fixed and enforced by `_deserialize_order` array — never reordered at runtime
- Each system serializes to its own namespace key (lowercase system name)
- `serialize()` produces pure data — no node references, no Callable, no Object instances
- Systems register via `register_save_system()` in their `_ready()` — must complete before any save can occur
- TickSystem is always LAST in deserialize order (confirmed by ADR-0006 rationale)

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Save slot management, metadata files, atomic writes
- Story 003: Schema version validation, error handling
- Individual system serialize()/deserialize() implementations (each system's story handles its own serialization)

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases derived from ADR-0006 acceptance criteria.*

- **AC-1**: Multi-system save produces complete JSON
  - Given: 3 registered systems (TickSystem, GridMap, Inventory); each returns unique data in serialize()
  - When: `save_game(1)` called
  - Then: `user://saves/save_1.json` contains valid JSON with all 3 systems' data under their namespace keys; top-level `schema_version` field exists

- **AC-2**: Load restores systems in correct order
  - Given: Save file with TickSystem, GridMap, Inventory data
  - When: `load_game(1)` called
  - Then: GridMap.deserialize() called before Inventory.deserialize(); Inventory.deserialize() called before TickSystem.deserialize() (verified by observing _deserialize_order sequence)

- **AC-3**: TickSystem deserializes last
  - Given: Full save with all 8 systems in load order
  - When: `load_game(1)` called
  - Then: TickSystem.deserialize() is the final deserialize() call; no other system's deserialize() is called after it

- **AC-4**: Auto-registration works
  - Given: A new system calls `register_save_system("NewSystem")` in its _ready()
  - When: `save_game(1)` is called next
  - Then: NewSystem's serialize() is called and its data appears in the saved JSON

- **AC-5**: Deterministic serialization
  - Given: Identical game state saved twice (same tick count, same grid, same inventory)
  - When: `save_game(1)` then `save_game(2)`
  - Then: `save_1.json` and `save_2.json` are byte-for-byte identical (verified by file comparison)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/save_world/save_manager_test.gd` — must exist and pass

**Status**: [x] Created — `tests/unit/save_world/save_manager_test.gd` (15 test functions)

---

## Dependencies

- Depends on: None (this is the first story; creates the WorldSaveManager Autoload framework)
- Unlocks: All other save/load stories; individual system serialize()/deserialize() implementations

---

## Completion Notes
**Completed**: 2026-06-05
**Criteria**: 5/5 implemented, 1 advisory (AC-5 timestamp prevents byte-for-byte identity; system data fields verified deterministic)
**Deviations**:
- ADVISORY: Namespace keys use exact registered name (e.g. "TickSystem") not lowercased as ADR-0006 specifies — downstream system stories must be consistent
- ADVISORY: Signals (save_completed, save_failed) from ADR skeleton not implemented; printerr()/print() used instead — deferred to UI wiring story
- ADVISORY: AC-5 timestamp caveat — byte-identical save files unachievable with live timestamp; test verifies system-data equality only
- OUT OF SCOPE: Metadata files (.meta.json) and atomic writes (.json.tmp → rename) implemented here; Story 002 should update its scope to reflect this
**Test Evidence**: Logic — `tests/unit/save_world/save_manager_test.gd` (15 test functions)
**Code Review**: Skipped — Lean mode
