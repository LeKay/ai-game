# Story 005: Save/Load for Logistics

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-008`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture, ADR-0006: Save and Load Format and Serialisation Order
**ADR Decision Summary**: Routes serialized as `Dictionary` via `serialize()` method in LogisticsSystem. Each route stores id, source_building_id, destination_building_id, npc_id, route_type, active, lifecycle_state, carrier_state, cargo, cargo_resource, remaining_ticks, wait_ticks. Deserialized with `Dictionary.get(key, default)` for safe handling of older saves. Load order: Logistics System loads after Buildings, before TickSystem resumes.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None. JSON serialization via `JSON.stringify()` / `JSON.parse()`. `FileAccess.store_string()` returns bool in Godot 4.4+ — check return value. Use `.get()` with defaults on deserialization.

**Control Manifest Rules (Foundation Layer)**:
- Required: JSON save format with schema versioning, namespaced system data
- Required: Load order invariant: ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick
- Required: Null-check Autoload references via `Engine.get_singleton()`
- Required: deserialize() must use `.get()` with defaults — never direct `[key]` access
- Forbidden: Never use scene-instanced Autoloads — Foundation systems must be project-level

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] `LogisticsSystem.serialize()` returns a `Dictionary` with key "logistics_routes" containing an array of route dictionaries, each with: id, source_building_id, destination_building_id, npc_id, route_type, active, lifecycle_state, carrier_state, cargo, cargo_resource, remaining_ticks, wait_ticks
- [ ] `LogisticsSystem.deserialize()` loads routes from saved data using `.get()` with defaults — missing keys use safe defaults (active=true, lifecycle_state=DEACTIVATED, carrier_state=IDLE, cargo=0, remaining_ticks=0, wait_ticks=0)
- [ ] A carrier saved during TRAVEL_TO_DESTINATION with `remaining_ticks = 30` resumes travel from its saved position with `remaining_ticks = 30` after game reload
- [ ] A deactivated route (DEACTIVATED lifecycle_state) loads as inactive, carrier_state = IDLE, and does not start execution on load
- [ ] Route data survives save/load round-trip without loss: all fields preserved exactly

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**Serialization** (from ADR-0011):
```
func serialize() -> Dictionary:
    var routes = []
    for route in _active_routes:
        routes.append({
            "id": route.id,
            "source_building_id": route.source_building_id,
            "destination_building_id": route.destination_building_id,
            "npc_id": route.npc_id,
            "route_type": route.route_type,
            "active": route.active,
            "lifecycle_state": route.lifecycle_state,
            "cargo_resource": route.cargo_resource,
            "cargo": route.cargo,
            "remaining_ticks": route.remaining_ticks,
            "wait_ticks": route.wait_ticks,
        })
    return {"logistics_routes": routes}
```

**Deserialization** (from ADR-0011):
```
func deserialize(data: Dictionary) -> void:
    var routes_data = data.get("logistics_routes", [])
    for route_data in routes_data:
        var route = LogisticsRoute.create(
            route_data.get("source_building_id"),
            route_data.get("destination_building_id"),
            route_data.get("npc_id"),
            route_data.get("route_type", RouteType.OUTPUT))
        route.id = route_data.get("id", "route_" + route.npc_id)
        route.active = route_data.get("active", true)
        route.lifecycle_state = route_data.get("lifecycle_state", 3)  # DEACTIVATED
        route.carrier_state = route_data.get("carrier_state", 0)     # IDLE
        route.cargo = route_data.get("cargo", 0)
        route.cargo_resource = route_data.get("cargo_resource")
        route.remaining_ticks = route_data.get("remaining_ticks", 0)
        route.wait_ticks = route_data.get("wait_ticks", 0)
        _active_routes.append(route)
```

**Critical deserialization note**: Deactivated routes load with `lifecycle_state = 3 (DEACTIVATED)`, `active = false`, `carrier_state = IDLE`. These routes must NOT start execution on load — they sit in the route list waiting for player reconfiguration. Only ACTIVE routes begin carrier simulation.

**Load order**: Logistics System deserializes after BuildingSystem (which must have all buildings present for route source/destination references) and before TickSystem resumes (so tick simulation doesn't start until all routes are loaded).

**Schema versioning**: Per ADR-0006, add `"logistics_schema_version": 1` to the serialize output and check on deserialize. This allows future migrations if the route data model changes.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Route model (route serialization fields are defined here, but the route class itself is in Story 001)
- [Story 002]: Carrier FSM (save/load preserves state, but FSM logic is in Story 002)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**Serialization:**

- **AC-1**: Active route serializes all fields
  - Given: Route with id="route_1", source="storage_A", dest="lumber_B", npc="npc_1", type=OUTPUT, active=true, lifecycle=ACTIVE(1), carrier=TRAVEL_TO_DESTINATION(4), cargo=3, cargo_resource="plank", remaining_ticks=25, wait_ticks=0
  - When: `LogisticsSystem.serialize()` is called
  - Then: Result["logistics_routes"][0] contains all fields with exact values
  - Edge cases: cargo_resource can be null (empty-handed carrier) — null must be preserved, not omitted

**Deserialization with defaults:**

- **AC-2**: Missing keys use safe defaults
  - Given: Old save data with only {"source_building_id": "storage_A", "destination_building_id": "lumber_B", "npc_id": "npc_1"} (missing route_type, lifecycle_state, cargo, remaining_ticks, wait_ticks)
  - When: `LogisticsSystem.deserialize(older_save_data)` is called
  - Then: route.route_type = RouteType.OUTPUT (default), lifecycle_state = 3 (DEACTIVATED), cargo = 0, remaining_ticks = 0, wait_ticks = 0, id = "route_npc_1" (auto-generated)
  - Edge cases: Missing "active" key → defaults to true (route is created but inactive due to lifecycle_state = DEACTIVATED)

**Round-trip preservation:**

- **AC-3**: Save/load round-trip preserves carrier state and remaining ticks
  - Given: Active route, carrier in TRAVEL_TO_DESTINATION, remaining_ticks = 30, cargo = 1
  - When: serialize → deserialize (new instance)
  - Then: route.carrier_state = TRAVEL_TO_DESTINATION(4), route.remaining_ticks = 30, route.active = true, route.lifecycle_state = ACTIVE(1)
  - Edge cases: After deserialization, tick processing must resume normally — carrier should continue decrementing remaining_ticks from 30, not reset to full travel time

- **AC-4**: Deactivated route stays inactive after load
  - Given: Route with lifecycle_state = DEACTIVATED(3), active = false, carrier_state = IDLE(0)
  - When: serialize → deserialize
  - Then: route.active = false, route.lifecycle_state = 3, route.carrier_state = 0
  - Edge cases: The route must NOT trigger carrier simulation on load — it sits in the route list without executing

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/logistics/save_load_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (route model fields), Story 002 (carrier states being serialized)
- Unlocks: None (independent feature)
