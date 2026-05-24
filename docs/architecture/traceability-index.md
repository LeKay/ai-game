# Architecture Traceability Index

> Last Updated: 2026-05-14
> Source: /architecture-review (full)
> Coverage: 33 / 56 requirements covered (59%)

## How to read this index

| Column | Meaning |
|--------|---------|
| TR-ID | Stable requirement ID — never changes; see `tr-registry.yaml` |
| GDD | Source design document |
| System | Game system name |
| Requirement | What must be architecturally decided |
| ADR | Decision record covering this requirement |
| Status | Covered / Partial / Gap |

---

## Full Traceability Matrix

### Foundation Layer

| TR-ID | GDD | System | Requirement | ADR | Status |
|-------|-----|--------|-------------|-----|--------|
| TR-tick-001 | tick-system.md | Tick | 1000-tick/day float accumulator | ADR-0001 | Covered |
| TR-tick-002 | tick-system.md | Tick | 3 speed modes (0.5x/1x/2x) + pause state | ADR-0001 | Covered |
| TR-tick-003 | tick-system.md | Tick | Tick signal emission to all subscribers per tick | ADR-0001 | Covered |
| TR-tick-004 | tick-system.md | Tick | Manual action tick advancement | ADR-0001 | Covered |
| TR-tick-005 | tick-system.md | Tick | Day-transition event + auto-pause | ADR-0001 | Covered |
| TR-tick-006 | tick-system.md | Tick | Determinism: same seed → same tick sequence | ADR-0001 | Covered |
| TR-res-001 | resource-system.md | Resource | JSON data registry loaded at startup | ADR-0002 | Covered |
| TR-res-002 | resource-system.md | Resource | Resource definition: id/name/category/stack_limit/weight/base_value/icons | ADR-0002 | Covered |
| TR-res-003 | resource-system.md | Resource | Schema validation on load (fail fast) | ADR-0002 | Covered |
| TR-res-004 | resource-system.md | Resource | O(1) id-keyed runtime lookup | ADR-0002 | Covered |
| TR-res-005 | resource-system.md | Resource | Two categories: Consumables / Production Goods | ADR-0002 | Covered |
| TR-input-001 | input-system.md | Input | Unified action mapping: keyboard+mouse + gamepad | ADR-0003 | Covered |
| TR-input-002 | input-system.md | Input | Input context switching (WORLD_ACTIVE/UI_ACTIVE/PAUSED) | ADR-0003 | Covered |
| TR-input-003 | input-system.md | Input | Context transition on UI open/close | ADR-0003 | Covered |
| TR-input-004 | input-system.md | Input | Input debouncing for rapid presses | ADR-0003 | Covered |
| TR-input-005 | input-system.md | Input | Mouse position → world tile coordinate conversion | ADR-0003 | Partial — Delegated to CameraController; no Camera ADR yet |

### Core Layer

