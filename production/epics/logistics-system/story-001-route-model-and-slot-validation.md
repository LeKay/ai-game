# Story 001: Route Model and Slot Validation

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-001`, `TR-logistics-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture
**ADR Decision Summary**: Route model with `route_type` enum (INPUT/OUTPUT), `LogisticsRoute` class with lifecycle states, slot validation in `create_route()` blocks duplicate carrier assignment to the same slot type.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — pure GDScript data model. No verification required.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Single gate placement validation via GridMap.validate_placement()
- Required: Visual pool pattern — recycled scene templates, registry owns all state
- Forbidden: Never use TileMap for rendering — always TileMapLayer

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] A `LogisticsRoute` class exists with fields: id, source_building_id, destination_building_id, npc_id, route_type (INPUT/OUTPUT), active, lifecycle_state (DRAFT/ACTIVE/PAUSED/DEACTIVATED), carrier_state, cargo, cargo_resource, remaining_ticks, wait_ticks
- [ ] Route factory `create()` sets lifecycle_state = ACTIVE, carrier_state = IDLE, active = true, npc_id assigned
- [ ] A building with `output_slots = 1` blocks creation of a second route with `route_type = OUTPUT` — returns failure and no route created
- [ ] A building with `input_slots = 1` blocks creation of a second route with `route_type = INPUT` on the destination building — returns failure and no route created
- [ ] Attempting to create a route where source and destination are the same building_id is blocked with a descriptive error message
- [ ] Three route types are supported via the `route_type` field: OUTPUT (fills output slot on source), INPUT (fills input slot on destination), and implicit Production→Production (same structure, different building pairing)

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**LogisticsRoute as top-level class_name**: This must be `class_name LogisticsRoute` in its own file (`logistics_route.gd`) so that `Array[LogisticsRoute]` compiles with static typing. This is NOT a Node — it's a pure data class.

**Route ID convention**: Use `StringName("route_" + npc)` as the default ID pattern. The NPC serves as the route's unique anchor since a single NPC serves one route at a time.

**Slot validation flow** (called from LogisticsSystem, NOT from the route class itself):
```
create_route(source_id, destination_id, npc_id, route_type):
    validate slot availability:
        if route_type == OUTPUT:
            check source building has free output_slots
        if route_type == INPUT:
            check destination building has free input_slots
    if no free slot → return FAILURE with reason string
    else → create route via LogisticsRoute.create(...)
```

**Lifecycle state enum**: DRAFT=0, ACTIVE=1, PAUSED=2, DEACTIVATED=3. These map directly to the route lifecycle table in the GDD.

**Carrier state enum**: IDLE=0, TRAVEL_TO_SOURCE=1, AT_SOURCE=2, WAITING_SOURCE=3, TRAVEL_TO_DESTINATION=4, AT_DESTINATION=5, WAITING_DESTINATION=6, RETURN_HOME=7. Maps to carrier state machine in Core Rules 5.

**Route deletion**: When a route is deleted, the slot on the source (for OUTPUT) or destination (for INPUT) is freed. This happens in LogisticsSystem, not the route class.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 002]: Carrier FSM execution loop, NPC state machine integration, travel time computation
- [Story 005]: Save/load persistence of routes

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**Route creation and lifecycle:**

- **AC-1**: Route creation via factory sets correct initial state
  - Given: No routes exist in LogisticsSystem
  - When: `LogisticsRoute.create(storage_id, lumber_camp_id, npc_1, RouteType.OUTPUT)` is called
  - Then: route.id = "route_npc_1", route.active = true, route.lifecycle_state = 1 (ACTIVE), route.carrier_state = 0 (IDLE), route.cargo = 0, route.cargo_resource = null
  - Edge cases: NPC ID as empty string should still create a route (validation is caller's responsibility)

- **AC-2**: Route factory creates all fields correctly
  - Given: source = "storage_A", dest = "lumber_camp_B", npc = "npc_7", type = OUTPUT
  - When: `LogisticsRoute.create(source, dest, npc, type)` is called
  - Then: All fields match — source_building_id = "storage_A", destination_building_id = "lumber_camp_B", npc_id = "npc_7", route_type = OUTPUT, active = true, lifecycle_state = ACTIVE, carrier_state = IDLE
  - Edge cases: StringName args should compare with `==` not `is`

**Slot validation:**

- **AC-3**: Duplicate OUTPUT slot assignment is blocked
  - Given: Building "lumber_camp" has output_slots = 1, one OUTPUT route already exists for it
  - When: A second create_route call tries to create another OUTPUT route on "lumber_camp"
  - Then: Returns FAILURE (not a route object), `get_active_routes().count()` remains 1, error message mentions "no free output slots"
  - Edge cases: If the first route is PAUSED or DEACTIVATED, the slot should still be counted as occupied (slot = route_type binding, not lifecycle-dependent)

- **AC-4**: Duplicate INPUT slot assignment is blocked
  - Given: Building "sawmill" has input_slots = 1, one INPUT route already exists for it
  - When: A second create_route call tries to create another INPUT route on "sawmill"
  - Then: Returns FAILURE, route count unchanged, error message mentions "no free input slots"
  - Edge cases: Same — inactive routes still occupy slots

- **AC-5**: Same building as source and destination is blocked
  - Given: Building "storage_A" exists
  - When: `create_route("storage_A", "storage_A", "npc_1", RouteType.OUTPUT)` is called
  - Then: Returns FAILURE, error message = "Source and destination cannot be the same building."
  - Edge cases: String comparison should be exact (case-sensitive, StringName equality)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/logistics/route_model_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: Story 002 (carrier FSM needs route model), Story 004 (building status needs route queries)
