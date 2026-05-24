# Story 005: Version Migration and Deprecated Resources

> **Epic**: Resource System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/resource-system.md`
**Requirement**: `TR-res-001` (extended — load-time migration behavior)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: Resource Data Registry Format and Loading (primary); ADR-0006: Save and Load Format and Serialization Order (secondary)
**ADR Decision Summary**: The JSON `"version"` field enables forward compatibility. When the game loads an old registry version, optional fields default gracefully (e.g., `weight` defaults to 0.0). The `"deprecated": true` flag keeps old resource definitions loadable from saves while hiding them from new loot/merchant systems. Version downgrade (save newer than game) blocks load with an error.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: `FileAccess.open()` null-check is critical here too — migration reads the same file. JSON `Dictionary.get(key, default)` provides safe optional field defaulting. No post-cutoff APIs. Verify behavior when JSON contains int vs float for `weight` field (GDScript may need explicit `float()` cast).

**Control Manifest Rules (this layer)**:
- Required: Version field in JSON; migration applies defaults for new optional fields; deprecated resources remain loadable
- Forbidden: Silently stripping deprecated resources from the cache; blocking load for missing optional fields
- Guardrail: Version downgrade (save newer than game) must block load with a user-visible error — do not silently corrupt state

---

## Acceptance Criteria

*From GDD `design/gdd/resource-system.md`:*

- [ ] **AC-1**: Given a registry JSON with `"version": 1` (no `"weight"` field on resources), when loaded by a game with schema version 2 (weight is now optional), then all resources load successfully with `weight` defaulting to `0.0` and a migration log message is emitted
- [ ] **AC-2**: Given a resource with `"deprecated": true` in the registry JSON, when `get_definition(&"old_tool")` is called, then it returns the definition with `deprecated == true` (resource is in cache and accessible)
- [ ] **AC-3**: Given a resource with `"deprecated": true`, when `get_all_by_category()` is called, then the deprecated resource IS included in the result (callers filter by `def.deprecated` themselves — the registry does not hide it)
- [ ] **AC-4**: Given a save file was created with registry version 2, and the current game has registry version 1 (downgrade), when `load_from_file()` runs, then loading is blocked with `push_error()` referencing the version mismatch — game does not silently start with wrong state
- [ ] **AC-5**: Given a resource entry has `"weight": 2` (integer in JSON, expected float), when loaded, then `weight` is stored as `2.0` float without error

---

## Implementation Notes

*Derived from ADR-0002 and ADR-0006 Implementation Guidelines:*

Add version comparison and migration support to `load_from_file()`:

```gdscript
const CURRENT_SCHEMA_VERSION: int = 1  # Increment when adding required fields

func load_from_file(path: String) -> bool:
    # ... (file open + JSON parse from Story 001) ...
    _registry_version = int(data.get("version", 0))

    if _registry_version > CURRENT_SCHEMA_VERSION:
        push_error("ResourceRegistry: Save version %d exceeds game version %d — cannot load" % [
            _registry_version, CURRENT_SCHEMA_VERSION])
        return false

    if _registry_version < CURRENT_SCHEMA_VERSION:
        push_warning("ResourceRegistry: Migrating registry from v%d to v%d — applying defaults" % [
            _registry_version, CURRENT_SCHEMA_VERSION])
        # Migration: defaults are applied in _cache_resource() via .get(key, default)

    return _parse_resources(data.get("resources", []))
```

**Deprecated flag**: The `deprecated` field is already handled by `_cache_resource()` in Story 003 (`def.deprecated = bool(entry.get("deprecated", false))`). No additional caching logic needed — deprecated definitions sit in `_definitions` like any other entry.

**Caller responsibility for deprecated filtering**: Systems that must exclude deprecated resources (Hunger System, Production System, loot tables) call `get_all_by_category()` and filter by `not def.deprecated`. ResourceRegistry does not hide deprecated resources from `get_definition()` or `get_all_by_category()` — the Inventory System needs to load deprecated items from existing saves.

**Weight field migration example**: In `_cache_resource()`, `float(entry.get("weight", 0.0))` already handles both the missing field case and the int→float cast. No special migration code needed for optional fields.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Visual display of deprecated resources (grayed-out icon, "(Deprecated)" suffix) — this is HUD/Inventory UI, not ResourceRegistry
- The actual save file format (`WorldSaveManager`) — ADR-0006 epic handles that
- Unknown resource handling (save contains resource ID not in registry) — handled at the Inventory System level, not ResourceRegistry

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Schema version migration — optional field defaults
  - Given: JSON with `"version": 1`, resources have no `"weight"` field
  - When: `load_from_file()` called (CURRENT_SCHEMA_VERSION = 1, so no mismatch in VS — test as v0→v1 migration if version is bumped; or verify default applies)
  - Then: `get_definition(&"wood").weight == 0.0`; `push_warning()` called if version < CURRENT
  - Edge cases: version field missing entirely → treated as v0; warn and migrate

- **AC-2**: Deprecated resource is in cache
  - Given: JSON has `{"id":"old_tool","deprecated":true,...}`
  - When: `get_definition(&"old_tool")` called after load
  - Then: returns definition with `deprecated == true`; not null

- **AC-3**: get_all_by_category includes deprecated
  - Given: Registry has berry (consumable, deprecated:false) and old_food (consumable, deprecated:true)
  - When: `get_all_by_category(ResourceCategory.CONSUMABLE)` called
  - Then: returns Array of length 2 (both included); caller can filter by `def.deprecated`

- **AC-4**: Version downgrade blocks load
  - Given: CURRENT_SCHEMA_VERSION = 1; JSON has `"version": 2`
  - When: `load_from_file()` called
  - Then: returns `false`; `push_error()` called with version numbers in message; `_definitions` is empty

- **AC-5**: Integer weight field cast to float
  - Given: JSON has `{"id":"wood","weight":2,...}` (integer 2, not float 2.0)
  - When: `get_definition(&"wood")` called after load
  - Then: `def.weight == 2.0` (float); no type error; no crash

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/resource/version_migration_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 004 must be DONE (full ResourceRegistry implementation — all fields cached, all API methods present)
- Unlocks: Save/Load System epic (WorldSaveManager can rely on ResourceRegistry handling deprecated/versioned entries correctly)