| TR-ID | GDD | System | Requirement | ADR | Status |
|-------|-----|--------|-------------|-----|--------|
| TR-player-001 | player-character-system.md | Player | Energy pool (0–100) with tick-based drain | ADR-0007 | Covered |
| TR-player-002 | player-character-system.md | Player | Manual action dispatch (forage/pick/craft/chop/mine/transport) with energy cost | ADR-0007 | Covered |
| TR-player-003 | player-character-system.md | Player | Drag-and-drop transport (carry item from tile to storage) | ADR-0007 | Covered |
| TR-player-004 | player-character-system.md | Player | Energy depletion: 2x tick cost + ceil(output x 0.5) min 1 at 0 energy | ADR-0007 | Covered |
| TR-player-005 | player-character-system.md | Player | Food-to-energy refill on food consumption | ADR-0007 | Covered |
| TR-player-006 | player-character-system.md | Player | Architect Mode lock after first NPC assigned | ADR-0007 | Covered |
| TR-grid-001 | grid-map-system.md | Grid | 30x30 tile grid, 3-layer data model (Terrain/Resource/Building) | ADR-0004 | Covered |
| TR-grid-002 | grid-map-system.md | Grid | TileMapLayer rendering (TileMap deprecated — must not use) | ADR-0004 | Covered |
| TR-grid-003 | grid-map-system.md | Grid | Perlin noise procedural terrain generation at world init | ADR-0004 | Covered |
| TR-grid-004 | grid-map-system.md | Grid | validate_placement gate (checks all 3 layers before any placement) | ADR-0004 | Covered |
| TR-grid-005 | grid-map-system.md | Grid | Manhattan + Euclidean distance functions | ADR-0004 | Covered |
| TR-grid-006 | grid-map-system.md | Grid | World-space ↔ tile-coordinate conversion | ADR-0004 | Covered |
| TR-cam-001 | camera-system.md | Camera | Pan: WASD/arrows/middle-drag/edge-scroll | — | Gap — deferred (low risk) |
| TR-cam-002 | camera-system.md | Camera | Zoom 0.85–2.0 anchored to mouse position | — | Gap — deferred (low risk) |
| TR-cam-003 | camera-system.md | Camera | Boundary clamping (cannot scroll outside world bounds) | — | Gap — deferred (low risk) |
| TR-cam-004 | camera-system.md | Camera | Screen → tile coordinate conversion (click → tile) | — | Gap — deferred (low risk) |
| TR-cam-005 | camera-system.md | Camera | Fit-to-view on R key | — | Gap — deferred (low risk) |
| TR-inv-001 | inventory-storage-system.md | Inventory | InventoryContainer with first-fit stacking algorithm | ADR-0005 | Covered |
| TR-inv-002 | inventory-storage-system.md | Inventory | Resource state machine: DROPPED → IN_TRANSIT → STORED/LOST | ADR-0005 | Covered |
| TR-inv-003 | inventory-storage-system.md | Inventory | Transport energy/tick cost formulas | ADR-0005 | Covered |
| TR-inv-004 | inventory-storage-system.md | Inventory | Hunger consumption priority: lowest-quantity storage bin first | ADR-0005 | Covered |
| TR-inv-005 | inventory-storage-system.md | Inventory | Storage Area (50 slots) + Storage Building (150 slots) | ADR-0005 | Covered |
| TR-inv-006 | inventory-storage-system.md | Inventory | Items only consumed from STORED state | ADR-0005 | Covered |

### Feature Layer

| TR-ID | GDD | System | Requirement | ADR | Status |
|-------|-----|--------|-------------|-----|--------|
| TR-build-001 | building-system.md | Building | 1-tile footprint placement with cost deduction | ADR-0008 | Covered |
| TR-build-002 | building-system.md | Building | 4 building types for Vertical Slice: Storage Area, Storage Building, Residential House, Lumber Camp | ADR-0008 | Covered |
| TR-build-003 | building-system.md | Building | Tick-based build time progression | ADR-0008 | Covered |
| TR-build-004 | building-system.md | Building | Production cycle tick advancement | ADR-0008 | Covered — **updated**: output now buffered for carrier pickup via `production_output_ready`; deposit handled by Transportation System carrier NPCs, not Building System directly |
| TR-build-005 | building-system.md | Building | NPC assignment slots per building | ADR-0008 | Covered |
| TR-transport-001 | building-system.md, ux/building-detail.md | Transportation | Carrier NPC assignment for input/output wares per building | — | Gap — Transportation System spec pending (`design/ux/transportation-management.md`) |
| TR-transport-002 | building-system.md | Transportation | Carrier travel time formula: `carrier_travel_ticks = floor(distance × ticks_per_tile)` | ADR-0008 (partial) | Partial — formula defined in ADR-0008/GDD; carrier scheduling ADR pending |
| TR-transport-003 | ux/building-detail.md | Transportation | Transportation Management UI for configuring carrier routes | — | Gap — UI spec pending (`design/ux/transportation-management.md`) |
| TR-npc-001 | npc-system.md | NPC | NPC data: id/name/state/assignment/current_task | ADR-0009 | Covered |
| TR-npc-002 | npc-system.md | NPC | State machine: IDLE→TRAVEL→WORK→DEPOSIT→RETURN | ADR-0009 | Covered |
| TR-npc-003 | npc-system.md | NPC | Manhattan-distance movement (abstract, no sprites for VS) | ADR-0009 | Covered |
| TR-npc-004 | npc-system.md | NPC | Recruitment: 2 NPCs per Residential House | ADR-0009 | Covered |
| TR-npc-005 | npc-system.md | NPC | Task assignment with storage selection | ADR-0009 | Covered |
| TR-npc-006 | npc-system.md | NPC | Demolition disconnects NPC assignment | ADR-0009 | Covered |
| TR-hunger-001 | hunger-system.md | Hunger | Daily consumption: 1 food unit per NPC per day | ADR-0010 | Covered |
| TR-hunger-002 | hunger-system.md | Hunger | Hunger debuff: 2x tick cost for travel/work | ADR-0010 | Covered |
| TR-hunger-003 | hunger-system.md | Hunger | Combined debuff: hunger x energy depletion = 4x tick cost | ADR-0010 | Covered |
| TR-hunger-004 | hunger-system.md | Hunger | Food unit conversion: berry=1, bread=2 | ADR-0010 | Covered |

