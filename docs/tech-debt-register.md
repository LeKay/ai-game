# Tech Debt Register

Tracks advisory deviations from ADR/GDD requirements that were accepted at implementation
time and deferred for a future story. Each entry has an owner story and a resolution trigger.

---

## TDB-001 — NPCSystem: Manhattan distance computed inline instead of via GridMap.distance_between()

| Field | Value |
|-------|-------|
| **Logged** | 2026-06-02 |
| **Story** | npc-system/story-002-task-cycle-travel-work.md |
| **ADR** | ADR-0009 — Constraint: "Must delegate distance calculations to GridMap `distance_between()`" |
| **Location** | `src/gameplay/npc_system.gd` — `_compute_travel_ticks()` |
| **Description** | `_compute_travel_ticks()` uses inline Manhattan distance (`absi(dx) + absi(dy) × TICKS_PER_TILE`) instead of delegating to `GridMap.distance_between(a, b, "manhattan")`. Result is identical at VS scope (no obstacle pathfinding). Inline was chosen for test isolation — the integration test uses a `_BuildingStub` (RefCounted) that cannot provide a GridMap. |
| **Resolution trigger** | When GridMap integration is wired and NPCSystem subscribes to GridMap (post-VS), replace the inline with `_grid_system.distance_between(from, to, "manhattan")`. The injectable `_building_system` pattern is already in place — add `_grid_system: Object = null` alongside it. |
| **Risk** | LOW — inline and GridMap results are equivalent for axis-aligned Manhattan distance. Would diverge only if GridMap added weighted tiles or terrain cost modifiers. |
