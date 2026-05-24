# Story 003: Schema Versioning and Error Handling

> **Epic**: Save/Load System
> **Status**: Ready
> **Layer**: Persistence
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: None — design governed by ADR-0006
**Requirement**: `TR-sv-002` *(Schema validation on load with fail-fast)*, `TR-sv-005` *(Schema versioning)*

**ADR Governing Implementation**: ADR-0006: Save and Load Format and Serialization Order
**ADR Decision Summary**: Save file has a single top-level `schema_version`. Loading rules: version < current → migration (use default values for missing fields); version == current → direct load; version > current → reject with clear error message. JSON parse failure → show error dialog, return to title screen. Never crash on save errors. Each system's `deserialize()` uses `.get()` with defaults for optional/missing keys.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `JSON.parse()` returns `Error` code (check `result` not truthiness), `JSON.stringify()` returns empty string on parse failure — all stable pre-cutoff. `push_error()` for debug console logging of corrupted saves.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Crashing on corrupted save — must show error dialog and allow fallback
- Guardrail: All deserializers must use `.get()` with defaults, never direct dictionary access with `[key]` that raises on missing keys

---

## Acceptance Criteria

- [ ] **AC-11**: Given a save file with `schema_version: 999` (future version), `load_game(1)` returns `false`, emits `load_failed` signal, and shows "Save file is from a newer version of the game" error
- [ ] **AC-12**: Given a save file with `schema_version: 0` (missing fields), `load_game(1)` returns `true` and systems use default values for missing fields — no crash
- [ ] **AC-13**: Given a corrupted JSON file (invalid JSON syntax), `load_game(1)` returns `false`, emits `load_failed` signal, and shows "Save file is corrupted" error — player is NOT kicked out of the game
- [ ] **AC-14**: Given an empty save slot (no file exists), `load_game(1)` returns `false` with "Save slot is empty" message
- [ ] **AC-15**: Given a valid save, `load_game()` completes successfully and all registered systems have their state restored

---

## Implementation Notes

*Derived from ADR-0006 Implementation Guidelines:*

**Schema validation and error handling on WorldSaveManager:**
```gdscript
func _read_file(path: String) -> Dictionary:
    var fa := FileAccess.open(path, FileAccess.READ)
    if fa == null:
        return null
    var content := fa.get_as_text()
    fa.close()
    var err := JSON.parse(content)
    if err != OK:
        push_error("JSON parse error at %s: error_code=%d" % [path, err])
        return null
    var result = JSON.parse(content)
    if result.error_code != OK:
        push_error("JSON parse failed for %s: %s" % [path, result.error_string])
        return null
    return result.result as Dictionary

func _validate_schema_version(data: Dictionary) -> bool:
    var version := data.get("schema_version", -1)
    if version < 0:
        push_error("Save file has no schema_version field")
        return false
    if version > SCHEMA_VERSION:
        push_error("Save file schema_version %d > current %d" % [version, SCHEMA_VERSION])
        return false
    if version == 0:
        push_warning("Loading save from schema v0 — using defaults for missing fields")
    return true

# _collect_serialize_data and _process_deserialize_order are in Story 001
```

**Per-system deserialize contract (must be followed by all consuming systems):**
```gdscript
# CORRECT — use .get() with defaults:
func deserialize(data: Dictionary) -> void:
    var version = data.get("schema_version", 1)
    var grid_data = data.get("grid", {})
    var terrain = grid_data.get("terrain", [])
    if terrain.is_empty():
        terrain = _generate_default_terrain()  # fallback for v0 save

# INCORRECT — direct access raises KeyError on missing key:
# var terrain = data["grid"]["terrain"]  # CRASH if missing
```

**Error policy table (must be documented for all systems):**

| Error | Response | Signal Emitted |
|-------|----------|----------------|
| File not found | Return `false`, emit `load_failed(slot, "Save slot is empty")` | load_failed |
| JSON parse failure | Return `false`, emit `load_failed(slot, "Save file is corrupted — cannot load")` | load_failed |
| Schema version too new | Return `false`, emit `load_failed(slot, "Save file is from a newer version of the game")` | load_failed |
| Missing required field | Use default value (graceful degradation) — no signal | none |
| FileAccess failure (disk full, permissions) | Return `false`, emit `save_failed(slot, "Failed to write save — disk may be full")` | save_failed |
| Deserialize exception | Catch, log to debug console, return `false` from load_game | load_failed |

**Crucial invariant**: Never crash on save errors. A corrupted save should never prevent the player from loading a different slot or starting a new game.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: WorldSaveManager framework and save_game()/load_game() entry points
- Story 002: Save slot management and metadata files
- Migration functions for significant schema changes (deferred to MVP+)

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases derived from ADR-0006 acceptance criteria.*

- **AC-11**: Future schema version → reject
  - Given: `user://saves/save_1.json` contains `{"schema_version": 999, ...}`
  - When: `load_game(1)` called
  - Then: returns `false`; `load_failed` signal emitted with message containing "newer version"; no systems are deserialized

- **AC-12**: Old schema (v0) → defaults for missing fields
  - Given: `user://saves/save_1.json` contains `{"schema_version": 0, ...}` (missing grid, inventory, etc.)
  - When: `load_game(1)` called
  - Then: returns `true`; systems use default values for missing data; no crash; `load_completed` signal emitted

- **AC-13**: Corrupted JSON → no crash, show error
  - Given: `user://saves/save_1.json` contains `{invalid json content` (malformed)
  - When: `load_game(1)` called
  - Then: returns `false`; `load_failed` signal emitted with "corrupted" message; game remains running (no crash); player can call `load_game(2)` with a valid save

- **AC-14**: Empty slot → no crash
  - Given: No file exists at `user://saves/save_1.json`
  - When: `load_game(1)` called
  - Then: returns `false`; `load_failed` signal emitted with "empty" message

- **AC-15**: Full load round-trip succeeds
  - Given: A valid save file with all 8 systems' data under correct namespaces
  - When: `load_game(1)` called
  - Then: returns `true`; `load_completed` signal emitted; all registered systems have their state restored

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/save_world/schema_validation_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (WorldSaveManager framework, save_game(), load_game(), _collect_serialize_data() must exist)
- Unlocks: None (this is a cross-cutting concern; all systems' serialize()/deserialize() implementations consume the error handling policy)