### Presentation Layer

| TR-ID | GDD | System | Requirement | ADR | Status |
|-------|-----|--------|-------------|-----|--------|
| TR-hud-001 | hud-system.md | HUD | Real-time display: energy, day, time-of-day, resource counts | — | Gap — deferred (visual) |
| TR-hud-002 | hud-system.md | HUD | Days-of-food-remaining calculation + display | — | Gap — deferred (visual) |
| TR-hud-003 | hud-system.md | HUD | Notification system (building complete, NPC hungry, storage full) | — | Gap — deferred (visual) |
| TR-hud-004 | hud-system.md | HUD | Time controls in HUD (speed buttons, pause) | — | Gap — deferred (visual) |
| TR-hud-005 | hud-system.md | HUD | Dual-focus aware UI (mouse + keyboard/gamepad) | ADR-0003 | Partial — ADR-0003 covers input gating; HUD implementation needs its own dual-focus ADR |

---

## Coverage Summary

| Layer | Total | Covered | Partial | Gap |
|-------|-------|---------|---------|-----|
| Foundation | 16 | 15 | 1 | 0 |
| Core | 22 | 18 | 0 | 4 |
| Feature | 16 | 16 | 0 | 0 |
| Presentation | 5 | 0 | 1 | 4 |
| **Total** | **59** | **49 (83%)** | **2 (3%)** | **8 (14%)** |

---

## Resolved Conflicts

| Date | ADRs | Conflict | Resolution |
|------|------|----------|------------|
| 2026-05-14 | ADR-0008 ↔ ADR-0009 | `production_output_ready` signal referenced by NPCSystem but not defined in BuildingRegistry | Signal added to ADR-0008 BuildingRegistry section |
| 2026-05-14 | ADR-0007 ↔ ADR-0008 | BuildingRegistry called `PlayerCharacter.consume_energy()` not in PlayerCharacter API | `consume_energy(amount: int) -> bool` added to ADR-0007 public API |
| 2026-05-14 | ADR-0004 ↔ ADR-0009 | NPCSystem called `GridMap.distance_between(a, b, metric)` not defined | Unified `distance_between()` method added to ADR-0004 GridMap |

---

## Priority Fix List

### Foundation layer — 0 gaps

All foundation requirements have ADR coverage. The only action needed is accepting all 6 ADRs (currently Proposed).

### Core layer gaps

| TR-IDs | System | Priority | Action |
|--------|--------|----------|--------|
| TR-cam-001…005 | Camera | Low — deferred | No ADR needed before implementation; Camera2D API is stable. ADR-0003 delegates mouse→tile conversion here. |

### Feature layer — 0 gaps

All feature layer requirements have ADR coverage (ADR-0007 through ADR-0010). Accept these Proposed ADRs when ready.

### Presentation layer gaps

| TR-IDs | System | Priority | Action |
|--------|--------|----------|--------|
| TR-hud-001…004 | HUD display | Medium | Deferred until Vertical Slice implementation begins |
| TR-hud-005 | HUD dual-focus | Medium | ADR-0003 covers input gating; create HUD ADR for UI layout when starting HUD work |

---

## History

| Date | Coverage | ADRs | Event |
|------|----------|------|-------|
| 2026-05-13 | 42% (25/59) | 6 (all Proposed) | Initial architecture review — Foundation ADRs complete |
| 2026-05-14 | 83% (49/59) | 10 (6 Proposed Foundation + 4 Proposed Core/Feature) | Conflict fixes applied; ADR-0007 through ADR-0010 written; integration conflicts resolved |
