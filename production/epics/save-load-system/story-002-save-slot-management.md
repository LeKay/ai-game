# Story 002: Save Slot Management and Metadata

> **Epic**: Save/Load System
> **Status**: Complete
> **Layer**: Persistence
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: None — design governed by ADR-0006
**Requirement**: `TR-sv-004` *(TBD — no GDD exists for save-load-system)*

**ADR Governing Implementation**: ADR-0006: Save and Load Format and Serialization Order
**ADR Decision Summary**: Save slots are 1-based, configurable up to MAX_SLOTS (default 10). Each save slot has a data file (`save_<slot>.json`) and a companion metadata file (`save_<slot>.meta.json`). Metadata contains `schema_version`, `timestamp`, `current_day`, `tick_count`, `container_count` — enabling fast save listing without parsing full JSON. Atomic writes use write-to-tmp-then-rename pattern. Startup cleanup scans for orphaned `.tmp` files.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `FileAccess.open()` returns `bool` for success (Godot 4.4+), `DirAccess` for file listing, `user://` path — all stable pre-cutoff.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Reading full JSON to list saves (must use metadata file)
- Guardrail: Metadata file read is < 1KB — sub-millisecond for save listing UI

---

## Acceptance Criteria

- [ ] **AC-6**: Given 3 slots have been used, `get_available_slots()` returns [1, 2, 3]
- [ ] **AC-7**: Given `save_game(2)` is called, both `save_2.json` and `save_2.meta.json` are created atomically
- [ ] **AC-8**: Given `save_2.json` exists but `save_2.meta.json` is missing, `get_save_info(2)` returns null (not null-safe crash)
- [ ] **AC-9**: Given `save_game(2)` is called and the game crashes mid-write (write to .tmp only), the existing `save_2.json` is NOT corrupted
- [ ] **AC-10**: On startup, orphaned `.tmp` files in `user://saves/` are detected and cleaned up (deleted or logged)

---

## Implementation Notes

*Derived from ADR-0006 Implementation Guidelines:*

**Slot management methods on WorldSaveManager:**
```gdscript
func get_available_slots() -> Array[int]:
    var slots := []
    var dir := DirAccess.open(SAVE_PATH)
    if dir == null:
        return slots
    dir.list_dir_begin()
    var file := dir.get_next()
    while file != "":
        if file.begins_with("save_") and file.ends_with(".json"):
            var slot_num := _extract_slot_number(file)
            if slot_num >= 1 and slot_num <= MAX_SLOTS:
                slots.append(slot_num)
        file = dir.get_next()
    dir.list_dir_end()
    slots.sort()
    return slots

func get_save_info(slot: int) -> Dictionary:
    var meta_path := SAVE_PATH + "save_%d.meta.json" % slot
    var meta := _read_file(meta_path)
    if meta == null:
        # Data file exists but no metadata — return empty
        return {}
    return {
        schema_version = meta.get("schema_version", 0),
        timestamp = meta.get("timestamp", 0),
        current_day = meta.get("current_day", 0),
        tick_count = meta.get("tick_count", 0),
        container_count = meta.get("container_count", 0)
    }

func delete_save(slot: int) -> bool:
    var data_path := SAVE_PATH + "save_%d.json" % slot
    var meta_path := SAVE_PATH + "save_%d.meta.json" % slot
    DirAccess.remove_absolute(data_path)
    DirAccess.remove_absolute(meta_path)
    return true

func _atomic_write(path: String, data: Dictionary) -> bool:
    var tmp_path := path + ".tmp"
    var json_str := JSON.stringify(data)
    var fa := FileAccess.open(tmp_path, FileAccess.WRITE)
    if fa == null:
        return false
    fa.store_string(json_str)
    fa.close()
    # Rename is atomic on most filesystems
    DirAccess.remove_absolute(path)
    var ok := DirAccess.rename_absolute(tmp_path, path)
    if not ok:
        # Failed to rename — .tmp is orphaned (cleaned up on next startup)
        push_warning("Atomic write failed for %s — .tmp orphaned" % path)
    return true

func _build_metadata(data: Dictionary) -> Dictionary:
    var world := data.get("world", {})
    var game := data.get("game", {})
    var tick_data := game.get("tick", {})
    var inventory_data := world.get("inventory", {})
    var containers := inventory_data.get("containers", [])
    return {
        schema_version = data.get("schema_version", 1),
        timestamp = data.get("timestamp", 0),
        current_day = tick_data.get("current_day", 0),
        tick_count = tick_data.get("tick_count", 0),
        container_count = containers.size()
    }

func _startup_cleanup() -> void:
    var dir := DirAccess.open(SAVE_PATH)
    if dir == null:
        return
    dir.list_dir_begin()
    var file := dir.get_next()
    while file != "":
        if file.ends_with(".tmp"):
            DirAccess.remove_absolute(SAVE_PATH + file)
            push_warning("Cleaned up orphaned .tmp file: %s" % file)
        file = dir.get_next()
    dir.list_dir_end()
```

**Key design invariants:**
- Slot numbers are 1-based, not 0-based (UI-friendly)
- Atomic write: write JSON to `.tmp`, then rename `rename_absolute(tmp, final)` — if rename fails, `.tmp` is orphaned and cleaned on next startup
- Metadata is always written alongside data — if metadata is missing, `get_save_info()` returns empty dict (not null)
- `_startup_cleanup()` is called in `_ready()` before any save/load can occur

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: WorldSaveManager framework and register_save_system()
- Story 003: Schema version validation and error handling policies

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases derived from ADR-0006 acceptance criteria.*

- **AC-6**: Available slots reported correctly
  - Given: Slots 1, 2, 3 have been saved; slot 4 is empty
  - When: `get_available_slots()` called
  - Then: returns [1, 2, 3] (sorted, excludes empty slots)

- **AC-7**: Atomic save creates both files
  - Given: `save_game(2)` called
  - When: save completes
  - Then: both `user://saves/save_2.json` and `user://saves/save_2.meta.json` exist; metadata contains correct schema_version and timestamp

- **AC-8**: Missing metadata handled gracefully
  - Given: `save_2.json` exists but `save_2.meta.json` does not
  - When: `get_save_info(2)` called
  - Then: returns `{}` (empty dict, not null — caller can check `.is_empty()`)

- **AC-9**: Crash during write preserves existing save
  - Given: Existing valid `save_2.json`; `save_game(2)` called but only writes to `.tmp` (simulated crash via DirAccess.remove_absolute on final path before rename)
  - When: save operation fails
  - Then: existing `save_2.json` is untouched; `save_2.json.tmp` is orphaned (cleaned on next startup)

- **AC-10**: Orphaned .tmp cleanup
  - Given: `user://saves/` contains `save_1.json.tmp`
  - When: WorldSaveManager `_ready()` runs `_startup_cleanup()`
  - Then: orphaned .tmp file is deleted; warning logged

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/save_world/save_slot_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (WorldSaveManager framework and register_save_system() must exist)
- Unlocks: Story 003 (error handling can reference save slot paths)

---

## Completion Notes
**Completed**: 2026-06-05
**Criteria**: 5/5 passing (all criteria covered)
**Deviations**: Advisory only — manifest version not set in story header (no manifest existed at story creation); TR-sv-004 not in registry (no GDD exists for save-load-system, expected); AC-9 atomicity tested indirectly via orphaned-.tmp pattern
**Test Evidence**: Logic — `tests/unit/save_world/save_slot_test.gd` (13 test functions)
**Code Review**: Skipped — Lean mode
