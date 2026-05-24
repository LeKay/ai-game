# Story 005: Architect Mode

> **Epic**: Player Character System
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration — ADR-0007
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: `TR-player-006` (Architect Mode lock: after first NPC assigned, manual gathering is permanently locked out)

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: `ArchitectMode` class with `locked: bool = false`. One-way, irreversible transition within a session. `on_npc_assigned(npc_id, building_id)` sets locked = true and emits `architect_mode_triggered()` signal. `can_gather(resource_id)` returns false when locked for gathering actions. `get_blocked_actions()` returns `[CHOP, MINE, BERRIES, FORAGE]` when locked. Player Character System subscribes to NPC System's `on_npc_assigned(npc_id, building_id)` signal. After transition, the player can still: eat food, transport resources, interact with UI, and place/demolish buildings. Only manual gathering (tile-click harvesting) is blocked.

**Engine**: Godot 4.6 | **Risk**: HIGH (verification required: signal subscription to NPC System)
**Engine Notes**: Signal connection to NPC System's `on_npc_assigned` signal — verify that cross-Autoload signal connections work correctly in Godot 4.6. The NPC System ADR-0009 must define this signal with signature `on_npc_assigned(npc_id: StringName, building_id: StringName)`.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/player-character-system.md`, scoped to this story:*

- [ ] **AC (Architect)** GIVEN the first NPC is assigned to a building WHEN `on_npc_assigned` signal fires THEN manual gathering actions (Pick Berries, Chop Tree, Mine Stone, Forage) are permanently locked out with tooltip: "Your workers handle this now."
- [ ] **AC (Architect)** The transition is one-way and irreversible — `locked` never returns to false within a session
- [ ] **AC (Architect)** Non-gathering actions remain available after architect mode: food consumption, transport, building interaction

---

## Implementation Notes

*Derived from ADR-0007 Implementation Guidelines:*

**ArchitectMode class structure:**
```
class ArchitectMode:
    - locked: bool = false

    Signal: architect_mode_triggered()

    Methods:
    - on_npc_assigned(npc_id: StringName, building_id: StringName) -> void
    - can_gather(resource_id: StringName) -> bool  # false if locked
    - get_blocked_actions() -> Array[ActionType]     # [CHOP, MINE, BERRIES, FORAGE] when locked

    on_npc_assigned():
        locked = true
        architect_mode_triggered.emit()
```

**Transition logic:**
```
on_npc_assigned(npc_id, building_id):
    if locked:
        return  # already locked, no-op
    locked = true
    architect_mode_triggered.emit()
    # Notify HUD to update available actions
```

**Integration with ActionSlot (from ADR-0007):**
```
StartResult:
    ...
    ARCHITECT_LOCKED  # architect mode, this is a gathering action
```

When `ActionSlot.try_start()` is called, check:
1. Is slot free? → if no, BLOCKED_SLOT
2. Is energy sufficient (or at 0)? → if no, INSUFFICIENT_ENERGY
3. Is architect mode locked AND is this a gathering action? → if yes, ARCHITECT_LOCKED
4. Is a tool required and no tool available? → if yes, TOOL_REQUIRED
5. All checks pass → SUCCESS

**Gathering action types:** `[CHOP, MINE, BERRIES, FORAGE]`
**Non-gathering actions (still available):** `CRAFT_TOOL`, `EAT_FOOD`, `TRANSPORT`, `BUILDING_PLACEMENT`

**Tooltip text:** "Your workers handle this now."

**HUD integration:** On `architect_mode_triggered()` signal, the HUD should hide gathering-related UI elements and update action availability.

**Signal subscription (in PlayerCharacter._enter_tree()):**
```
# Subscribe to NPC System signal
# Signal contract: npc_id: StringName, building_id: StringName
# Safe to connect before ADR-0009 is implemented — unconnected signals are no-ops in Godot
on_npc_assigned.connect(_on_npc_assigned)
```

**Signals to emit:**
- `architect_mode_triggered()` — fired once when transition occurs

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: EnergyPool (no dependency)
- [Story 002]: Action dispatch (this story adds the ARCHITECT_LOCKED result; the dispatch mechanism itself is Story 002)
- [Story 003]: Drag-and-drop transport (not affected by architect mode — transport remains available)
- [Story 004]: Depletion and food refill (food consumption remains available in architect mode, but is in Story 004)

---

## QA Test Cases

**AC (Architect)**: NPC assignment locks manual gathering
  - Given: ArchitectMode.locked = false, player clicks berry tile
  - When: on_npc_assigned(npc_id="npc_1", building_id="building_1")
  - Then: locked = true, architect_mode_triggered signal emitted, ActionSlot.try_start(BERRIES) returns ARCHITECT_LOCKED
  - Edge cases: second NPC assignment → on_npc_assigned fires again, but locked is already true → no-op; different NPC/buidling combinations → same result, all trigger the same transition

**AC (Architect)**: Transition is one-way and irreversible
  - Given: ArchitectMode.locked = true
  - When: any signal, any method call (no public method to unlock)
  - Then: locked remains true for the entire session lifetime
  - Edge cases: no unlock method exists in ArchitectMode class; if a reset is needed, it requires creating a new ArchitectMode instance (which only happens on project reload or save/load)

**AC (Architect)**: Non-gathering actions remain available
  - Given: ArchitectMode.locked = true
  - When: player attempts eat food, transport drag, building placement
  - Then: all succeed normally (no ARCHITECT_LOCKED check applies to these action types)
  - Edge cases: eat food at 0 energy while in architect mode → works (food restores energy); transport drag while architect mode → works (resource transport is not gathering); craft tool while architect mode → works (CRAFT_TOOL is not in blocked list)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/architect_mode_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (ActionSlot must have ARCHITECT_LOCKED StartResult)
- Unlocks: None directly — architect mode enables NPC System stories (NPCs become meaningful only after architect mode transition)
