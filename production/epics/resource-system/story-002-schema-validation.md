# Story 002: Schema Validation and Fail-Fast

> **Epic**: Resource System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/resource-system.md`
**Requirement**: `TR-res-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: Resource Data Registry Format and Loading
**ADR Decision Summary**: `_validate_resource()` checks each resource entry for required fields (`id`, `display_name`, `category`, `stack_limit`, `icon_path`) and cross-field constraints (`max_charge` must be > 0.0 when provided). Any validation failure halts loading with a clear error (`push_error()`). Invalid category strings default to `"produktionsware"` with a logged warning rather than halting load entirely.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: No post-cutoff APIs. GDScript `Dictionary.has()` and type-checking via `is` operator are stable. `push_error()` vs `push_warning()` distinction matters — validation errors that halt load use `push_error()`; recoverable issues (invalid category default) use `push_warning()`.

**Control Manifest Rules (this layer)**:
- Required: Fail-fast validation — invalid data must halt loading, not silently corrupt runtime state
- Forbidden: Silently ignoring missing required fields; continuing load after a required-field error
- Guardrail: Cross-field constraint (`max_charge <= 0.0` when provided) must be caught at load time

---

## Acceptance Criteria

*From GDD `design/gdd/resource-system.md`:*

- [ ] **AC-1**: Given a resource entry missing a required field (e.g., no `"id"`), when `load_from_file()` runs, then loading halts, `push_error()` is called with the entry index and missing field name, and `load_from_file()` returns `false`
- [ ] **AC-2**: Given a resource with `max_charge: 0.0` or `max_charge: -1.0` (invalid — must be > 0.0), when validation runs, then loading halts with a clear error naming the resource ID and the invalid value
- [ ] **AC-3**: Given a resource with `category: "misc"` (invalid enum value), when validation runs, then the resource loads with category defaulted to `"production_good"`, `push_warning()` is called, and loading continues (not halted)
- [ ] **AC-4**: Given all resources have valid required fields and no cross-field violations, when `load_from_file()` runs, then validation passes with no errors and all resources are cached
- [ ] **AC-5**: Given a resource with `stack_limit: 0` (invalid — must be >= 1), when validation runs, then loading halts with a clear error

---

## Implementation Notes

*Derived from ADR-0002 Implementation Guidelines:*

Add `_validate_resource()` to ResourceRegistry and wire it into `_parse_resources()`:

```gdscript
const _VALID_CATEGORY_STRINGS: Array[String] = ["consumable", "production_good"]

func _validate_resource(entry: Dictionary, index: int) -> Array[String]:
    var errors: Array[String] = []
    if not entry.has("id") or not entry["id"] is String:
        errors.append("Resource at index %d: missing or invalid 'id'" % index)
    if not entry.has("display_name") or not entry["display_name"] is String:
        errors.append("Resource at index %d: missing or invalid 'display_name'" % index)
    if not entry.has("category"):
        errors.append("Resource at index %d: missing 'category'" % index)
    elif entry["category"] not in _VALID_CATEGORY_STRINGS:
        # Recoverable: default to production_good, log warning, do not add to errors
        push_warning("ResourceRegistry: Resource '%s' has invalid category '%s' — defaulting to 'production_good'" % [
            entry.get("id", "???"), entry["category"]])
        entry["category"] = "production_good"
    if not entry.has("stack_limit") or not (entry["stack_limit"] is int and entry["stack_limit"] >= 1):
        errors.append("Resource at index %d: 'stack_limit' must be int >= 1" % index)
    if not entry.has("icon_path") or not entry["icon_path"] is String:
        errors.append("Resource at index %d: missing or invalid 'icon_path'" % index)
    # Cross-field constraint: max_charge must be > 0.0 when provided
    if entry.has("max_charge"):
        if not entry["max_charge"] is float and not entry["max_charge"] is int:
            errors.append("Resource '%s': 'max_charge' must be a number" % entry.get("id", "???"))
        elif float(entry["max_charge"]) <= 0.0:
            errors.append("Resource '%s': 'max_charge' must be > 0.0 (got %s)" % [entry.get("id", "???"), entry["max_charge"]])
    return errors

func _parse_resources(resources_array: Array) -> bool:
    for i in resources_array.size():
        var errors: Array[String] = _validate_resource(resources_array[i], i)
        if not errors.is_empty():
            for err in errors:
                push_error("ResourceRegistry validation: " + err)
            return false  # Fail-fast: first invalid resource halts load
        _cache_resource(resources_array[i])
    return true
```

The invalid-category case mutates `entry["category"]` in-place before caching (since the entry is a dictionary reference). This is safe — the entry is not stored anywhere else.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: File I/O and JSON parsing
- Story 003: Public lookup API (`get_definition()`, `is_valid_id()`)
- Story 005: Deprecated resource flag handling (a separate optional-field check)

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Missing required field halts load
  - Given: resources.json contains `[{"display_name": "Wood", "category": "produktionsware", "stack_limit": 99, "icon_path": "..."}]` (no "id")
  - When: `load_from_file()` called
  - Then: returns `false`; `push_error()` called with "index 0" and "id" in message

- **AC-2**: Invalid max_charge halts load
  - Given: entry has `"max_charge": 0.0` (or `-5.0`) with all other required fields valid
  - When: `_validate_resource()` called
  - Then: errors array contains message naming the resource ID and stating max_charge must be > 0.0

- **AC-3**: Invalid category defaults (does not halt)
  - Given: entry has `"category": "misc"` with all other required fields valid
  - When: `_validate_resource()` called
  - Then: errors array is empty; `push_warning()` called; entry category becomes `"production_good"`

- **AC-4**: All valid — no errors
  - Given: entry has id, display_name, valid category, stack_limit >= 1, icon_path
  - When: `_validate_resource()` called
  - Then: returns empty errors array; no push_error or push_warning called

- **AC-5**: stack_limit = 0 halts load
  - Given: entry has `"stack_limit": 0`
  - When: `_validate_resource()` called
  - Then: errors array contains message about stack_limit being invalid

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/resource/validation_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (ResourceRegistry Autoload skeleton + `_parse_resources()` entry point exists)
- Unlocks: Story 003 (lookup API can trust that all cached definitions have been validated)
