# Story 001: JSON File Loading and Registry Schema

> **Epic**: Resource System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/resource-system.md`
**Requirement**: `TR-res-001`, `TR-res-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: Resource Data Registry Format and Loading
**ADR Decision Summary**: ResourceRegistry is an Autoload singleton (`extends Node`) that opens `res://data/resources.json` with `FileAccess.open()`, parses it with `JSON.parse()`, validates the schema, and caches definitions in a `Dictionary[StringName, _ResourceDefinition]`. The JSON file (not `.tres`) is the authoritative source — editable outside Godot.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: `FileAccess.open()` returns a `FileAccess` object (null on failure) in Godot 4.4+ — NOT a bool. Must null-check the return value, not bool-check. `FileAccess.store_*` methods return `bool` in 4.4+. `JSON.parse()` returns error info — always check before accessing results. Verification required: test with missing file, malformed JSON, and valid file.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern; JSON format (not .tres); editable outside Godot
- Forbidden: hardcoded_resource_definitions (no inline const arrays of resource data)
- Guardrail: Performance budget 0.002ms per lookup; load time ~1-2ms total (30 resources)

---

## Acceptance Criteria

*From GDD `design/gdd/resource-system.md`:*

- [ ] **AC-1**: Given `res://data/resources.json` exists and is valid, when `load_from_file()` is called, then it returns `true` and all resources are cached
- [ ] **AC-2**: Given the registry is loaded, when `get_definition("wood")` is called, then it returns wood's full `_ResourceDefinition` struct (display_name, category, stack_limit, icon_path, and all optional fields present in the JSON)
- [ ] **AC-3**: Given `res://data/resources.json` is missing, when `load_from_file()` is called, then it returns `false` and logs a clear error message with the missing path
- [ ] **AC-4**: Given `res://data/resources.json` contains malformed JSON (syntax error), when `load_from_file()` is called, then it returns `false` and logs the parse error with line number
- [ ] **AC-5**: Given the JSON file has a `"version"` field, when loaded, then the version number is stored and accessible for migration checks

---

## Implementation Notes

*Derived from ADR-0002 Implementation Guidelines:*

Create `src/systems/resource_registry.gd` as an Autoload singleton named `ResourceRegistry`:

```gdscript
extends Node

const REGISTRY_PATH: String = "res://data/resources.json"

var _definitions: Dictionary = {}  # StringName -> _ResourceDefinition
var _registry_version: int = 0

func _ready() -> void:
    load_from_file(REGISTRY_PATH)

func load_from_file(path: String) -> bool:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:  # NULL-CHECK — NOT bool check (Godot 4.4+ breaking change)
		push_error("ResourceRegistry: Cannot open '%s'" % path)
        return false

    var json_text: String = file.get_as_text()
    var json: JSON = JSON.new()
    var parse_result: Error = json.parse(json_text)
    if parse_result != OK:
        push_error("ResourceRegistry: JSON parse error at line %d: %s" % [
            json.get_error_line(), json.get_error_message()])
        return false

    var data: Variant = json.get_data()
    if not data is Dictionary:
        push_error("ResourceRegistry: Root JSON element must be an object")
        return false

    _registry_version = int(data.get("version", 0))
    return _parse_resources(data.get("resources", []))
```

**_ResourceDefinition inner class** — define as a nested class within ResourceRegistry:

```gdscript
class _ResourceDefinition:
    var id: StringName
    var display_name: String
    var category: ResourceCategory  # enum
    var stack_limit: int
    var icon_path: String
    var subcategory: String = ""
    var weight: float = 0.0
    var base_value: int = 0
    var max_charge: float = 100.0
    var description: String = ""
    var tags: Array[String] = []
    var deprecated: bool = false
```

Also create the initial `res://data/resources.json` with at minimum: wood, stone, berry (one Verbrauchsgut, two Produktionswaren) so tests can run against real data.

Register `ResourceRegistry` as an Autoload in `project.godot` with name `ResourceRegistry`, loading before any scene.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Schema validation logic (`_validate_resource()`) — stub validation as pass-through here
- Story 003: `get_definition()`, `is_valid_id()`, `get_all_by_category()` public API methods
- Story 004: Category enum and category-based filtering
- Story 005: Deprecated resource handling and version migration

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Valid file loads successfully
  - Given: `res://data/resources.json` exists with valid structure (version + resources array)
  - When: `load_from_file("res://data/resources.json")` called
  - Then: returns `true`; `_definitions` has at least one entry; `_registry_version > 0`

- **AC-2**: get_definition returns full struct
  - Given: Registry loaded with wood entry (display_name:"Wood", category:"produktionsware", stack_limit:99)
  - When: `get_definition(&"wood")` called (stubbed in this story — implemented fully in Story 003)
  - Then: returned struct has display_name=="Wood", stack_limit==99
  - Edge cases: optional fields with defaults (weight defaults to 0.0 if not in JSON)

- **AC-3**: Missing file returns false
  - Given: path points to a non-existent file
  - When: `load_from_file("/nonexistent/path.json")` called
  - Then: returns `false`; `push_error()` called with path in message; `_definitions` remains empty

- **AC-4**: Malformed JSON returns false
  - Given: file contains `{ "version": 1, "resources": [{ "id": "wood", ` (truncated/invalid JSON)
  - When: `load_from_file()` called
  - Then: returns `false`; `push_error()` called with line number; no crash

- **AC-5**: Version field stored
  - Given: JSON has `"version": 2`
  - When: `load_from_file()` succeeds
  - Then: `_registry_version == 2`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/resource/registry_loading_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None (this is the first story; creates the ResourceRegistry Autoload skeleton)
- Unlocks: Story 002 (validation needs the file loading infrastructure), Story 003 (lookup API needs the cache)
