# Story 003: Dictionary Cache and O(1) Lookup API

> **Epic**: Resource System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/resource-system.md`
**Requirement**: `TR-res-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: Resource Data Registry Format and Loading
**ADR Decision Summary**: Post-validation, resource entries are cached in `_definitions: Dictionary[StringName, _ResourceDefinition]`. Three public query methods provide O(1) or O(n) access: `get_definition(id)` returns null for unknown IDs (no crash), `is_valid_id(id)` returns bool, `get_all_by_category(cat)` returns a fresh Array (callers must not mutate).

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: `StringName` is the preferred key type for Godot dictionaries — use `&"wood"` syntax (StringName literals) in tests and call sites. Dictionary `.get(key, null)` is safe for null-return on miss. Verify that `Dictionary[StringName, _ResourceDefinition]` typed dictionary syntax works in Godot 4.6 — if not, use untyped `Dictionary` with explicit cast.

**Control Manifest Rules (this layer)**:
- Required: O(1) lookup via Dictionary — no linear search through the resources array at runtime
- Forbidden: direct_dictionary_access_in_deserialize — callers must use `get_definition()`, never access `_definitions` directly
- Guardrail: 0.002ms per lookup budget; `get_all_by_category()` is O(n) — acceptable for startup-only calls only

---

## Acceptance Criteria

*From GDD `design/gdd/resource-system.md`:*

- [ ] **AC-1**: Given the registry is loaded, when `get_definition(&"wood")` is called, then it returns a `_ResourceDefinition` with the correct id, display_name, category, stack_limit, and icon_path
- [ ] **AC-2**: Given the registry is loaded, when `get_definition(&"nonexistent_id")` is called, then it returns `null` (no crash, no error logged)
- [ ] **AC-3**: Given the registry is loaded, when `is_valid_id(&"wood")` is called, then it returns `true`; when `is_valid_id(&"???")` is called, then it returns `false`
- [ ] **AC-4**: Given a recipe system calls `is_valid_id()` for an unknown resource ID `"unknown_item"`, then `is_valid_id()` returns `false`, enabling the caller to mark the recipe as INVALID
- [ ] **AC-5**: Given the registry has 30 resources, when `get_definition()` is called 10,000 times in a tight loop, then total time is under 1ms (verifying O(1) performance)

---

## Implementation Notes

*Derived from ADR-0002 Implementation Guidelines:*

Add caching and public methods to ResourceRegistry:

```gdscript
func _cache_resource(entry: Dictionary) -> void:
    var def := _ResourceDefinition.new()
    def.id = StringName(entry["id"])
    def.display_name = entry["display_name"]
    def.category = _parse_category(entry["category"])
    def.stack_limit = int(entry["stack_limit"])
    def.icon_path = entry["icon_path"]
    # Optional fields with defaults
    def.subcategory = entry.get("subcategory", "")
    def.weight = float(entry.get("weight", 0.0))
    def.base_value = int(entry.get("base_value", 0))
    def.max_durability = int(entry.get("max_durability", 0))
    def.description = entry.get("description", "")
    def.tags = entry.get("tags", [])
    def.deprecated = bool(entry.get("deprecated", false))
    _definitions[def.id] = def

func get_definition(id: StringName) -> _ResourceDefinition:
    return _definitions.get(id, null)

func is_valid_id(id: StringName) -> bool:
    return id in _definitions

func _parse_category(cat_string: String) -> ResourceCategory:
    match cat_string:
        "verbrauchsgut": return ResourceCategory.VERBRAUCHSGUT
        _: return ResourceCategory.PRODUKTIONSWARE
```

**Important**: `get_definition()` return type annotation is `_ResourceDefinition` — GDScript allows returning `null` from a typed method. Callers must null-check. Do not annotate as `_ResourceDefinition?` (nullable annotation syntax varies — use untyped return or verify Godot 4.6 nullable annotation support).

`_definitions` must never be exposed directly (no getter). Callers always go through `get_definition()` — this is the "no direct dictionary access" rule.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Validation that ensures the cache only contains valid entries
- Story 004: `get_all_by_category()` method (requires category enum — implemented there)
- Story 005: Handling deprecated resources returned from `get_definition()` (callers check `def.deprecated`)

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: get_definition returns correct struct
  - Given: Registry loaded with `{"id":"wood","display_name":"Wood","category":"produktionsware","stack_limit":99,"icon_path":"..."}`
  - When: `get_definition(&"wood")` called
  - Then: returned definition is not null; `.display_name == "Wood"`; `.stack_limit == 99`; `.category == ResourceCategory.PRODUKTIONSWARE`

- **AC-2**: get_definition returns null for unknown ID
  - Given: Registry loaded (wood exists)
  - When: `get_definition(&"unicorn_horn")` called
  - Then: returns `null`; no `push_error()` called; no crash

- **AC-3**: is_valid_id returns correct bool
  - Given: Registry loaded with wood
  - When: `is_valid_id(&"wood")` and `is_valid_id(&"???")` called
  - Then: first returns `true`; second returns `false`

- **AC-4**: is_valid_id enables external validation
  - Given: Registry loaded; "unknown_item" not in registry
  - When: external system calls `is_valid_id(&"unknown_item")`
  - Then: returns `false` — external system can use this to mark its own state INVALID

- **AC-5**: O(1) lookup performance
  - Given: Registry with 30 resources loaded
  - When: `get_definition()` called in loop 10,000 times
  - Then: completes in < 1ms total wall-clock time (GUT test with Time.get_ticks_usec())

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/resource/lookup_api_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 must be DONE (cache is populated only after validation passes)
- Unlocks: Story 004 (category filtering needs the cache and category enum), Story 005 (deprecated flag accessible via get_definition)
