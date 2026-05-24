# Story 001: NPC Identity and Recruitment

> **Epic**: NPC System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic — ADR-0009
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/npc-system.md`
**Requirements**:
- `TR-npc-001` (NPC data model: id, name, state, assignment, current_task)
- `TR-npc-004` (Recruitment: up to 2 NPCs per Residential House; first spawns on completion, second after 1 day)

**ADR Governing Implementation**: ADR-0009: NPC State Machine and Movement
**ADR Decision Summary**: NPCSystem is an Autoload singleton (`res://src/gameplay/npc_system.gd`). `NPCInstance` is a nested class tracking npc_id, position, home_base, state (TaskState enum), assignment data, travel progress, and work cycle status. `recruit_npc(home_base: Vector2i) -> StringName` creates an IDLE NPC at the house tile. `all_npcs: Dictionary[StringName, NPCInstance]` is the central registry.

**Engine**: Godot 4.6 | **Risk**: LOW (pure GDScript data, stable APIs — `_process`, `Engine.get_singleton()`)
**Engine Notes**: No post-cutoff APIs used. `StringName` for keys, `Dictionary` insertion order is deterministic in Godot 4.x. Nested `class` (not `class_name`) — acceptable at VS scope.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/npc-system.md`, scoped to this story:*

- [ ] **AC-1** GIVEN an unoccupied Residential House WITH available slots WHEN the player clicks the "Recruit" button THEN a new NPC is created in IDLE state at the house tile position, the house worker counter updates (e.g., from 0/2 to 1/2), and `npc_recruited` signal fires
- [ ] **AC-2** GIVEN a house already has 1 NPC recruited WHEN 1000 ticks elapse after the first recruitment THEN the second slot becomes available (the "Recruit" affordance appears), and `npc_spawn_delay_ticks` tuning knob controls this delay
- [ ] **AC-3** GIVEN a house has 2 NPCs already WHEN the player attempts to recruit a third THEN recruitment is blocked, no NPC is created, and the house counter remains at 2/2
- [ ] **AC-4** GIVEN an NPC is created via `recruit_npc(home_base)` THEN the NPCInstance has: state = IDLE, position = home_base (Vector2i), home_base set, all assignment fields null, travel_progress = 0, travel_ticks_total = 0

---

## Implementation Notes

*Derived from ADR-0009 Implementation Guidelines:*

**NPCInstance structure (from ADR-0009):**
```
class NPCInstance:
    - npc_id: StringName
    - position: Vector2i  # current tile coordinates
    - home_base: Vector2i  # residential house tile (set at recruitment)
    - state: TaskState  # IDLE, TRAVEL_TO_BUILDING, WORK_AT_BUILDING, ...
    - assigned_building_id: StringName?
    - assigned_storage_id: StringName?
    - travel_progress: int  # accumulated ticks during current travel segment
    - travel_destination: Vector2i?
    - travel_ticks_total: int
    - work_cycle_complete: bool
```

**recruit_npc() implementation (from ADR-0009):**
```
func recruit_npc(home_base: Vector2i) -> StringName:
    # Generate unique ID
    var npc_id := StringName("npc_%d" % npc_counter)
    npc_counter += 1

    # Create NPCInstance
    var npc := NPCInstance.new()
    npc.npc_id = npc_id
    npc.position = home_base
    npc.home_base = home_base
    npc.state = TaskState.IDLE
    npc.travel_progress = 0
    npc.travel_ticks_total = 0

    # Register in central registry
    all_npcs[npc_id] = npc

    # Emit signal
    npc_recruited.emit(npc_id, home_base)

    return npc_id
```

**House capacity enforcement (from GDD Rule 7):**
- Each Residential House: max 2 NPCs
- No global population cap beyond housing capacity
- The Building System owns NPC spawn triggering (triggers `NPCSystem.recruit_npc()` via signal)
- Second slot unlocks after `npc_spawn_delay_ticks` (default 1000) from first recruitment

**Tuning knob:**
```
const NPC_SPAWN_DELAY_TICKS: int = 1000  # ticks before second slot unlocks
const NPC_CAPACITY_PER_HOUSE: int = 2   # fixed at 2 for VS
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Task cycle execution (travel, work, deposit — NPC recruited but not yet assigned)
- Story 004: Disconnection on demolition (NPC was just recruited)
- Story 005: UI for recruitment (only the logic; the "Recruit" affordance on the house is a Building System concern, the UI wiring is Story 005)

---

## QA Test Cases

**AC-1**: NPC recruitment creates IDLE NPC at house tile
  - Given: Residential House at tile (10, 10), 0/2 workers, player clicks "Recruit"
  - When: BuildingSystem emits recruitment signal → NPCSystem.recruit_npc(Vector2i(10, 10))
  - Then: NPCInstance created with state = IDLE, position = (10,10), home_base = (10,10), npc_id assigned, all_npcs dictionary contains exactly 1 entry, npc_recruited signal emitted with (npc_id, Vector2i(10,10))
  - Edge cases: multiple simultaneous recruitments → each gets unique ID; NPCInstance.travel_progress = 0; NPCInstance.assigned_building_id = null

**AC-2**: Second slot unlocks after 1000 ticks
  - Given: 1 NPC recruited at house (10,10), first recruitment at tick 500
  - When: ticks_advanced(1000) fires (tick reaches 1500)
  - Then: second slot becomes available — NPCSystem.recruit_npc() succeeds; building_slot_unlocked or equivalent internal state reflects availability
  - Edge cases: recruitment attempted at tick 999 → blocked (second slot not yet available); tick_delay is a tuning knob — changing NPC_SPAWN_DELAY_TICKS to 0 makes both slots immediately available; changing to 5000 delays second slot to 5000 ticks

**AC-3**: Max 2 NPCs per house enforced
  - Given: 2 NPCs recruited at same house, both in IDLE state
  - When: recruit_npc() called again for same house
  - Then: recruitment blocked, no new NPC created, all_npcs dictionary unchanged, returns appropriate error result
  - Edge cases: if one NPC is reassigned to a building (state != IDLE), the slot is occupied but the capacity is still 2/2; capacity is a hard ceiling, not just IDLE count

**AC-4**: NPCInstance fields correctly initialized
  - Given: recruit_npc(Vector2i(5, 5)) is called
  - When: NPCInstance is created
  - Then: npc_id is unique StringName, position = (5,5), home_base = (5,5), state = TaskState.IDLE, assigned_building_id = null, assigned_storage_id = null, travel_progress = 0, travel_ticks_total = 0, work_cycle_complete = false
  - Edge cases: all fields verified immediately after creation, no deferred initialization

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/npc_system/npc_identity_recruitment_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None — NPCSystem can be tested independently with mock dependencies
- Unlocks: Story 002 (task cycle requires NPCs to exist first)
