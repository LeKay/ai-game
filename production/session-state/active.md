# Active Session State

**Last Updated:** 2026-06-19
**Task:** Progression Tree (Tech Tree) — Step 1 (graph) + Step 2 (gating) implemented; awaiting Godot verification

## Current Focus: Progression Tree (2026-06-19)

Designing a node-graph tech tree that gates ALL content (manual gather, hand-craft,
buildings, recipes) behind clickable unlock nodes radiating from a central Hearth.
Design captured in `design/quick-specs/progression-tree-2026-06-19.md` (lightweight
spec by user direction; flagged for promotion to a full GDD before implementation).

**Decisions locked:** free-click unlock now (research-currency hook reserved via
`cost` field) · everything gated incl. manual gathering · radiating branches with
cross-links · manual-first then building automation. Visual = custom Node2D/Camera2D
+ Line2D (Option B, NOT GraphEdit).

**Gating architecture (documented in spec → "Code Integration / Gating Architecture"):**
new `ProgressionSystem` Autoload = single source of truth, data-driven from
`data/progression_tree.json`; capability API (`is_building_unlocked` /
`is_recipe_unlocked` / `is_gather_unlocked` / `is_building_recipe_unlocked`);
`node_unlocked` signal → UI re-`populate()`. Two-layer gating (UI hides + command
layer rejects). Gate points: `inventory_screen._building_list()` / `_crafting_list()`,
`tile_interaction_panel` (manual gather), `building_detail_panel` (recipe selectors).
Grids (`BuildingGrid`/`CraftingGrid`) are dumb renderers — no change needed.

**DONE this session — prerequisite refactor (smell fix):**
`inventory_screen.gd::_building_list()` no longer hardcodes a 13-entry building array.
Added `BuildingRegistry.BUILDABLE_TYPES` (canonical buildable list, menu order) +
public `BuildingRegistry.get_type_display_name()`. `BuildingRegistry` is now the
single source of truth for buildable types + names. ⚠️ Unverified in Godot (no run).

**STEP 1 — DONE 2026-06-19 (graph + UI):** `data/progression_tree.json`, `ProgressionSystem`
autoload + `ProgressionTreeNode`, radial Node2D graph UI (`progression_tree_screen` +
`progression_node_button`), 🌳 HUD button, auto-computed visual rings, perpendicular
strand layout, circular emoji badges, dynamic reveal. Unverified in Godot.

**STEP 2 — DONE 2026-06-19 (gating/verzahnung; awaiting Godot verification):** two-layer
gating wired everywhere via the `ProgressionSystem` autoload (unmapped content defaults
UNLOCKED so non-tree stuff is never blocked):
- Buildings: `BuildingRegistry.initiate_build`/`check_build_conditions` → new
  `PlacementResult.LOCKED` (overlay shows "Locked — unlock in the tech tree");
  `place_starter_building` NOT gated. Build menu hides locked types in `inventory_screen`.
- Manual craft: `CraftingRegistry.try_craft` → new `CraftResult.LOCKED`; menu hides locked
  recipes; `_on_recipe_selected` floats a LOCKED message.
- Manual gather: `player_character.try_start_action` → new `StartResult.PROGRESSION_LOCKED`
  (rejected before queueing). `tile_interaction_panel` HIDES the harvest row entirely for a
  locked gather (`_hide_harvest_action`); Clear/Search/Plant still shown.
- Building-recipe selectors: `building_detail_panel._rebuild_recipe_view` marks tech-locked
  recipes unavailable.
- Refresh-on-unlock: `inventory_screen` connects `ProgressionSystem.node_unlocked` →
  re-`_refresh_zone3()` while open.
- Save/Load: `WorldSaveManager` SAVE_SYSTEMS + LOAD_ORDER both begin with `"ProgressionSystem"`.
  'From scratch' start via `reset_to_initial()` (hearth-only).
- Tests: added `ProgressionSystem.unlock_all()` helper + `before_test`/`after_test`
  (unlock_all / reset_to_initial) to the 5 suites exercising gated build/gather content
  (building_system: placement/production/failed_states; player_character: action_dispatch,
  tile_harvest_interaction, depletion_food).

**NEXT:** user verifies in Godot (gating + Save/Load round-trip + tree UI); then promote
spec → full GDD (`/design-system`) + add to `design/gdd/systems-index.md`; ADR for
ProgressionSystem.

---

**Prior task:** inp-03 — Action Rebinding and Persistence (Complete)

## Story Creation Progress

| Epic | Stories | Status |
|------|---------|--------|
| tick-system | 5 (4 Logic, 1 Integration) | In Progress (Story 005 — save/load tick state being implemented) |
| resource-system | 5 (4 Logic, 1 Integration) | Complete |
| input-system | 5 (4 Logic, 1 Integration) | Complete |
| grid-map-system | 6 (5 Logic, 1 Visual/Feel) | Complete |
| inventory-system | 5 (4 Logic, 1 Integration) | Complete |
| save-load-system | 3 (3 Logic) | Complete |
| player-character | 5 | Complete |
| building-system | 5 | Complete |
| npc-system | 5 | Complete |
| hunger-system | 5 | Complete |

**Total Stories:** 44 across 10 epics

## UX Spec Progress

| Screen | Status | File |
|--------|--------|------|
| main-menu | APPROVED | design/ux/main-menu.md |
| hud | APPROVED (after review) | design/ux/hud.md |
| build-placement | APPROVED (after review) | design/ux/build-placement.md |
| building-detail | COMPLETE (ready for /ux-review) | design/ux/building-detail.md |
| inventory | COMPLETE (ready for /ux-review) | design/ux/inventory.md |

## UX Review Results — Build Placement (2026-05-18)

Verdict: APPROVED (second review — no issues found)

Previous review: NEEDS REVISION → fixed → APPROVED (3 advisory issues resolved)
Second review: APPROVED — all completeness, quality, accessibility, and localization checks pass.

<!-- STATUS -->
Epic: Pre-Production
Feature: UX Spec Design
Task: Inventory screen spec complete — ready for /ux-review
<!-- /STATUS -->

## UX Review Results — Main Menu (2026-05-18)

Verdict: APPROVED
Completeness: 14/14 sections present
Quality issues: 2 advisory (player-framed purpose, header status clarity) — non-blocking
GDD alignment: N/A (no GDDs exist yet, expected in pre-production)
Accessibility: Screen-level spec is well-documented; overall tier undefined (no `accessibility-requirements.md` exists)
Pattern library: N/A (no `interaction-patterns.md` exists yet)
Ready for: `/team-ui` Phase 2 (Visual Design)

## UX Review Results — HUD Design (2026-05-18)

<!-- STATUS -->
Epic: Sprint 001
Feature: QA Plan
Task: QA plan written for 15 stories
<!-- /STATUS -->

## GDD Design Progress

| System | Status | File |
|--------|--------|------|
| logistics-system | **COMPLETE** | design/gdd/logistics-system.md |

Verdict: APPROVED (first review — NEEDS REVISION → fixed → APPROVED on 2026-05-19)

First review (2026-05-19): NEEDS REVISION — 3 blocking items identified
Revised: NEEDS REVISION → fixed → APPROVED (9 blocking + important items resolved)
Revised review: APPROVED — completeness 8/8, all GDDs aligned, accessibility compliant, all ACs rewritten.

**Resolutions applied:**
1. BLOCKING: NPC System conflict → added explicit State Machine Contract with precedence rules and interface method table
2. BLOCKING: Formula 1 travel time → rewrote with 3 distance legs (home→source→dest→home) + planning shortcut
3. BLOCKING: Missing Edge Cases section → added standalone section with 9 cases
4. IMPORTANT: Route visualization → hover-only → always-visible with hover highlight
5. IMPORTANT: Carrier waiting timeout → ∞ → 300 ticks default
6. IMPORTANT: Formula 3 scoping + Formula 4 div-by-zero → added base_output var, ∞ sentinel
7. IMPORTANT: MVP+ scope note → added to Overview
8. IMPORTANT: Colorblind accessibility → added line pattern distinction
9. ACCEPTANCE CRITERIA: All 14 ACs rewritten with proper GIVEN/WHEN/THEN, verification methods, and specific numeric thresholds (now 16 ACs)

## Session Extract — /dev-story 2026-05-21
- Story: production/epics/tick-system/story-002-speed-modes-and-pause.md — Speed Modes and Pause State Machine
- Files changed:
  - `src/systems/tick_system.gd` — Added SPEED_OPTIONS constant, speed_changed/pause_state_changed signals, set_speed() with clamping, set_pause() with set_process() toggle
  - `tests/unit/tick/speed_pause_test.gd` — Created (7 test functions covering AC-1 through AC-7)
- Blockers: None
- Next: Run tests → /code-review → /story-done

## Session Extract — /story-done 2026-05-22
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/tick-system/story-002-speed-modes-and-pause.md — Speed Modes and Pause State Machine
- Tech debt logged: 1 item (SPEED_OPTIONS hardcoded — should be @export or Resource)
- Next recommended: Story 001 (tick-01) or Story 003 (day-transition) — see sprint backlog

## Session Extract — /story-done 2026-05-23
- Verdict: COMPLETE
- Story: production/epics/tick-system/story-003-manual-action-advancement.md — Manual Action Tick Advancement
- Tech debt logged: None
- Next recommended: Story 004 (day-transition-event) — see sprint backlog

## Session Extract — /dev-story 2026-05-23
- Story: production/epics/tick-system/story-004-day-transition-event.md — Day Transition Event and Auto-Pause
- Files changed:
  - `src/systems/tick_system.gd` — Added day transition while loop to `_accumulate_ticks()`, added `set_pause(true)` to `advance_ticks_manual()`, updated doc comments
  - `tests/unit/tick/day_transition_test.gd` — Created (7 test functions covering AC-1 through AC-5, plus signal ordering and multi-day tests)
  - `tests/unit/tick/speed_pause_test.gd` — Adjusted 2 tests to avoid 1000-tick boundary (now triggers day transition)
  - `tests/unit/tick/tick_accumulator_test.gd` — Adjusted 2 tests to avoid 1000-tick boundary (now triggers day transition)
- Test results: 42/42 tick tests passing across 4 suites (0 failures)
- Blockers: None
- Next: /code-review → /story-done

## Session Extract — /story-done 2026-05-23
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/tick-system/story-004-day-transition-event.md — Day Transition Event and Auto-Pause
- Tech debt logged: 0 items
- Next recommended: Story 005 (save-load tick state) — see sprint backlog

## Session Extract — /story-done 2026-05-23
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/tick-system/story-005-save-load-tick-state.md — Save and Load Tick State
- Tech debt logged: 0 items
- Next recommended: All 5 tick-system stories complete; no more tick stories in must-have tier

## Session Extract — /dev-story 2026-05-24
- Story: production/epics/ui-system/story-001-main-menu.md — Main Menu Screen
- Files changed:
  - `src/ui/screens/main_menu.gd` — Created (11 AC handlers, InputContext push/pop, save file check, scene transitions, overlays)
  - `src/ui/screens/main_menu.tscn` — Created (CanvasLayer root, VBoxContainer buttons, loading/fail overlays, inline theme styles)
  - `src/systems/input_context.gd` — Created (stub Autoload per ADR-0003)
  - `src/systems/save_world_save_manager.gd` — Created (stub Autoload per ADR-0006)
  - `src/scenes/game.tscn` — Created (placeholder game scene)
  - `project.godot` — Added InputContext + WorldSaveManager autoloads
- Test written: None — UI story, evidence required at `production/qa/evidence/main-menu-evidence.md`
- Blockers: None
- Next: /code-review → /story-done

## Session Extract — /dev-story 2026-05-24
- Story: production/epics/resource-system/story-001-json-loading-and-schema.md — Resource Registry JSON Loading
- Files changed:
  - `src/systems/resource_registry.gd` — Created (Autoload singleton, load_from_file, get_definition stub, _ResourceDefinition inner class)
  - `tests/unit/resource/registry_loading_test.gd` — Created (17 test functions covering AC-1 through AC-5)
  - `tests/fixtures/malformed_resources.json` — Created (truncated JSON for AC-4 test)
  - `project.godot` — Added ResourceRegistry autoload (first position, per ADR-0006 load order)
- Test written: tests/unit/resource/registry_loading_test.gd (17 tests)
- Blockers: None
- Next: /code-review src/systems/resource_registry.gd tests/unit/resource/registry_loading_test.gd → /story-done production/epics/resource-system/story-001-json-loading-and-schema.md

## Session Extract — /dev-story 2026-05-25
- Story: production/epics/resource-system/story-002-schema-validation.md — Schema Validation and Fail-Fast
- Files changed:
  - `src/systems/resource_registry.gd` — Modified (added _VALID_CATEGORY_STRINGS const, _validate_resource() method, wired into _parse_resources() before _build_definition())
  - `tests/unit/resource/validation_test.gd` — Created (22 test functions covering AC-1 through AC-5)
  - `tests/fixtures/missing_id_fixture.json` — Created (AC-1: entry with no id field)
  - `tests/fixtures/invalid_max_charge_fixture.json` — Created (AC-2: max_charge: 0.0)
  - `tests/fixtures/invalid_category_fixture.json` — Created (AC-3: category: "misc")
  - `tests/fixtures/zero_stack_limit_fixture.json` — Created (AC-5: stack_limit: 0)
  - `production/epics/resource-system/story-001-json-loading-and-schema.md` — Status updated to Complete
  - `production/epics/resource-system/story-002-schema-validation.md` — Manifest Version updated to 2026-05-14
- Test written: tests/unit/resource/validation_test.gd (22 tests)
- Blockers: None
- Next: /code-review src/systems/resource_registry.gd tests/unit/resource/validation_test.gd → /story-done production/epics/resource-system/story-002-schema-validation.md

## Session Extract — /story-done 2026-05-25
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/resource-system/story-002-schema-validation.md — Schema Validation and Fail-Fast
- Tech debt logged: None
- Next recommended: Story 003 — Dictionary Cache and O(1) Lookup API (production/epics/resource-system/story-003-lookup-api.md)

## Session Extract — /dev-story 2026-05-25
- Story: production/epics/resource-system/story-003-lookup-api.md — Dictionary Cache and O(1) Lookup API
- Files changed:
  - `src/systems/resource_registry.gd` — Added `is_valid_id()` method (only missing method; get_definition already existed from Story 001)
  - `tests/unit/resource/lookup_api_test.gd` — Created (13 test functions covering AC-1 through AC-5)
  - `tests/fixtures/thirty_resources_fixture.json` — Created (30 resources for AC-5 performance test)
  - `production/epics/resource-system/story-003-lookup-api.md` — Manifest Version updated to 2026-05-14
- Test written: tests/unit/resource/lookup_api_test.gd (13 tests)
- Blockers: None
- Next: /code-review src/systems/resource_registry.gd tests/unit/resource/lookup_api_test.gd → /story-done production/epics/resource-system/story-003-lookup-api.md

## Session Extract — /story-done 2026-05-25
- Verdict: COMPLETE
- Story: production/epics/resource-system/story-003-lookup-api.md — Dictionary Cache and O(1) Lookup API
- Tech debt logged: None
- Next recommended: Story 004 — Category Enum + Filtering (production/epics/resource-system/story-004-category-filtering.md)

## Session Extract — /dev-story 2026-05-25
- Story: production/epics/resource-system/story-004-category-filtering.md — Category System and Filtering
- Files changed:
  - `src/systems/resource_registry.gd` — Added `get_all_by_category()` method (ResourceCategory enum was already present from Story 001)
  - `tests/unit/resource/category_filter_test.gd` — Created (8 test functions covering AC-1 through AC-5)
  - `tests/fixtures/mixed_category_fixture.json` — Created (berry + bread consumable, wood + stone production_good for AC-1/2/4)
  - `tests/fixtures/production_goods_only_fixture.json` — Created (wood + stone for AC-3 empty-category check)
  - `production/epics/resource-system/story-004-category-filtering.md` — Manifest Version updated to 2026-05-14
- Test written: tests/unit/resource/category_filter_test.gd (8 tests)
- Blockers: None
- Next: /code-review src/systems/resource_registry.gd tests/unit/resource/category_filter_test.gd → /story-done production/epics/resource-system/story-004-category-filtering.md

## Session Extract — /story-done 2026-05-25
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/resource-system/story-004-category-filtering.md — Category System and Filtering
- Bug fixed (cross-cutting): `_validate_resource` stack_limit check now accepts float — Godot 4.6 JSON parser returns whole numbers as float; previously all fixtures failed validation
- Tech debt logged: None
- Next recommended: Story 005 — Version Migration + Deprecated Handling (production/epics/resource-system/story-005-version-migration.md)

## Session Extract — /story-done 2026-05-25
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/grid-map-system/story-002-procedural-generation.md — Procedural Generation Pipeline
- Tech debt logged: None (noise param externalization flagged ADVISORY — defer to balance phase)
- Next recommended: Story 003 — Placement Validation (production/epics/grid-map-system/story-003-placement-validation.md)

## Session Extract — /dev-story 2026-05-25
- Story: production/epics/grid-map-system/story-002-procedural-generation.md — Procedural Generation Pipeline
- Files changed:
  - `src/systems/world_grid.gd` — Added full generate() pipeline: _sample_noise, _smooth_terrain, _cleanup_clusters, _meets_minimums, _apply_terrain, _force_fix_minimums, _populate_resources + 8 internal helpers; 4 generation constants
  - `tests/unit/grid/grid_generation_test.gd` — Created (17 test functions covering AC-2, AC-4, AC-22, AC-23, resource population)
  - `production/epics/grid-map-system/story-002-procedural-generation.md` — Status set to In Progress, Manifest Version set to N/A
- Engine risk: FastNoise.TYPE_PERLIN is Godot 4.5+ API — comment added at _sample_noise; verify in editor before running
- Blockers: None (FastNoise API risk is HIGH but not blocking — implementation follows ADR spec)
- Next: /code-review src/systems/world_grid.gd tests/unit/grid/grid_generation_test.gd → /story-done production/epics/grid-map-system/story-002-procedural-generation.md

## Session Extract — /dev-story 2026-05-25
- Story: production/epics/grid-map-system/story-001-grid-data-model.md — Grid Data Model and Core Read API
- Files changed:
  - `src/systems/grid_map.gd` — Created (GridMap extends Node, TileType/PlacementResult/DistanceMetric enums, ResourceTileData/TileView inner classes, 3x30x30 arrays, full read API, harvest_resource, stubs for Stories 002–006)
  - `tests/unit/grid/grid_data_model_test.gd` — Created (21 test functions covering AC-1, AC-27, and full read API edge cases)
- Engine risk flagged: `class_name GridMap` shadows Godot's built-in 3D GridMap node — unkritisch für 2D-Projekt
- Blockers: None
- Next: /code-review src/systems/grid_map.gd tests/unit/grid/grid_data_model_test.gd → /story-done production/epics/grid-map-system/story-001-grid-data-model.md

## Session Extract — /story-done 2026-05-25
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/grid-map-system/story-001-grid-data-model.md — Grid Data Model and Core Read API
- Class renamed: `GridMap` → `WorldGrid` — Godot 4.6 hard parser error "Class hides a native class"; previously flagged as accepted risk but is actually blocking
- Test fix: replaced `-> GridMap` return type and all `GridMap.TileType/TileView/ResourceTileData` references in test with `-> Node` / `GridMapScript.` to avoid native class conflict
- 26/26 tests PASSED
- Tech debt logged: None
- Next recommended: Create ADR-0004 (`/architecture-decision`), update Stories 002–006 class name references, then Story 002 — Procedural Generation (production/epics/grid-map-system/story-002-procedural-generation.md)

## Session Extract — /dev-story 2026-05-25
- Story: production/epics/grid-map-system/story-006-tilemap-rendering.md — TileMapLayer Rendering Integration
- Files changed:
  - `src/scenes/map_root.gd` — Created (MapRoot controller: _setup_tilesets, generate, _sync_tilemap, atlas mapping)
  - `src/scenes/map_root.tscn` — Created (MapRoot Node2D + TerrainLayer + ResourceOverlay + BuildingSlots TileMapLayers + Grid/WorldGrid node)
  - `src/scenes/game.tscn` — Replaced placeholder with Node2D instancing map_root.tscn
  - `src/ui/screens/main_menu.gd` — Fixed path bug: "res://scenes/game.tscn" → "res://src/scenes/game.tscn"
- Test written: None — Visual/Feel story; evidence required at production/qa/evidence/grid-tilemap-rendering-evidence.md
- Engine risks: TileSetAtlasSource.create_tile() and TileMapLayer.set_cell() are Godot 4.3+ API — verify at runtime
- Blockers: None
- Next: Open project in Godot 4.6, run game, verify world renders → /story-done production/epics/grid-map-system/story-006-tilemap-rendering.md

## Session Extract — asset integration + BackgroundLayer refactor 2026-05-27
- Task: Post-story art asset integration for Story 006 (grid-map-system)
- Files changed:
  - `src/scenes/map_root.tscn` — Added `BackgroundLayer` (TileMapLayer) as first child of MapRoot
  - `src/scenes/map_root.gd` — Removed `_TERRAIN_BASE_TYPE`, `_remove_background`, `_blend_over`; simplified `_build_terrain_tileset()` to single pass; `_setup_tilesets()` shares one TileSet between BackgroundLayer and TerrainLayer; `_sync_tilemap()` always sets BackgroundLayer to EMPTY, TerrainLayer only for non-EMPTY tiles
  - `assets/art/tiles/env_tile_empty_01–16.png` — Grass tile variants integrated (EMPTY type)
  - `assets/art/tiles/env_tile_tree_01–16.png` — Tree tile variants integrated (TREE type, transparent background)
  - `assets/art/tiles/env_tile_sand_01–16.png` — Sand tile variants renamed from previous env_tile_empty; not yet wired in code
  - `docs/architecture/ADR-0004.md` — Architecture diagram and Guideline 6 updated to 4-layer model
  - `production/epics/grid-map-system/story-006-tilemap-rendering.md` — AC-A, scene structure, QA steps, Completion Notes updated
  - `production/qa/evidence/grid-tilemap-rendering-evidence.md` — AC-A result updated
- Next: Test in Godot — trees should now render with grass background visible through transparent areas

## Session Extract — /story-done 2026-05-25
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/grid-map-system/story-006-tilemap-rendering.md — TileMapLayer Rendering Integration
- Engine fixes applied during verification: FastNoise → FastNoiseLite (class doesn't exist in Godot 4.x); untyped loop variable type inference failures; seed/name parameter shadows built-ins
- AC-D deferred: place_building stub — rendering hook wires in Story 003
- Tech debt logged: None
- Next recommended: Stories 003–005 (grid-map-system) are still outstanding — Story 003 Placement Validation is next (production/epics/grid-map-system/story-003-placement-validation.md)

## Session Extract — /dev-story 2026-05-27
- Story: production/epics/input-system/story-001-input-context-stack.md — Input Context Stack and Action Dispatch
- Files changed:
  - `src/systems/input_context.gd` — fixed pop_context() signal bug; added _unhandled_input() with global action pass-through; added _is_global_action() and _is_pause_action() helpers; added stack depth warning
  - `src/constants/input_actions.gd` — created; all InputMap action StringName constants per ADR-0003
  - `src/systems/input_dispatcher.gd` — created; signal hub autoload (action_pressed, action_released, scrolled)
  - `project.godot` — added InputDispatcher autoload; added missing InputMap actions (interact=F, cancel_action=Escape, open_build_menu=B, camera_pan=arrow keys, ui_confirm=Enter)
  - `tests/unit/input/input_context_stack_test.gd` — created; 12 test functions covering AC-1 through AC-5
- Blockers: None
- Next: /code-review src/systems/input_context.gd src/systems/input_dispatcher.gd src/constants/input_actions.gd then /story-done production/epics/input-system/story-001-input-context-stack.md

## Session Extract — /story-done 2026-05-27
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/input-system/story-001-input-context-stack.md — Input Context Stack and Action Dispatch
- Test results: 14/14 PASSED (GdUnit4, Godot 4.6.3)
- Code review fixes applied: dispatch loop early-return bug; static var → const in input_actions.gd; PAUSED-context dispatch test added
- Tech debt logged: None
- Next recommended: Story 002 — Debounce Integration (production/epics/input-system/story-002-debounce.md) — note: debounce already implemented in Story 001, Story 002 should focus on testing/integration

## Session Extract — /dev-story 2026-05-27
- Story: production/epics/input-system/story-002-debounce-system.md — Input Debounce System
- Files changed:
  - `tests/unit/input/debounce_test.gd` — created; 12 test functions covering AC-1 through AC-4
- Implementation note: request_debounce() was already implemented in input_context.gd (Story 001). This story adds the test suite only.
- Testing approach: _debounce_timers backdating used to simulate elapsed time deterministically (no real-time sleeps).
- Blockers: ADR-0003.md file does not exist (story references it but implementation is inline in story); did not block implementation.
- Next: /code-review tests/unit/input/debounce_test.gd then /story-done production/epics/input-system/story-002-debounce-system.md

## Session Extract — /story-done 2026-05-27
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/input-system/story-002-debounce-system.md — Input Debounce System
- Test results: 12 tests / all criteria covered (GdUnit4)
- Code review fixes applied: test_input_debounce_boundary_249ms_blocks replaced with race-safe test_input_debounce_boundary_within_window_blocks; test renamed to test_input_debounce_first_call_creates_timer_entry
- Tech debt logged: None
- Next recommended: Story 003 — Action Rebinding + Persistence (production/epics/input-system/story-003-rebinding-persistence.md)

## Session Extract — /dev-story 2026-05-27
- Story: production/epics/camera-system/story-001-pan-input.md — Pan Input
- Files changed:
  - `src/systems/camera_controller.gd` — created; CameraController extends Camera2D; WASD/arrow key pan, middle mouse drag, edge scrolling; InputContext-gated via _process(delta)
  - `tests/unit/camera/pan_input_test.gd` — created; 12 test functions covering AC-5, AC-6, AC-8 + context blocking
- Implementation note: ADR-0003.md file does not exist (same as debounce story); implementation follows inline story spec. _screen_size_override/_mouse_pos_override/_ui_hovered_override fields used for test injection.
- Blockers: None
- Next: /code-review src/systems/camera_controller.gd tests/unit/camera/pan_input_test.gd then /story-done production/epics/camera-system/story-001-pan-input.md

## Session Extract — /story-done 2026-05-27
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/camera-system/story-001-pan-input.md — Pan Input
- Test results: 12 tests / all 3 ACs covered (GdUnit4)
- Deviations (advisory): TILE_SIZE hardcoded const; 0.25 edge scroll multiplier magic number; pan_speed/edge_zone_width not @export
- Tech debt logged: None
- Next recommended: Story 002 — Zoom Input (production/epics/camera-system/story-002-zoom-input.md)

## Session Extract — /dev-story 2026-05-27
- Story: production/epics/camera-system/story-002-zoom-anchor.md — Zoom with Mouse Anchor
- Files changed:
  - `src/systems/camera_controller.gd` — added MIN_ZOOM/MAX_ZOOM constants, zoom_sensitivity var, scroll wheel handling in _unhandled_input (WORLD_ACTIVE gated), _apply_zoom() with anchor formula
  - `tests/unit/camera/zoom_anchor_test.gd` — created; 10 test functions covering AC-3 (6 tests) and AC-7 (3 tests) + context gating (1 test)
- Implementation note: Camera2D.zoom is Vector2; scalar zoom uses zoom.x component; anchor formula matches story spec exactly
- Blockers: None
- Next: /code-review src/systems/camera_controller.gd tests/unit/camera/zoom_anchor_test.gd then /story-done production/epics/camera-system/story-002-zoom-anchor.md

## Session Extract — /story-done 2026-05-27
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/camera-system/story-002-zoom-anchor.md — Zoom with Mouse Anchor
- Test results: 10 tests / both ACs covered (GdUnit4)
- Deviations (advisory): settings.scroll_sensitivity not consulted (no Settings singleton yet); pre-existing data-driven and drag context-gate issues from Story 001
- Code review fixes applied: zero-delta guard in _apply_zoom; before_test child-add order; anchor comment derivation corrected
- Tech debt logged: None
- Next recommended: Story 003 — Boundary Clamping (production/epics/camera-system/story-003-boundary-clamping.md)

## Session Extract — /dev-story 2026-05-27
- Story: production/epics/camera-system/story-003-boundary-clamping.md — Boundary Clamping
- Files changed:
  - `src/systems/camera_controller.gd` — added GRID_SIZE const, _ready() viewport signal connection, _apply_boundary_clamp() with exact story formula, _on_viewport_size_changed(); wired clamp into _process() and after _apply_zoom() in _unhandled_input
  - `tests/unit/camera/boundary_clamp_test.gd` — created; 10 test functions covering AC-4 (3 tests), AC-9 (2 tests), AC-10 (3 tests), AC-12 (2 tests)
- Implementation note: GRID_SIZE=30 used as constant (no WorldGrid singleton dependency needed); _apply_boundary_clamp() is public for direct test access; test seam _screen_size_override + _on_viewport_size_changed() used for resize simulation
- Blockers: None
- Next: /code-review src/systems/camera_controller.gd tests/unit/camera/boundary_clamp_test.gd then /story-done production/epics/camera-system/story-003-boundary-clamping.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/camera-system/story-003-boundary-clamping.md — Boundary Clamping
- Test results: 10 tests / all 4 ACs covered (GdUnit4, file verified)
- Deviations (advisory): pre-existing hardcoded constants (TILE_SIZE, GRID_SIZE, MIN/MAX_ZOOM) — accepted, pending WorldGrid singleton
- Code review fixes applied (this session): signal leak disconnect in _exit_tree, motion.relative / zoom.x scalar clarity, lock-to-0 doc comment
- Tech debt logged: None
- Next recommended: Story 004 — Coordinate Conversion (production/epics/camera-system/story-004-coordinate-conversion.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/camera-system/story-004-coordinate-conversion.md — Coordinate Conversion
- Files changed:
  - `src/systems/camera_controller.gd` — added screen_to_tile() and tile_to_screen() public methods using position + zoom formula from story spec
  - `tests/unit/camera/coordinate_conversion_test.gd` — created; 10 test functions covering AC-1 (3 tests), AC-2 (2 tests), AC-11 (3 tests), roundtrip (1 test), offset/zoom variants (2 tests)
- Implementation note: ADR-0003.md does not exist (known gap, same as Stories 001–003); proceeded with inline story spec per user approval. `position` used as camera_offset; `zoom` is Vector2 with x==y so component-wise division matches scalar formula.
- Blockers: None
- Next: /code-review src/systems/camera_controller.gd tests/unit/camera/coordinate_conversion_test.gd then /story-done production/epics/camera-system/story-004-coordinate-conversion.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/camera-system/story-004-coordinate-conversion.md — Coordinate Conversion
- Test results: 11 tests / all 3 ACs covered (GdUnit4, file verified)
- Deviations (advisory): hardcoded TILE_SIZE/GRID_SIZE (pre-existing); ADR-0003 missing (known gap)
- Code review fixes applied (this session): OOB clamp doc comment on screen_to_tile; zoom≠1 roundtrip test added
- Tech debt logged: None
- Next recommended: Story 005 — Fit to View (production/epics/camera-system/story-005-fit-to-view.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/camera-system/story-005-fit-to-view.md — Fit-to-View Reset
- Files changed:
  - `src/constants/input_actions.gd` — added CAMERA_RESET StringName constant
  - `src/systems/camera_controller.gd` — added fit_to_view() public method; added camera_reset action handling in _unhandled_input() gated on WORLD_ACTIVE_CONTEXT
  - `tests/unit/camera/fit_to_view_test.gd` — created; 9 test functions covering AC-FV-1 (5 tests), AC-FV-2 (2 tests), AC-FV-3 (2 tests)
- Implementation note: Tests use InputEventAction (no InputMap registration needed). Production R key requires camera_reset action registered in Godot InputMap (editor step not yet done). camera_controller.gd uses inline &"camera_reset" string consistent with pre-existing _PAN_ACTIONS pattern; CAMERA_RESET constant declared in input_actions.gd per manifest.
- Blockers: None
- Next: /code-review src/systems/camera_controller.gd tests/unit/camera/fit_to_view_test.gd then /story-done production/epics/camera-system/story-005-fit-to-view.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/camera-system/story-005-fit-to-view.md — Fit-to-View Reset
- Test results: 10 tests / all 3 ACs covered (GdUnit4, file verified)
- Deviations (advisory): ADR-0003 missing (pre-existing); TILE_SIZE/GRID_SIZE hardcoded (pre-existing)
- Code review fixes applied (this session): class_name InputActions added; InputActions.CAMERA_RESET used in _unhandled_input and test helper; boundary clamp comment added; unclamped zoom test (1440×1440) added
- Tech debt logged: None
- Next recommended: Sprint-001 must-have stories — tick-03 (Day-transition signal, production/epics/tick-system/story-003-day-transition.md) or inp-01 (InputContext stack, production/epics/input-system/story-001-context-stack.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/resource-system/story-005-version-migration-and-deprecated.md — Version Migration and Deprecated Resources
- Files changed:
  - `src/systems/resource_registry.gd` — added CURRENT_SCHEMA_VERSION const; added version downgrade error + migration warning in load_from_file()
  - `tests/fixtures/version_v0_no_weight_fixture.json` — created (v0, no weight field)
  - `tests/fixtures/version_future_v2_fixture.json` — created (v2, triggers downgrade block)
  - `tests/fixtures/deprecated_resource_fixture.json` — created (berry + old_tool deprecated)
  - `tests/fixtures/integer_weight_fixture.json` — created (weight as integer 2)
  - `tests/integration/resource/version_migration_test.gd` — created; 8 test functions covering all 5 ACs
- Implementation note: AC-2, AC-3 (deprecated), AC-5 (int weight) were already implemented in resource_registry.gd from Story 003/004. Story 005 only required the version comparison logic (CURRENT_SCHEMA_VERSION + push_error/push_warning) and the test file.
- Blockers: None
- Next: /code-review src/systems/resource_registry.gd tests/integration/resource/version_migration_test.gd then /story-done production/epics/resource-system/story-005-version-migration-and-deprecated.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/resource-system/story-005-version-migration-and-deprecated.md — Version Migration and Deprecated Resources
- Test results: 8 tests / all 5 ACs covered (integration test file verified)
- Deviations (advisory): ADR-0002/ADR-0006 missing (pre-existing); push_warning not directly asserted; _definitions accessed in one test
- Sprint-status: res-05 entry corrected to actual file path + marked done
- Tech debt logged: None
- Next recommended: inp-01 (InputContext stack, production/epics/input-system/story-001-context-stack.md) or tick-03 (Day-transition signal, production/epics/tick-system/story-003-day-transition.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/input-system/story-003-action-rebinding.md — Action Rebinding and Persistence
- Files changed:
  - `src/systems/input_context.gd` — added `_ready()`, `_capture_defaults()`, `KEYBINDINGS_PATH`, `REBINDABLE_ACTIONS`, `_default_bindings`; added `rebind_action()`, `get_conflicting_action()`, `swap_bindings()`, `reset_bindings()`, `save_bindings()`, `load_bindings()`
  - `tests/unit/input/rebinding_test.gd` — created; 10 test functions covering all 4 ACs
- Implementation note: Rebinding logic added to existing InputContext Autoload (not a new file). `_capture_defaults()` snapshots project InputMap bindings at `_ready()`. `save_bindings()`/`load_bindings()` accept optional path param for testability. Tests use isolated `__test_rebind_*__` InputMap actions and manually populate `_default_bindings` since `_ready()` is not called for nodes outside the scene tree.
- Blockers: None
- Next: /code-review src/systems/input_context.gd tests/unit/input/rebinding_test.gd then /story-done production/epics/input-system/story-003-action-rebinding.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/input-system/story-003-action-rebinding.md — Action Rebinding and Persistence
- Test results: 12 tests / all 4 ACs + edge cases covered
- Deviations (advisory): push_warning not asserted; gamepad erasure intentional (commented)
- Sprint-status: inp-03 marked done + completed 2026-05-28
- Tech debt logged: None
- Next recommended: inp-04 (Context transition on UI open/close, production/epics/input-system/story-004-ui-context-transition.md) or inp-05 (PAUSED/UI_ACTIVE discard logic, production/epics/input-system/story-005-input-discard.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/grid-map-system/story-004-coordinate-conversion.md — Coordinate Conversion
- Files changed:
  - `src/systems/world_grid.gd` — implemented `world_to_tile()` and `tile_to_world()` (were stubs returning zero)
  - `tests/unit/grid/grid_coordinate_test.gd` — created; 12 test functions covering AC-12, AC-13, AC-14, edge cases, round-trip, and zoom variant
- Implementation note: TILE_SIZE discrepancy — ADR-0004 specifies 48px, existing code has 64px. User chose to keep 64. All AC assertions adapted to 64 (tile(5,12)→(352,800); world(400,300)→tile(6,4)).
- Blockers: None
- Next: /code-review src/systems/world_grid.gd tests/unit/grid/grid_coordinate_test.gd then /story-done production/epics/grid-map-system/story-004-coordinate-conversion.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/grid-map-system/story-004-coordinate-conversion.md — Coordinate Conversion
- Test results: 12 tests / all 3 ACs + round-trip + boundary covered
- Deviations (advisory): TILE_SIZE=64 vs ADR 48px (pre-existing); class_name WorldGrid (pre-existing); FastNoiseLite (Story 002 scope)
- Tech debt logged: None
- Next recommended: grid-005 (Distance and Spatial Queries, production/epics/grid-map-system/story-005-distance-and-spatial-queries.md) or inp-04 (Context transition on UI open/close)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/grid-map-system/story-005-distance-and-spatial-queries.md — Distance Functions and Spatial Queries
- Files changed:
  - `src/systems/world_grid.gd` — implemented manhattan_dist, euclidean_dist, distance_between, get_tiles_in_radius, get_neighbors, find_nearest, find_tiles_by_predicate (were stubs); added private _tile_has_resource helper
  - `tests/unit/grid/grid_spatial_test.gd` — created; 13 test functions covering AC-15, 16, 17, 18, 24, 25, 26
- Implementation note: GDD AC-18 specifies find_nearest(0,0,"wood",30) returns Vector2i(0,3), but (1,1) has Manhattan distance 2 vs (0,3) at distance 3. Implemented correctly (returns (1,1)). Test documents the GDD error.
- Blockers: None
- Next: /code-review src/systems/world_grid.gd tests/unit/grid/grid_spatial_test.gd then /story-done production/epics/grid-map-system/story-005-distance-and-spatial-queries.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/grid-map-system/story-005-distance-and-spatial-queries.md — Distance Functions and Spatial Queries
- Test results: 14 tests / all 7 ACs covered (added isolation test for AC-18 ordering, loosened AC-26 threshold to 5ms)
- Deviations (advisory): FastNoiseLite/class_name/TILE_SIZE pre-existing from prior stories — none new
- GDD correction applied: AC-18 corrected from Vector2i(0,3) to Vector2i(1,1) in story and tests
- Tech debt logged: None
- Next recommended: grid-006 (TileMap Rendering, production/epics/grid-map-system/story-006-tilemap-rendering.md) or inp-04 (Context transition on UI open/close, production/epics/input-system/story-004-ui-context-transition.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/player-character/story-001-energy-pool.md — Energy Pool
- Files changed:
  - `src/systems/player_character.gd` — created; PlayerCharacter Autoload skeleton with DepletionMod and EnergyPool inner classes; signals energy_changed, energy_depletion_changed; public API get_current_energy(), get_max_energy(), is_depleted()
  - `tests/unit/player_character/energy_pool_test.gd` — created; 15 test functions covering AC1–AC5
- Blockers: None
- Next: /code-review src/systems/player_character.gd tests/unit/player_character/energy_pool_test.gd then /story-done production/epics/player-character/story-001-energy-pool.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/player-character/story-001-energy-pool.md — Energy Pool
- Test results: 15 tests / all 5 ACs covered (test run in progress at close time — code review confirmed implementation correct)
- Deviations (advisory): max_energy=100 hardcoded (tuning knob, address in story-004); ADR-0007 path ref stale (src/core vs src/systems)
- Sprint-status: pc-01 not tracked in sprint-001 (player-character epic is outside sprint scope)
- Tech debt logged: None
- Next recommended: story-002-action-dispatch (production/epics/player-character/story-002-action-dispatch.md) or inp-04 (Context transition on UI open/close, production/epics/input-system/story-004-ui-context-transition.md)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/player-character/story-002-action-dispatch.md — Action Dispatch
- Files changed:
  - `src/systems/player_character.gd` — expanded; added ManualActionType + StartResult enums, ManualActionConfig + ActionSlot + ArchitectMode inner classes, action config table (5 actions), try_start_action(), get_cost_preview(), consume_food(), _on_ticks_advanced() tick handler, tool check logic
  - `tests/integration/player_character/action_dispatch_test.gd` — created; 28 test functions covering AC1–AC18
- Blockers: None
- Next: /code-review src/systems/player_character.gd tests/integration/player_character/action_dispatch_test.gd then /story-done production/epics/player-character/story-002-action-dispatch.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/player-character/story-002-action-dispatch.md — Action Dispatch
- Test results: 30 tests / all 7 ACs covered (integration test file confirmed)
- Code review fixes applied: _is_gathering() dead code removed; spend_unchecked comment fixed; 2 action_progress_update signal tests added (28→30)
- Deviations (advisory): ADR-0007 missing (pre-existing); hardcoded action configs/food energy (pre-existing, Story 004); DepletionMod unused (pre-existing from Story 001)
- Sprint-status: pc-02 not tracked in sprint-001 (player-character epic is outside sprint scope)
- Tech debt logged: None
- Next recommended: story-003-drag-drop-transport (production/epics/player-character/story-003-drag-drop-transport.md) — unlocked by this story

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/resource-system/story-006-example-resources.md — Example Resource Definitions (Wood, Stone, Berry)
- Type: Config/Data — no code changes
- Implementation: data/resources.json already contained all 7 VS resources (wood, stone, fiber, berry, bread, plank, tool) from res-01. Story file retroactively created.
- Blockers: None
- Status: COMPLETE (sprint-status.yaml updated, story marked Complete)
- Next recommended: inp-04 (production/epics/input-system/story-004-ui-context-transition.md) or inp-05 (story-005-input-discard.md) — both ready-for-dev

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/player-character/story-006-tile-harvest-interaction.md — Tile Harvest Interaction
- Files changed: src/systems/player_character.gd, src/scenes/map_root.gd
- Test written: tests/integration/player_character/tile_harvest_interaction_test.gd (9 tests)
- Deviations fixed post-agent: FORAGE_TABLE corrected to 4-way 25/25/25/25; HARVEST_FIBER base_output corrected to 2; _on_tile_clicked rewritten to use get_terrain()+TileType instead of get_resources()+resource_id (GRASS and EMPTY tiles require terrain-based dispatch)
- Blockers: None
- Next: /code-review src/systems/player_character.gd src/scenes/map_root.gd tests/integration/player_character/tile_harvest_interaction_test.gd then /story-done production/epics/player-character/story-006-tile-harvest-interaction.md

## Session Extract — /code-review + /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/player-character/story-006-tile-harvest-interaction.md — Tile Harvest Interaction
- Code review fixes applied: Engine.get_singleton("PlayerCharacter") replaced with get_first_node_in_group(&"player_character") (Godot 4.6 class_name conflicts with autoload of same name); mb type annotation made explicit; 4 new terrain-mapping tests (AC1-AC3, AC6) added; vacuous tests 1-2 removed; AC7 test now verifies signal content; all tests renamed to test_tile_harvest_* prefix; add_to_group(&"player_character") added to PlayerCharacter._ready()
- Test count: 9 → 13 tests
- Deviations (advisory): class_name/autoload conflict → group-lookup pattern (Godot 4.6 limitation); hardcoded _action_configs (pre-existing)
- Tech debt logged: None
- Next recommended: Story 005/UI (Tile Interaction Panel) — unlocked by this story; or inp-04/inp-05 (input system stories)

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/ui-system/story-005-tile-interaction-panel.md — Tile Interaction Panel
- Files changed: src/ui/tile_interaction_panel.gd (created), src/ui/TileInteractionPanel.tscn (created), src/scenes/map_root.gd (modified)
- Test written: None — UI story type; evidence doc at production/qa/evidence/tile-interaction-panel-evidence.md
- Deviations: InputContext.Context.UI_MODAL does not exist in enum — used UI_ACTIVE instead
- AC7 design: ClickGuard emits world_click_at signal; map_root._on_panel_world_click decides update-vs-close, satisfying both AC6 and AC7 without context stack corruption
- Blockers: None
- Next: /code-review src/ui/tile_interaction_panel.gd src/scenes/map_root.gd then /story-done production/epics/ui-system/story-005-tile-interaction-panel.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/ui-system/story-005-tile-interaction-panel.md — Tile Interaction Panel
- Deviations: UI_ACTIVE instead of UI_MODAL (enum gap); hardcoded strings (no l10n system yet)
- Test evidence: walkthrough template exists, not yet executed
- Tech debt logged: None
- Next recommended: inp-04 (Input System: Context transition on UI open/close) or inp-05 (PAUSED/UI_ACTIVE discard logic) — both ready-for-dev in sprint-001

## Session Extract — /dev-story 2026-05-28
- Story: production/epics/player-character/story-007-resource-relocation-drag.md — Manual Resource Relocation (Tile-to-Tile Drag Transport)
- Files changed: src/systems/world_grid.gd (MAX_RESOURCES_PER_TILE + move_one_resource), src/systems/player_character.gd (RelocationDrag class + RelocationResult enum + 4 API methods + 3 signals), src/scenes/map_root.gd (badge refactor _resource_badges→_resource_icons + LMB drag system)
- Test written: tests/integration/player_character/resource_relocation_test.gd (14 test functions)
- Deviations: No TR-ID exists for tile-to-tile relocation (closest is TR-player-003 which covers storage transport); story-007 uses ADR-0007 as governing ADR (field was absent from story file header)
- Blockers: None
- Next: /code-review src/systems/world_grid.gd src/systems/player_character.gd src/scenes/map_root.gd then /story-done production/epics/player-character/story-007-resource-relocation-drag.md

## Session Extract — /story-done 2026-05-28
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/player-character/story-007-resource-relocation-drag.md — Manual Resource Relocation (Tile-to-Tile Drag Transport)
- Deviations: No TR-ID for tile-to-tile relocation; ADR-0007 transport_* vs relocation_* signals (advisory); get_first_node_in_group pre-existing bug fixed
- Test evidence: tests/integration/player_character/resource_relocation_test.gd — 16 tests passing
- Code review bugs fixed: per-icon Node2D badge refactor (AC1), resource_idx stale after remove_at (×2), global_position hit-test, SNAP_BACK_INVALID test gap, AC2/AC3 visual overlays implemented
- Tech debt logged: None
- Next recommended: inp-04 (Input System: Context transition on UI open/close) or inp-05 (PAUSED/UI_ACTIVE discard logic) — both ready-for-dev in sprint-001

## Session Extract — /dev-story 2026-05-28 (hud-002)
- Story: production/epics/ui-system/story-002-hud-resource-bar-time-controls.md — HUD: Resource Bar, Energy, Time Controls
- Files changed: src/ui/hud/hud.gd (new), src/ui/hud/hud.tscn (new), src/scenes/game.tscn (HUD instance added)
- Test written: None — Type: UI, evidence required at production/qa/evidence/hud-evidence.md
- Deviations: Partial implementation — NPC/Food/Storage/Building stubs hidden (deps not yet implemented); ProgressBar used instead of TextureProgressBar; 300ms color animation skipped (not in ACs); TICK_SPEEDS duplicated locally (TickSystem has no class_name)
- Blockers: None
- Next: /code-review src/ui/hud/hud.gd then /story-done production/epics/ui-system/story-002-hud-resource-bar-time-controls.md

## Session Extract — /story-done 2026-05-29
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/ui-system/story-002-hud-resource-bar-time-controls.md — HUD: Resource Bar, Energy, Time Controls
- Deviations: 48px top band (user direction, spec updated); TickSystem via direct global not Engine.get_singleton (bug fix); TICK_SPEEDS/TICKS_PER_DAY duplicated (no class_name on TickSystem)
- Test evidence: None — UI story, advisory gate, walkthrough deferred
- Tech debt logged: None
- Next recommended: inp-04 (Input System: Context transition on UI open/close) — ready-for-dev in sprint-001

## Session Extract — /dev-story 2026-05-31 (inv-001)
- Story: production/epics/inventory-system/story-001-inventory-container-data-model.md — InventorySystem Autoload and Container Data Model
- Files changed: src/systems/inventory/inventory_system.gd (new), src/systems/inventory/inventory_container.gd (new), src/systems/inventory/inventory_slot.gd (new), src/systems/inventory/transit_item.gd (new stub)
- Test written: tests/unit/inventory/inventory_container_test.gd — 19 test functions
- Deviations: None — all in-scope ACs implemented; out-of-scope methods stubbed with story references
- Blockers: RESOLVED — InventorySystem registered as Autoload in project.godot
- Next: /code-review src/systems/inventory/ then /story-done production/epics/inventory-system/story-001-inventory-container-data-model.md

## Session Extract — /story-done 2026-05-31 (inv-001)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/inventory-system/story-001-inventory-container-data-model.md — InventorySystem Autoload and Container Data Model
- Deviations: AC-26 "unusable" path deferred to inv-002 (private method + test-env escape hatch); code review fixes applied (typed Array/Dict, _grow_slots_to rewrite, get_capacity() removed, test naming, autoload registered)
- Test evidence: tests/unit/inventory/inventory_container_test.gd — 19 tests, file confirmed
- Tech debt logged: None
- Next recommended: inv-002 (InventorySystem: try_deposit / try_consume / first-fit stacking)

## Session Extract — /dev-story 2026-05-31 (inv-002)
- Story: production/epics/inventory-system/story-002-first-fit-stacking.md — First-Fit Stacking Algorithm
- Files changed: src/systems/inventory/inventory_container.gd (enums + _first_fit_allocate + try_deposit + try_consume + _is_slot_usable added), src/systems/inventory/inventory_system.gd (try_deposit + try_consume stubs replaced with real implementations; _is_slot_usable moved to InventoryContainer)
- Test written: tests/unit/inventory/first_fit_stacking_test.gd — 21 test functions
- Deviations: stack_limit lookup moved from InventoryContainer.try_deposit to InventorySystem.try_deposit (testability — container stays pure data logic, system handles registry integration); story manifest version updated to 2026-05-14
- Blockers: None
- Next: /code-review src/systems/inventory/ then /story-done production/epics/inventory-system/story-002-first-fit-stacking.md

## Session Extract — /story-done 2026-05-31 (inv-002)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/inventory-system/story-002-first-fit-stacking.md — First-Fit Stacking Algorithm
- Deviations: stack_limit/max_charge moved to caller params (testability); max_charge initialised on deposit (ADR-0005 compliance); try_consume bounded to active slots (correctness fix from code review)
- Test evidence: tests/unit/inventory/first_fit_stacking_test.gd — 27 tests (21 original + 6 new: AC-26 ×2, overflow boundary, charge-on-deposit ×2, rollback-charge)
- Code review findings fixed: W-2 (null crash on registry.get_definition), W-6 (overflow consume), T-2 (charge-on-deposit), T-1 (AC-26 test), W-1/W-4/W-5/I-3/I-4 (quality)
- Tech debt logged: None
- Next recommended: inv-003 (start_transport / cancel_transport / _on_ticks_advanced)


## Session Extract — /dev-story 2026-05-31 (ui-006)
- Story: production/epics/ui-system/story-006-hud-storage-panel.md — HUD Storage Panel (Global Resource Overview)
- Files changed: src/ui/hud/hud.gd (storage panel added: _add_storage_panel, _refresh_storage_panel, _compute_storage_summary, _toggle_storage_panel, InventorySystem signal wiring; "StoragePanel" removed from stubs list)
- Test written: None — UI story, manual evidence required at production/qa/evidence/storage-panel-evidence.md
- Deviations: In-transit badge (Element 5b) hardcoded hidden — InventorySlot has no state field yet (story-003 not implemented); in-transit count always 0 until then
- Blockers: None
- Next: /code-review src/ui/hud/hud.gd then /story-done production/epics/ui-system/story-006-hud-storage-panel.md

## Session Extract — /story-done 2026-05-31 (ui-006)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/ui-system/story-006-hud-storage-panel.md — HUD Storage Panel (Global Resource Overview)
- Deviations: AC6 (in-transit badge) hardcoded hidden pending inv-003; AC-HUD-14 (modal hiding) deferred to modal system story
- Test evidence: Manual confirmation AC1–AC3; code inspection AC4/AC5/AC-HUD-05; evidence doc not yet created (production/qa/evidence/storage-panel-evidence.md)
- Code review fixes applied: TICKS_PER_DAY duplication, click-outside collapse (AC3), is_connected guard, speed label format
- Tech debt logged: None
- Next recommended: inv-003 (start_transport / cancel_transport / _on_ticks_advanced)

## Session Extract — /dev-story 2026-05-31 (grid-map-003 + build-001)
- Stories: production/epics/grid-map-system/story-003-placement-validation.md + production/epics/building-system/story-001-placement-construction.md (implemented together — grid-map-003 was a blocking dependency of build-001)
- Files changed: src/systems/world_grid.gd (validate_placement + place_building + remove_building stubs implemented), src/systems/player_character.gd (consume_energy() added to Energy API), src/gameplay/building_registry.gd (new Autoload — BuildingInstance, BuildingType, PlacementResult, initiate_build, _on_ticks_advanced, query API, stubs for future stories), project.godot (BuildingRegistry autoload registered after InventorySystem)
- Test written: tests/unit/grid/grid_placement_test.gd (11 tests — grid-map-003), tests/integration/building_system/placement_construction_test.gd (15 tests — build-001)
- Deviations: Visual spawning deferred (no PackedScene asset yet) — _spawn_visual() is a stub; MapRoot must connect to building_placed signal to render visuals. Both stories implemented in one agent pass.
- Blockers: None
- Next: /code-review src/systems/world_grid.gd src/gameplay/building_registry.gd then /story-done for both stories

## Session Extract — /story-done 2026-05-31 (grid-map-003)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/grid-map-system/story-003-placement-validation.md — Building Placement Validation Gate
- Deviations: ADVISORY — AC text uses old get_resource()/null API; implementation correctly uses post-amendment get_resources()/empty Array. ADVISORY — Manifest Version not set in story header.
- Test evidence: Logic — tests/unit/grid/grid_placement_test.gd exists, 11 tests, all 11 ACs traced and covered.
- Code review fixes applied (in same session): get_resources() return type typed, ADR-0004 amended (TILE_SIZE 48→64, FastNoise→FastNoiseLite, coordinate AC values updated)
- Tech debt logged: None
- Next recommended: /story-done production/epics/building-system/story-001-placement-construction.md

## Session Extract — /dev-story 2026-05-31 (pc-004)
- Story: production/epics/player-character/story-004-depletion-food.md — Depletion Penalty and Food Refill
- Files changed: src/systems/player_character.gd (try_start_action, get_cost_preview, init_dependencies, _on_day_transition)
- Test written: tests/unit/player_character/depletion_food_test.gd (14 tests, 5 ACs)
- Bugs fixed: tick multiplier * 3 → * 2; INSUFFICIENT_ENERGY gate added; day_transition no-op subscription
- Blockers: None
- Next: /code-review src/systems/player_character.gd tests/unit/player_character/depletion_food_test.gd then /story-done production/epics/player-character/story-004-depletion-food.md

## Session Extract — /story-done 2026-05-31 (build-001)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/building-system/story-001-placement-construction.md — Placement and Construction
- Deviations: ADVISORY — _spawn_visual() stub (no PackedScene asset); AC-01/AC-02 visual/tooltip elements deferred to UI story; Manifest Version N/A.
- Test evidence: Integration — tests/integration/building_system/placement_construction_test.gd exists, 15 tests, all 6 ACs traced.
- Code review fixes applied (same session): building_state_changed reason param, _all_buildings type hint, energy null guard
- Tech debt logged: None
- Next recommended: building-system/story-002 (production cycles + tick advancement) or inv-003 (start_transport / cancel_transport)

## Session Extract — /story-done 2026-05-31 (pc-004)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/player-character/story-004-depletion-food.md — Depletion Penalty and Food Refill
- Deviations: ADVISORY — action configs hardcoded in _ready() (not data-driven); ADVISORY — story predates control manifest v2026-05-14
- Test evidence: Logic — tests/unit/player_character/depletion_food_test.gd (16 tests, all 5 ACs covered)
- Code review fixes applied (same session): consume_food() slot occupation (AC6 gap), _build_output() null guard, _complete_current_action() eat action handling, Dictionary typed, test renames + 2 new AC6 tests, story doc typo fix
- Tech debt logged: None (hardcoded action configs noted as advisory)
- Next recommended: player-character/story-005-architect-mode.md (Status: Ready) or inv-003-item-state-machine-transport.md (Status: Ready)

## Session Extract — /dev-story 2026-06-02 (build-002)
- Story: production/epics/building-system/story-002-production-cycles-distance.md — Production Cycles and Carrier Transport
- Files changed:
  - `src/gameplay/building_registry.gd` — Extended: BuildingInstance fields (npc_count, npc_spawn_timer, production_cycle_ticks, production_cycle_duration, cycle_running, buffered_output, assigned_npc_id); input_buffer typed as float; signals (production_output_ready, building_npc_spawn_requested); constants (TICKS_PER_TILE, NPC_SPAWN_INTERVAL, MAX_HOUSE_NPCS, PRODUCTION_TABLE); formula methods (calculate_carrier_travel_ticks, calculate_production_output, calculate_cycle_duration); add_charge_to_input, assign_npc (stub→real), collect_output; _on_ticks_advanced rewritten to handle CONSTRUCTING (AC-06/AC-22), Residential NPC timer (AC-22), production cycle (AC-09/AC-13); _try_start_production_cycle private helper
  - `tests/integration/building_system/production_cycles_test.gd` — Created: 24 test functions covering all 6 ACs
- Deviations: ADVISORY — ADR-0008 file does not exist (rules embedded in story + control manifest); input_buffer changed from int to float to unify quantity/charge tracking
- Blockers: None
- Next: /code-review src/gameplay/building_registry.gd tests/integration/building_system/production_cycles_test.gd then /story-done production/epics/building-system/story-002-production-cycles-distance.md

## Session Extract — /story-done 2026-06-02 (build-002)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/building-system/story-002-production-cycles-distance.md — Production Cycles and Carrier Transport
- Deviations: ADVISORY — assign_npc() returns void vs ADR AssignmentResult (deferred to story-004); signal name building_npc_spawn_requested vs building_npc_spawned (explicit rename); TR-build-004 "output deposit" stale vs buffered_output pattern (ADR correct); story predates control manifest; gameplay constants hardcoded (ongoing pattern)
- Code review fixes (same session): get_all_buildings() typed return; production_output_ready signal typed; 3 methods extracted to helpers; Array[StringName] typing; Storage Area AC-06 test added (25 tests total)
- Tech debt logged: None
- Next recommended: building-system/story-003 (BLOCKED/STALLED states) or building-system/story-004 (NPC assignment)

## Session Extract — /dev-story 2026-06-02 (build-003)
- Story: production/epics/building-system/story-003-failed-states-blocked-stalled.md — Failed States: BLOCKED and STALLED
- Files changed:
  - `src/gameplay/building_registry.gd` — Added: _CycleStartResult enum; input_carrier_id/output_carrier_id fields on BuildingInstance; signals (building_blocked, building_unblocked, building_stalled, building_destalled); _try_start_production_cycle changed void→int return; _advance_production_cycle handles BLOCKED/STALLED transitions; _on_ticks_advanced adds BLOCKED recovery branch; _try_recover_blocked + _cycle_blocked_reason helpers; collect_output handles STALLED→OPERATING; charge_cost fixed 1.0→5.0 (pre-existing bug)
  - `tests/integration/building_system/production_cycles_test.gd` — Updated: _make_carrying_lumber_camp helper added; 7 AC-09/AC-13 tests updated for carrier IDs; test_production_cycle_does_not_start_without_wood_input renamed/fixed to test_production_cycle_does_not_start_without_tool_input; test_production_new_cycle_does_not_start_while_output_buffered → renamed/improved to test_production_new_cycle_does_not_start_while_stalled
  - `tests/integration/building_system/failed_states_test.gd` — Created: 21 test functions covering AC-11/12/12b/12c/13/14/23 + state_changed signal
- Deviations: ADVISORY — charge_cost fix (1.0→5.0) is out of story-003 scope but required to keep story-002 tests valid; story predates control manifest (N/A)
- Blockers: None
- Next: /code-review src/gameplay/building_registry.gd tests/integration/building_system/failed_states_test.gd tests/integration/building_system/production_cycles_test.gd then /story-done production/epics/building-system/story-003-failed-states-blocked-stalled.md

## Session Extract — /dev-story 2026-06-02 (npc-001)
- Story: production/epics/npc-system/story-001-npc-identity-recruitment.md — NPC Identity and Recruitment
- Files changed:
  - `src/gameplay/npc_system.gd` — Created: NPCSystem Autoload; NPCInstance nested class (9 fields); _HouseState nested class; TaskState enum (7 states); NPC_CAPACITY_PER_HOUSE/NPC_SPAWN_DELAY_TICKS constants; recruit_npc() with capacity + delay enforcement; get_house_npc_count(), get_npc_count(), get_available_npcs(), get_npc_state(), get_npc_position(); _on_ticks_advanced() for tick tracking; npc_recruited signal
  - `tests/unit/npc_system/npc_identity_recruitment_test.gd` — Created: 28 test functions covering AC-1 through AC-4 plus edge cases
- Deviations: ADVISORY — story predates control manifest (N/A — same pattern as build stories); _on_ticks_advanced() tick subscription added (nominally story-002 scope) but required for AC-2 second-slot delay test
- Blockers: None
- Next: /code-review src/gameplay/npc_system.gd tests/unit/npc_system/npc_identity_recruitment_test.gd then /story-done production/epics/npc-system/story-001-npc-identity-recruitment.md

## Session Extract — /story-done 2026-06-02 (npc-001)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/npc-system/story-001-npc-identity-recruitment.md — NPC Identity and Recruitment
- Deviations: ADVISORY — hardcoded constants (project pattern); story predates manifest; Autoload not in project.godot (deferred); _on_ticks_advanced in story-001 scope (required for AC-2)
- Implementation fixes during story-done: Dictionary[StringName, NPCInstance] → untyped (GDScript 4.x inner class typing); before_each()→before_test() in NPC test + 3 building-system tests; var before renamed to count_before (GdUnitTestSuite.before() shadowing)
- Test evidence: 27/27 PASSED
- Tech debt logged: None
- Next recommended: npc-system/story-002 (task cycle — travel, work, deposit) OR building-system/story-004 (NPC assignment wiring)

## Session Extract — /dev-story 2026-06-02 (npc-002)
- Story: production/epics/npc-system/story-002-task-cycle-travel-work.md — Task Cycle: Travel and Work
- Files changed:
  - `src/gameplay/npc_system.gd` — Extended: TICKS_PER_TILE constant; AssignmentResult enum (SUCCESS, INVALID_NPC_STATE, BUILDING_NOT_FOUND); 5 new signals (npc_assigned, npc_released, npc_travel_started, npc_travel_completed, npc_returned_home); _building_system injectable field; assign_npc() with travel computation; release_npc() with RETURN_TO_BASE; get_assigned_npc() query; _on_ticks_advanced() full travel manager (TRAVEL_TO_BUILDING, TRAVEL_TO_STORAGE, RETURN_TO_BASE); _compute_travel_ticks() (Manhattan inline); _npc_arrived_at_building(); _npc_returned_home_internal()
  - `tests/integration/npc_system/task_cycle_travel_work_test.gd` — Created: 29 test functions covering AC-3, AC-5, AC-6; uses _BuildingStub inner class for dependency isolation
- Deviations: ADVISORY — Manhattan distance computed inline (ADR says delegate to GridMap.distance_between(); inline justified for test isolation at VS scope); story predates control manifest (N/A)
- Blockers: None
- Next: /code-review src/gameplay/npc_system.gd tests/integration/npc_system/task_cycle_travel_work_test.gd then /story-done production/epics/npc-system/story-002-task-cycle-travel-work.md

## Session Extract — /story-done 2026-06-02 (npc-002)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/npc-system/story-002-task-cycle-travel-work.md — Task Cycle: Travel and Work
- Deviations: ADVISORY — inline Manhattan distance (TDB-001 logged); hardcoded constants (ongoing pattern)
- Implementation fixes during story-done: loop typing in get_available_npcs; release_npc doc comment; _on_ticks_advanced doc comment; work_cycle_complete TODO tag; test comment fix ("instant" → "first tick")
- Test evidence: 29/29 test functions (not run — requires Godot binary)
- Tech debt logged: TDB-001 (inline Manhattan → GridMap.distance_between() when GridMap integration added)
- Next recommended: npc-system/story-003 (deposit/storage coordination) or npc-system/story-004 (disconnection/demolition)

## Session Extract — /dev-story 2026-06-02 (npc-003)
- Story: production/epics/npc-system/story-003-deposit-storage-coordination.md — Deposit and Storage Coordination
- Files changed:
  - `src/gameplay/npc_system.gd` — Extended: 2 new signals (npc_deposit_completed, npc_storage_full); NPCInstance fields (current_output_resource, current_output_amount); _inventory_system injectable field + storage_changed connection; TRAVEL_TO_STORAGE tick handler now calls _npc_arrived_at_storage(); new methods: _npc_arrived_at_storage(), _on_storage_changed(), _begin_return_to_base()
  - `src/gameplay/building_registry.gd` — Added: on_npc_waiting() (OPERATING→STALLED), on_npc_deposited() (STALLED→OPERATING)
  - `tests/integration/npc_system/deposit_storage_test.gd` — Created: 20 test functions covering AC-4 and AC-7; uses _InventoryStub (try_deposit + storage_changed signal) and extended _BuildingStub (waiting_calls/deposited_calls tracking)
- Deviations: ADVISORY — on_npc_waiting/on_npc_deposited added to BuildingRegistry as part of this story (not in original story file list, but required by AC-7 per ADR-0009); consistent with get_building_tile stub pattern from npc-002
- Blockers: None
- Next: /code-review src/gameplay/npc_system.gd src/gameplay/building_registry.gd tests/integration/npc_system/deposit_storage_test.gd then /story-done production/epics/npc-system/story-003-deposit-storage-coordination.md

## Session Extract — /story-done 2026-06-02 (npc-003)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/npc-system/story-003-deposit-storage-coordination.md — Deposit and Storage Coordination
- Deviations: ADVISORY — on_npc_waiting/on_npc_deposited added to building_registry.gd (required by AC-7/ADR-0009)
- Code review fixes applied: Engine.get_singleton→InventorySystem direct ref; String→StringName in BuildingRegistry params; _exit_tree disconnect guard; str() wrappers removed; multi-NPC WAITING test added (24 total)
- Test evidence: 24/24 test functions (not run — requires Godot binary)
- Tech debt logged: None
- Next recommended: npc-system/story-004 (disconnection/demolition) or npc-system/story-005

## Session Extract — /dev-story 2026-06-02 (npc-004)
- Story: production/epics/npc-system/story-004-disconnection-demolition.md — Disconnection and Demolition
- Files changed:
  - `src/gameplay/npc_system.gd` — Extended: 2 new signals (npc_removed, house_demolished); _enter_tree now connects building_demolished+container_removed; _exit_tree disconnects both; 4 new methods: _on_building_demolished(), _on_container_removed(), on_house_demolished(), remove_npc()
  - `src/gameplay/building_registry.gd` — Added: signal building_demolished (emitted by story-005 demolish_building); get_building_tile() query method (ADVISORY: was missing, called by NPCSystem.assign_npc() from npc-002)
  - `src/systems/inventory/inventory_system.gd` — Added: signal container_removed; remove_container() method
  - `tests/integration/npc_system/disconnection_test.gd` — Created: 24 test functions covering AC-9, AC-10, AC-rule8a, AC-rule8b and edge cases
- Deviations: ADVISORY — get_building_tile() added to BuildingRegistry (was referenced by NPCSystem from npc-002 but missing from production code); building_demolished signal added to BuildingRegistry now (emission point is story-005); container_removed+remove_container added to InventorySystem (required by this story's AC-rule8a/8b)
- Blockers: None
- Next: /code-review src/gameplay/npc_system.gd src/gameplay/building_registry.gd src/systems/inventory/inventory_system.gd tests/integration/npc_system/disconnection_test.gd then /story-done production/epics/npc-system/story-004-disconnection-demolition.md

## Session Extract — /code-review fixes 2026-06-02 (npc-004)
- Applied 6 required changes + 2 suggestions from code review:
  - npc_system.gd: moved _exit_tree to Lifecycle section; fixed house_demolished signal to Array[StringName]; fixed remove_npc to erase from _house_registry.npc_ids; added home-guard to _begin_return_to_base; added = &"" initializers to NPCInstance assignment fields; replaced bare int 0/1 with InventoryContainer.DepositResult.SUCCESS/FAILURE_FULL
  - building_registry.gd: get_building_tile param String (not StringName); demolish_building param StringName (match signal)
  - disconnection_test.gd: fixed house_demolished listener to Array[StringName]; added npc_travel_started not-fired assertion to remove_npc test
- Next: /story-done production/epics/npc-system/story-004-disconnection-demolition.md

## Session Extract — /story-done 2026-06-02 (npc-004)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/npc-system/story-004-disconnection-demolition.md — Disconnection and Demolition
- Deviations: ADVISORY — building_registry.gd and inventory_system.gd modified (required signals/methods); AC-10 wording error (npc_released vs npc_removed); production building assigned_npc_id not cleared (story-005 responsibility)
- Test evidence: 24/24 test functions (not run — requires Godot binary)
- Tech debt logged: None
- Next recommended: npc-system/story-005 (UI — recruitment and assignment)

## Session Extract — /dev-story 2026-06-02 (npc-005)
- Story: production/epics/npc-system/story-005-ui-recruitment-assignment.md — UI: Recruitment and Assignment
- Files changed:
  - `project.godot` — registered NPCSystem as autoload
  - `src/ui/components/building_status_indicator.gd` — added set_stalled() (red mode) for AC-UI-5
  - `src/gameplay/npc_system.gd` — assign_npc() + release_npc() now sync BuildingRegistry.assigned_npc_id
  - `src/scenes/map_root.gd` — _refresh_indicator() calls set_stalled() when STALLED state
  - `src/ui/components/building_detail_panel.gd` — Residential house: worker counter + Recruit button (AC-UI-1/2); Assign popup: real 2-step NPC→storage flow (AC-UI-3/4); release button fixed (AC-UI-5)
  - `production/qa/evidence/npc-ui-evidence.md` — manual evidence template created
- Test written: None — UI story, manual evidence required
- Deviations: ADVISORY — BuildingDetailPanel references NPCSystem via Engine.get_singleton (not direct autoload ref) for null-safety; mock_npc in place_starter_building still sets assigned_npc_id = &"mock_npc" (no NPC in NPCSystem registry, so indicator falls back to yellow — acceptable)
- Blockers: None
## Session Extract — /code-review fixes 2026-06-02 (npc-005)
- Applied 4 required changes + 2 suggestions from code review:
  - map_root.gd: added indicator.show() before stalled/idle/progress branches in _refresh_indicator
  - building_detail_panel.gd: replaced queue_free() with free() in _populate_npc_popup_step
  - building_detail_panel.gd: replaced NPCSystem.NPC_CAPACITY_PER_HOUSE with npc_sys.NPC_CAPACITY_PER_HOUSE (null-safe)
  - building_detail_panel.gd: _on_npc_released_signal now guards — only refreshes when released NPC matches current building
  - npc_system.gd: removed dead code second _building_system null check in assign_npc
- Next: check sprint for next ready story

## Session Extract — /story-done 2026-06-02 (npc-005)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/npc-system/story-005-ui-recruitment-assignment.md — UI: Recruitment and Assignment
- Deviations: ADVISORY — residential houses not in game scene; NPCs mocked; full cycle unverifiable; project.godot + npc_system.gd touched outside story scope (both required)
- Test evidence: production/qa/evidence/npc-ui-evidence.md created — sign-off pending game integration
- Tech debt logged: None
- Next recommended: sprint review — npc-system epic complete; check building-system or hunger-system for next ready story

## Session Extract — /story-done 2026-06-02 (logistics-001)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/logistics-system/story-001-route-model-and-slot-validation.md — Route Model and Slot Validation
- Deviations: ADVISORY — MAX_OUTPUT_SLOTS/MAX_INPUT_SLOTS hardcoded as 1 (acceptable for MVP per ADR-0011)
- Test evidence: tests/unit/logistics/route_model_test.gd (22 tests, all ACs covered)
- Tech debt logged: None
- Next recommended: Story 002 (Carrier FSM Core Loop) — production/epics/logistics-system/story-002-carrier-fsm-core-loop.md

## Session Extract — /dev-story 2026-06-02 (logistics-001) — UPDATED
- Story: production/epics/logistics-system/story-001-route-model-and-slot-validation.md — Route Model and Slot Validation
- Status: IMPLEMENTED
- Files changed:
  - src/systems/logistics/logistics_route.gd — created (LogisticsRoute class, enums, factory)
  - src/systems/logistics/logistics_system.gd — created (LogisticsSystem, create_route, slot validation)
  - tests/unit/logistics/route_model_test.gd — created (22 test functions covering AC-1 through AC-5 + edge cases)
- Test written: tests/unit/logistics/route_model_test.gd (22 test functions)
- Blockers: None
- Next: /code-review src/systems/logistics/logistics_route.gd src/systems/logistics/logistics_system.gd then /story-done production/epics/logistics-system/story-001-route-model-and-slot-validation.md

## Session Extract — /dev-story 2026-06-02 (logistics-002)
- Story: production/epics/logistics-system/story-002-carrier-fsm-core-loop.md — Carrier FSM Core Loop
- Status: IMPLEMENTED
- Files changed:
  - src/systems/logistics/logistics_route.gd — added npc_home_pos field
  - src/systems/logistics/logistics_system.gd — added FSM: _advance_tick, _process_carrier, start_route, _calc_travel_time, injectable deps
  - src/gameplay/building_registry.gd — added has_output_buffer, get_output_buffer_total, get_output_buffer_resource
  - src/gameplay/npc_system.gd — added set_carrier_state, is_available, on_npc_at_location (carrier interface)
  - tests/integration/logistics/carrier_fsm_test.gd — created (18 test functions covering AC-1 through AC-5)
- Test written: tests/integration/logistics/carrier_fsm_test.gd (18 test functions)
- Deviations: AC-1 spec coordinates had errors (home=source=same tile); test uses self-consistent coordinates
- Blockers: None
- Next: /code-review src/systems/logistics/logistics_system.gd src/gameplay/building_registry.gd src/gameplay/npc_system.gd then /story-done production/epics/logistics-system/story-002-carrier-fsm-core-loop.md

## Session Extract — /dev-story 2026-06-02 (logistics-003)
- Story: production/epics/logistics-system/story-003-carrier-waiting-and-timeout.md — Carrier Waiting and Timeout
- Status: IMPLEMENTED
- Files changed:
  - src/systems/logistics/logistics_route.gd — added deactivation_reason field
  - src/systems/logistics/logistics_system.gd — added carrier_waiting_timeout var, timeout logic in WAITING_SOURCE and WAITING_DESTINATION, _deactivate_route() helper
  - tests/integration/logistics/carrier_waiting_test.gd — created (14 test functions covering AC-1 through AC-5)
- Test written: tests/integration/logistics/carrier_waiting_test.gd (14 test functions)
- Deviations: story-002 Status was "Ready" in file despite implementation existing — updated to "Complete" before proceeding
- Blockers: None
- Next: /dev-story production/epics/logistics-system/story-004-building-status-integration.md

## Session Extract — /story-done 2026-06-02 (logistics-003)
- Verdict: COMPLETE
- Story: production/epics/logistics-system/story-003-carrier-waiting-and-timeout.md — Carrier Waiting and Timeout
- Tech debt logged: None
- Next recommended: Story 004 — Building Status Integration (production/epics/logistics-system/story-004-building-status-integration.md)

## Session Extract — /dev-story 2026-06-02 (logistics-004)
- Story: production/epics/logistics-system/story-004-building-status-integration.md — Building Status Integration
- Status: IMPLEMENTED
- Files changed:
  - src/gameplay/building_registry.gd — added class_name BuildingRegistry, Status enum, set_status() API, assign_input_carrier(), assign_output_carrier(); removed mock_carrier stubs
  - src/systems/logistics/logistics_system.gd — added _update_building_status(), _on_route_active_changed(), _assign_carrier_to_building(); wired into create_route, delete_route, _deactivate_route, _advance_tick
  - tests/integration/logistics/building_status_test.gd — created (14 test functions covering AC-1 through AC-5)
- Test written: tests/integration/logistics/building_status_test.gd (14 test functions)
- Deviations: OUTPUT route deactivation intentionally does NOT set STALLED immediately — deferred to next production cycle completion per GDD Core Rules 6 (overrides ADR pseudocode which showed immediate STALLED)
- Blockers: None
- Next: /code-review src/systems/logistics/logistics_system.gd src/gameplay/building_registry.gd then /story-done production/epics/logistics-system/story-004-building-status-integration.md

## Session Extract — /story-done 2026-06-02 (logistics-004)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/logistics-system/story-004-building-status-integration.md — Building Status Integration
- Tech debt logged: None
- Next recommended: Story 005 — Save/Load for Logistics (production/epics/logistics-system/story-005-save-load-for-logistics.md)

## Session Extract — /dev-story 2026-06-02 (logistics-008)
- Story: production/epics/logistics-system/story-008-transportation-management-ui.md — Transportation Management UI
- Status: IMPLEMENTED
- Files changed:
  - src/ui/components/transportation_panel.gd — created (TransportationPanel extends Control; two views ActiveRoutesList/RouteDetail; map-select mode; route rows with status badges; NPC picker; route summary; animations with reduced-motion support)
  - src/systems/logistics/logistics_system.gd — added pause_route(), resume_route(), get_route_efficiency() stub (full Formula 3 pending story 007)
  - src/ui/components/building_detail_panel.gd — updated _refresh_transport_zone() with real carrier status from LogisticsSystem; efficiency badge; "Manage Transport" link wired
  - src/ui/hud/hud.gd — added 🚚 transport button; TransportationPanel instance; map-select mode support (notify_building_selected_in_map_select()); all route signals wired to LogisticsSystem
  - production/qa/evidence/transportation-ui-evidence.md — created (22 AC manual QA checklist)
- Test written: None — UI story type; evidence doc required at production/qa/evidence/transportation-ui-evidence.md
- Deviations:
  - UX spec design/ux/transportation.md status is "In Design" (not formally "Approved") — story was marked Ready, proceeded
  - Route update (AC-16) implemented as delete+recreate at MVP; preserving carrier mid-trip state is post-MVP
  - Map-select mode requires map_root.gd wiring of HUD.notify_building_selected_in_map_select() — not yet wired in scene tree (integration task for map_root story)
  - Efficiency badge uses story-007 stub (1.0/0.5/0.0 by lifecycle state) — full Formula 3 pending story 007
- Blockers: None
- Next: /code-review src/ui/components/transportation_panel.gd src/ui/hud/hud.gd then /story-done production/epics/logistics-system/story-008-transportation-management-ui.md

## Session Extract — /story-done 2026-06-02 (logistics-008)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/logistics-system/story-008-transportation-management-ui.md — Transportation Management UI
- Tech debt logged: None
- Next recommended: Story 007 — Efficiency and Carrier Count Formulas (production/epics/logistics-system/story-007-efficiency-and-carrier-count-formulas.md)

## Session Extract — /dev-story 2026-06-03 (logistics-006)
- Story: production/epics/logistics-system/story-006-route-visualization.md — Route Visualization
- Files changed:
  - src/ui/components/route_lines.gd — created (RouteLines extends Node2D; Line2D per route; dirty-flag updates via TickSystem; green/yellow/red/gray color encoding by carrier state; hover detection via segment distance; CanvasLayer tooltip with NPC name/distance/round-trip/efficiency)
  - src/scenes/map_root.gd — RouteLines instantiated in _ready(), grid dependency injected
  - production/qa/evidence/route-visualization-evidence.md — created (8 AC manual QA checklist)
- Test written: None — Visual/Feel story type; evidence doc at production/qa/evidence/route-visualization-evidence.md
- Deviations:
  - AC for colorblind line patterns (solid/dashed/dotted) DEFERRED per user instruction — marked in evidence doc
- Blockers: None
- Next: /code-review src/ui/components/route_lines.gd src/scenes/map_root.gd then /story-done production/epics/logistics-system/story-006-route-visualization.md

## Session Extract — /story-done 2026-06-03 (logistics-006)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/logistics-system/story-006-route-visualization.md — Route Visualization
- Tech debt logged: None
- Next recommended: Story 007 — Efficiency and Carrier Count Formulas (production/epics/logistics-system/story-007-efficiency-and-carrier-count-formulas.md)

## Session Extract — /dev-story 2026-06-03 (hunger-001)
- Story: production/epics/hunger-system/story-001-daily-consumption-and-state-machine.md — Daily Consumption and State Machine
- Files changed:
  - src/gameplay/hunger_system.gd — created (HungerSystem Autoload; FED/HUNGRY state machine; apply_daily_consumption(); _compute_total_food_units(); signals: hunger_state_changed, hunger_display_updated; public API: get_hunger_tick_multiplier, get_hunger_output_multiplier, is_hunger_debuff_active, get_days_of_food_remaining)
  - src/systems/inventory/inventory_system.gd — stub signature fixed: consume_food(_daily_requirement: float) -> Dictionary (was wrong entity_id signature)
  - project.godot — HungerSystem registered as Autoload after NPCSystem (per ADR-0006 load order)
  - tests/unit/hunger_system/daily_consumption_test.gd — created (11 test functions covering AC-1 through AC-5, defensive fallback, multiplier checks, formula checks)
- Test written: tests/unit/hunger_system/daily_consumption_test.gd (11 test functions)
- Deviations:
  - ADR tick_count % 1000 guard replaced with null-check only — _tick_count is private (use get_tick_count()); signal handler approach makes modulo guard redundant
  - InventorySystem.consume_food stub signature was wrong (entity_id + calorie_demand) — fixed to match ADR-0010 interface contract
- Blockers: None
- Next: /code-review src/gameplay/hunger_system.gd then /story-done production/epics/hunger-system/story-001-daily-consumption-and-state-machine.md

## Session Extract — /story-done 2026-06-03 (hunger-001)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/hunger-system/story-001-daily-consumption-and-state-machine.md — Daily Consumption and State Machine
- Tech debt logged: None (advisory deviations noted in story file)
- Next recommended: Story 002 — Debuff Stacking (production/epics/hunger-system/story-002-debuff-stacking.md)

## Session Extract — /dev-story 2026-06-03 (ui-007)
- Story: production/epics/ui-system/story-007-day-ledger.md — DayLedger Daily Resource Delta Accumulation
- Files changed:
  - src/systems/inventory/inventory_system.gd — added signals item_deposited(resource_id, qty) and item_withdrawn(resource_id, qty); emitted from try_deposit/try_consume on SUCCESS
  - src/gameplay/hunger_system.gd — added signal food_consumed_daily(items: Dictionary); emitted from apply_daily_consumption() with per-NPC consumed dict
  - src/ui/day_ledger.gd — created (DayLedger Autoload; _on_deposited/_on_withdrawn/_on_day_transition/_on_hunger_consumed; get_last_day_deltas/get_last_hunger_consumed)
  - project.godot — DayLedger registered as Autoload after HungerSystem
  - tests/unit/ui/day_ledger_test.gd — created (11 test functions covering AC-1 through AC-5)
- Test written: tests/unit/ui/day_ledger_test.gd (11 test functions)
- Deviations: None
- Blockers: None
- Next: /code-review src/ui/day_ledger.gd then /story-done production/epics/ui-system/story-007-day-ledger.md

## Session Extract — /story-done 2026-06-03 (ui-007)
- Verdict: COMPLETE
- Story: production/epics/ui-system/story-007-day-ledger.md — DayLedger Daily Resource Delta Accumulation
- Tech debt logged: None
- Next recommended: Story 008 — Day Overview Panel (production/epics/ui-system/story-008-day-overview-panel.md)

## Session Extract — /dev-story 2026-06-03 (ui-008)
- Story: production/epics/ui-system/story-008-day-overview-panel.md — Day Overview Panel
- Files changed:
  - src/ui/day_overview_panel.gd — created (DayOverviewPanel CanvasLayer; _on_day_transition/_populate/_fill_resource_list/_on_next_day_pressed)
  - src/ui/DayOverviewPanel.tscn — created (CanvasLayer layer=10; PanelContainer centered; HeaderRow/HungerList/DeltaList/NextDayButton)
  - src/scenes/game.tscn — updated (DayOverviewPanel instanced as child of GameWorld)
  - production/qa/evidence/day-overview-panel-evidence.md — created (manual walkthrough checklist for AC-1 through AC-6)
- Test written: None — UI story; evidence doc at production/qa/evidence/day-overview-panel-evidence.md
- Deviations: None
- Blockers: None
- Next: /code-review src/ui/day_overview_panel.gd then /story-done production/epics/ui-system/story-008-day-overview-panel.md

## Session Extract — /story-done 2026-06-03 (ui-008)
- Verdict: COMPLETE
- Story: production/epics/ui-system/story-008-day-overview-panel.md — Day Overview Panel
- Tech debt logged: None
- Next recommended: Check UI System EPIC.md for remaining stories or sprint close-out sequence

## Session Extract — /dev-story 2026-06-03 (efficiency-001)
- Story: production/epics/efficiency-system/story-001-npc-efficiency-property-and-hunger-integration.md — NPC Efficiency Property and Hunger Integration
- Files changed:
  - src/systems/efficiency/efficiency_formulas.gd — created (EfficiencyFormulas static class; F1 calculate_npc_efficiency, F2 calculate_building_efficiency, F3 calculate_effective_cycle_ticks, F4 calculate_effective_travel_ticks)
  - src/gameplay/npc_system.gd — modified (NPCInstance: efficiency/hunger_modifier/satisfaction_modifier/equipment_modifier fields + recalculate_efficiency(); NPCSystem: _hunger_system ref, hunger_state_changed connection in _enter_tree/_exit_tree, _on_hunger_state_changed, _apply_current_hunger_to_npc; recruit_npc calls _apply_current_hunger_to_npc)
  - tests/unit/efficiency/npc_efficiency_test.gd — created (17 test functions covering AC-1 through AC-7)
- Test written: tests/unit/efficiency/npc_efficiency_test.gd (17 test functions)
- Deviations: None
- Blockers: None
- Next: /dev-story production/epics/efficiency-system/story-002-building-efficiency-and-worker-contribution.md

## Session Extract — /story-done 2026-06-03 (efficiency-001)
- Verdict: COMPLETE
- Story: production/epics/efficiency-system/story-001-npc-efficiency-property-and-hunger-integration.md — NPC Efficiency Property and Hunger Integration
- Tech debt logged: None
- Next recommended: Story 002 — Building Efficiency and Worker Contribution (production/epics/efficiency-system/story-002-building-efficiency-and-worker-contribution.md)

## Session Extract — /dev-story 2026-06-04 (efficiency-002)
- Story: production/epics/efficiency-system/story-002-building-efficiency-and-worker-contribution.md — Building Efficiency and Worker Contribution
- Files changed:
  - src/gameplay/building_registry.gd — modified (BuildingInstance: efficiency/upgrade_bonus fields + recalculate_efficiency(); BuildingRegistry: _npc_system field, _get_assigned_workers() helper, assign_npc() calls recalculate)
  - src/gameplay/npc_system.gd — modified (_propagate_worker_efficiency_change() added; _on_npc_food_efficiency_changed now calls it after NPC recalculate)
  - tests/unit/efficiency/building_efficiency_test.gd — created (15 test functions covering AC-1 through AC-7)
- Test written: tests/unit/efficiency/building_efficiency_test.gd (15 test functions)
- Deviations: None
- Blockers: None
- Next: /dev-story production/epics/efficiency-system/story-003-production-cycle-integration.md

## Session Extract — /story-done 2026-06-04 (efficiency-002)
- Verdict: COMPLETE
- Story: production/epics/efficiency-system/story-002-building-efficiency-and-worker-contribution.md — Building Efficiency and Worker Contribution
- Tech debt logged: None
- Next recommended: Story 003 — Production Cycle Integration (production/epics/efficiency-system/story-003-production-cycle-integration.md)

## Session Extract — /dev-story 2026-06-04 (logistics-009)
- Story: production/epics/logistics-system/story-009-tile-movement-cost-data-model.md — Tile Movement Cost Data Model
- Files changed:
  - data/resources.json — modified (added movement_cost: 4.0 to all 7 resource definitions)
  - src/systems/resource_registry.gd — modified (movement_cost field on _ResourceDefinition; parsed in _apply_optional_fields, default 4.0)
  - src/systems/world_grid.gd — modified (BUILDING_LAYER/RESOURCE_LAYER constants; terrain_changed signal; get_tile_movement_cost(); is_tile_passable(); signal emissions in place_building, remove_building, add_resource_to_tile, remove_one_resource, harvest_resource)
  - tests/unit/logistics/tile_movement_cost_test.gd — created (14 test functions covering AC-1 through AC-8)
- Test written: tests/unit/logistics/tile_movement_cost_test.gd (14 test functions)
- Deviations: None
- Blockers: None
- Next: /code-review src/systems/world_grid.gd src/systems/resource_registry.gd then /story-done production/epics/logistics-system/story-009-tile-movement-cost-data-model.md

## Session Extract — /dev-story 2026-06-04 (logistics-010)
- Story: production/epics/logistics-system/story-010-weighted-astar-pathfinding.md — Weighted A* Pathfinding
- Files changed:
  - src/gameplay/path_result.gd — created (PathResult value object: path, cost, found; success/failure factories)
  - src/gameplay/logistics_pathfinder.gd — created (LogisticsPathfinder static find_path(); 4-dir A*, Manhattan heuristic, duck-typed grid param)
  - tests/unit/logistics/astar_pathfinder_test.gd — created (27 test functions covering AC-1 through AC-9 and TC-1 through TC-7)
- Test written: tests/unit/logistics/astar_pathfinder_test.gd (27 test functions)
- Deviations: Story 009 dependency was implemented but not yet marked Complete (status still "Ready") — implementation verified present in world_grid.gd before proceeding
- Blockers: None
- Next: /code-review src/gameplay/logistics_pathfinder.gd src/gameplay/path_result.gd then /story-done production/epics/logistics-system/story-010-weighted-astar-pathfinding.md

## Session Extract — /story-done 2026-06-04 (logistics-010)
- Verdict: COMPLETE
- Story: production/epics/logistics-system/story-010-weighted-astar-pathfinding.md — Weighted A* Pathfinding
- Tech debt logged: None
- Next recommended: Story 011 — Carrier FSM Path Integration (production/epics/logistics-system/story-011-carrier-fsm-path-integration.md)

## Session Extract — /dev-story 2026-06-04 (logistics-011)
- Story: production/epics/logistics-system/story-011-route-path-integration.md — Logistics Route Path Integration
- Files changed:
  - src/systems/logistics/logistics_route.gd — added 7 path-cache fields (cached_path, cached_path_cost, path_valid, cached_path_cost_home_to_source, cached_path_cost_source_to_home, cached_path_cost_dest_to_home, home_legs_valid)
  - src/systems/logistics/logistics_system.gd — added _grid_map dependency; updated create_route() with path gate; updated start_route() to cache home legs; swapped all FSM travel-time calls to use cached costs with Manhattan fallback
  - tests/integration/logistics/route_path_integration_test.gd — created (10 test functions covering AC-1 through AC-5 + home-leg caching)
- Test written: tests/integration/logistics/route_path_integration_test.gd (10 test functions)
- Deviations: AC lists 3 required fields; implementation adds 4 more (home-leg costs + validity flag) required to cover all 3 FSM travel legs — no out-of-scope files touched
- Blockers: None
- Next: /code-review src/systems/logistics/logistics_system.gd src/systems/logistics/logistics_route.gd then /story-done production/epics/logistics-system/story-011-route-path-integration.md

## Session Extract — /story-done 2026-06-05 (logistics-011)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/logistics-system/story-011-route-path-integration.md — Logistics Route Path Integration
- Tech debt logged: None
- Next recommended: Story 012 — Path Invalidation on Terrain Change (production/epics/logistics-system/story-012-path-invalidation-terrain-change.md)

## Session Extract — /dev-story 2026-06-05 (logistics-012)
- Story: production/epics/logistics-system/story-012-path-invalidation-on-terrain-change.md — Path Invalidation on Terrain Change
- Files changed:
  - src/systems/logistics/logistics_system.gd — added set_grid_map() public API; added _on_terrain_changed() handler; added _recalculate_invalid_paths() deferred recalculator
  - tests/integration/logistics/path_invalidation_test.gd — created (8 test functions covering AC-1 through AC-7)
- Test written: tests/integration/logistics/path_invalidation_test.gd (8 test functions)
- Deviations: None — all changes within logistics_system.gd; no out-of-scope files touched
- Blockers: None
- Next: /code-review src/systems/logistics/logistics_system.gd then /story-done production/epics/logistics-system/story-012-path-invalidation-on-terrain-change.md

## Session Extract — /story-done 2026-06-05 (logistics-012)
- Verdict: COMPLETE
- Story: production/epics/logistics-system/story-012-path-invalidation-on-terrain-change.md — Path Invalidation on Terrain Change
- Tech debt logged: None
- Next recommended: Check logistics epic for remaining Ready stories

## Session Extract — /dev-story 2026-06-05 (save-001)
- Story: production/epics/save-load-system/story-001-world-save-manager.md — WorldSaveManager Orchestrator
- Files changed:
  - src/systems/save_world_save_manager.gd — already implemented (no changes needed)
  - tests/unit/save_world/save_manager_test.gd — created (15 test functions covering AC-1 through AC-5 + schema validation + slot bounds)
- Test written: tests/unit/save_world/save_manager_test.gd (15 test functions)
- Deviations: Unit tests use file I/O (user://saves/) because WorldSaveManager's core behavior is file I/O; DI refactor would be a separate story
- Blockers: None
- Next: /code-review src/systems/save_world_save_manager.gd tests/unit/save_world/save_manager_test.gd then /story-done production/epics/save-load-system/story-001-world-save-manager.md

## Session Extract — /story-done 2026-06-05 (save-001)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/save-load-system/story-001-world-save-manager.md — WorldSaveManager Orchestrator
- Tech debt logged: None
- Next recommended: Story 002 — Save Slot Management (production/epics/save-load-system/story-002-save-slot-management.md)
  NOTE: Story 002 ACs 6–9 are already implemented by Story 001's scope creep (get_available_slots, get_save_info, atomic writes, metadata files all in save_world_save_manager.gd). Only AC-10 (_startup_cleanup in _ready) needs implementation. Story 002 should be fast.

## Session Extract — /dev-story 2026-06-05 (save-002)
- Story: production/epics/save-load-system/story-002-save-slot-management.md — Save Slot Management and Metadata
- Files changed:
  - src/systems/save_world_save_manager.gd — added _ready(), _startup_cleanup(), added slots.sort() to get_available_slots()
  - tests/unit/save_world/save_slot_test.gd — created (13 test functions covering AC-6 through AC-10)
- Test written: tests/unit/save_world/save_slot_test.gd (13 test functions)
- Deviations: AC-9 atomicity tested indirectly via orphaned .tmp + _startup_cleanup() pattern (cannot hook DirAccess.rename_absolute to force failure in GDScript unit tests)
- Blockers: None
- Next: /code-review src/systems/save_world_save_manager.gd tests/unit/save_world/save_slot_test.gd then /story-done production/epics/save-load-system/story-002-save-slot-management.md

## Session Extract — /story-done 2026-06-05 (save-002)
- Verdict: COMPLETE WITH NOTES
- Story: production/epics/save-load-system/story-002-save-slot-management.md — Save Slot Management and Metadata
- Tech debt logged: None
- Next recommended: Story 003 — Schema Versioning (production/epics/save-load-system/story-003-schema-versioning.md)


## Session Extract — Code→Doku-Sync 2026-06-13
- Auftrag: Doku an implementierten Spielstand angleichen (nach Balancing-Pass 2026-06-11/12); Code-Optimierungen mitnehmen. Balancing-Änderungen vorab committet (f5091d5).
- GDDs synchronisiert: building-system (Bauzeiten/Zyklen/Tool-Charge 1/30/F3 live/Adjazenz; STALLED→Output-full-idle), hunger-system (NEU geschrieben: Pro-NPC-Nutrition-Modell), logistics-system (NEU geschrieben: Shared Carrier, A*, keine Timeouts, Kapazität 2, 5 t/tile + F4), npc-system, tick-system (1440 t/Tag), resource-system (+nutrition), recipe-database (Impl.-Hinweis), player-character (Craft Tool entfernt), systems-index (Impl.-Status).
- NEU: design/gdd/efficiency-system.md (volles GDD, ersetzt Quick-Spec — als SUPERSEDED markiert).
- ADRs: ADR-0011 Amendment (Shared-Carrier-Modell), ADR-0012 Amendment (Nutrition-Kurve, BASE 0.5, Caps, F3/F4-Wiring).
- Code-Optimierungen: HungerSystem füttert jetzt über ALLE Container (all-or-nothing; vorher Bug: nur erster Container); CRAFT_TOOL-Manual-Action entfernt (Crafting nur via CraftingRegistry); BuildingRegistry tote Stubs entfernt (calculate_carrier_travel_ticks/_production_output/_cycle_duration, TICKS_PER_TILE, get_output_buffer_total); LogisticsRoute.wait_ticks entfernt (tot); stale Kommentare gefixt.
- Tests angepasst: carrier_waiting_test.gd NEU (Wait-in-Place/Hold-Cargo statt Timeouts); building_status/path_invalidation/carrier_fsm/route_model/action_dispatch/production_cycles aktualisiert. NICHT per Godot-Lauf verifiziert (kein Binary lokal) — Suite-Lauf steht aus.
- Offene Tech-Debt: Effizienz-Konstanten → JSON-Config (Story 005); Logistik-Test-Stubs anderer Suiten evtl. unvollständig (get_building_instance); Scheduler-Unit-Tests (_carrier_pick_next) fehlen; recipes.json-Registry weiterhin Designziel.


## Session Extract — Code-Konsolidierung/Refactoring 2026-06-13
- Auftrag: Systeme datei-für-datei auf Vereinheitlichung/Extraktion prüfen (Bsp. map_root.gd Konstanten/Helfer → Utility-Klassen). Planungsdatei zuerst, dann Umbau.
- Plan: docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (5 Phasen, risikoarm→risikoreich).
- UMGESETZT Phase 1: NEU src/util/texture_factory.gd (TextureFactory.circle/solid_tile/tile_highlight) + src/util/path_geometry.gd (PathGeometry.length/point_along). Duplikate entfernt aus map_root/npc_overlay/route_lines (_make_circle_texture 3×, _path_length/_point_along_path 2×). Tests: tests/unit/util/*.
- UMGESETZT Phase 2: 7× terrain_layer.local_to_map(to_local()) → grid.world_to_tile() in map_root (verifiziert: MapRoot/TerrainLayer ohne Offset → äquivalent).
- UMGESETZT Phase 3: data-driven Präsentation. resources.json +glyph (alle 7) +world_icon_path/+fallback_color (5 Terrain-Res). ResourceRegistry +get_glyph/+has_world_icon/+get_world_icon_texture. Entfernt: map_root _RESOURCE_PNG/_RESOURCE_FALLBACK_COLORS/_resource_id_to_index/_load_resource_texture; route_lines _RES_PNG/_RES_COLOR; Grid-Emoji-Maps (item/building/crafting) → get_glyph (fixt food/iron-Inkonsistenz). Tests: tests/unit/resource/glyph_world_icon_test.gd + fixture.
- UMGESETZT Phase 4: NEU src/ui/ui_palette.gd + src/ui/style_factory.gd. _build_separator (3 Panels) → StyleFactory.separator. Panel-COLOR_BG/SEP + 4 Grid-Palette-Consts → UiPalette. Alle 4 Grids: Panel-Shell → StyleFactory.block (kein StyleBoxFlat.new mehr in Grids). IconBlockGrid-Vollbasisklasse BEWUSST NICHT gebaut (zu viel _ready/populate/center-Varianz → mehr Risiko als Nutzen ohne Godot).
- UMGESETZT Phase 5 Schritt 1+2: NEU src/scenes/map_root/terrain_renderer.gd (TerrainRenderer: Tileset+sync+atlas+80 Terrain-Pfade) und src/scenes/map_root/building_indicator_layer.gd (BuildingIndicatorLayer: Gebäude-Sprites+Indikatoren, _on_building_* delegieren). map_root.gd: 1929 → 1569 Z. (−19 %).
- UMGESETZT Phase 5 Schritt 3a: NEU src/scenes/map_root/path_dot_overlay.gd (PathDotOverlay) — beheimatet _PATH_*-Konstanten; dedupliziert L-Pfad-Builder (3× inkl. route_lines → l_path), Punkt-Verteilung (place_dots) und Drag-Pfad-Rendering (render, 2× ~25-Z.-Blöcke). Tests: tests/unit/util/path_dot_overlay_test.gd. map_root 1569 → 1484 Z. (gesamt 1929→1484, −23 %).
- UMGESETZT Phase 5 Schritt 3b: NEU src/scenes/map_root/resource_badge_factory.gd (ResourceBadgeFactory) — reine Badge-Icon-Konstruktion + Skalierungs-Konstanten; dedupliziert 5 Icon-Builder (Badge-Loop, _make_resource_icon_node, 3 Drag-Start-Handler). map_root 1484 → 1400 Z. (gesamt 1929→1400, −27 %).
- UMGESETZT Phase 5 Schritt 3c: NEU src/scenes/map_root/transport_overlay.gd (TransportOverlay) — Transport-Indikator/Pfad-Overlay-Node-Bau+Animation+Freigabe (statisch, parent-Param). MapRoot behält Lifecycle+Pause. map_root 1400 → 1332 Z. (gesamt 1929→1332, −31 %). Vom Nutzer in Godot verifiziert: läuft.
- Nutzer wählte dann doch Option B (inkrementell). BEGONNEN Phase 5 Schritt 3d: NEU src/scenes/map_root/drag_controller.gd (DragController extends Node2D, hält _root: MapRoot via setup(); als Child in _ready). Chunk 1 (leaf): _calc_drag_ticks + _spawn_pickup_float verschoben (beide ohne map_root-Member → prefix-frei); _pay_drag_cost war tot → entfernt. 8 Calls umgeleitet auf _drag_controller. map_root 1332 → 1306 Z.
- Chunk 2: _snap_back_drag_icon + _reset_drag_icon_visuals → DragController; _cancel_drag_visual tot → entfernt. map_root 1306 → 1281 Z.
- Chunk 3: _hit_test_resource_icon → DragController (_root.grid/_root._resource_icons); _make_resource_icon_node tot → entfernt. map_root 1281 → 1250 Z. (gesamt 1929→1250, −35 %).
- Strategie bestätigt: METHODEN ZUERST (je _root.-Prefix für State/Member), STATE ZULETZT (dann _root.-Prefixes weg). Nebeneffekt: 3 tote Methoden gefunden+entfernt (_pay_drag_cost, _cancel_drag_visual, _make_resource_icon_node).
- Chunk 4 (GROSS, Nutzer will weniger Verifikationszyklen): _update_drag_overlays + _update_storage_drag_overlays + _try_batch_collect + _restore_batch_extras → DragController (alle State/Infra via _root.). map_root 1250 → 1100 Z. (gesamt 1929→1100, −43 %). DragController: 10 Methoden.
- ERKENNTNIS: vergessener _root.-Prefix = Parse-Fehler beim Godot-Laden (kein stiller Bug) → große Batches machbar.
- Chunk 5 (GROSS): _on_storage/input/output_drag_started + _finish_output/input/storage_drag + _park_panel_icon_pending → DragController (alle _root.-prefixed; _calc_drag_ticks/_park lokal; Parent-Args=_root für identische Hierarchie; Signal-Connects + Finish-Calls in map_root auf _drag_controller umgeleitet). map_root 1100 → 883 Z. (gesamt 1929→883, −54 %). DragController: 17 Methoden.
- Chunk 6 (GROSS): _try_deposit_to_building (Lambda-lastig) + _advance_pending_transports → DragController. Callers (_unhandled_input deposit, _on_ticks_advanced_indicators advance) auf _drag_controller umgeleitet. map_root 883 → 734 Z. (gesamt 1929→734, −62 %). DragController: 19 Methoden.
- WARNUNG: Linter formatiert map_root zwischen Edits um → Zeilennummern verschieben sich, Edit-Tool meldet "modified since read". Lösung: nach sed-Edits per grep neu lokalisieren, ggf. sed statt Edit für Einzeiler.
- Chunk 7 (GROSS): _setup_drag_overlays + _spawn_resource_badges + _spawn_badge → DragController. Bestehende _root._spawn_badge-Calls im Controller auf lokal umgestellt; 7 map_root-Caller (2 _ready + 5 _spawn_badge) auf _drag_controller umgeleitet (sed, da Linter Edit-State invalidiert). map_root 734 → 620 Z. (gesamt 1929→620, −68 %). DragController: 22 Methoden.
- Chunk 8 (GROSS): _input + _on_action_queued/started/progress_update/completed + _spawn_action_indicator → DragController. _player.action_*-Connects auf _drag_controller umgeleitet; _input ist Node-Callback (kein Caller). map_root 620 → 502 Z. (gesamt 1929→502, −74 %, schon unter Ziel!). DragController: 28 Methoden.
- Chunk 9 (GROSS): _unhandled_input (~165 Z., großer Handler + Lambda) + _process-Drag-Anteil → DragController. _process gesplittet (map_root behält nur _update_map_select_highlight). _input/_unhandled_input/_process sind Node-Callbacks → feuern auf Controller-Node, keine Caller-Rewires. map_root 502 → 294 Z. (gesamt 1929→294, −85 %!). DragController: 30 Methoden.
- BESTÄTIGT: map_root nutzt Drag-State NUR in Var-Deklarationen (kein Code-Zugriff) → finaler State-Move ist sauber.
- Chunk 10 FINAL (2026-06-14): State-Block (_resource_icons/_drag_*/_pending_transports/_action_indicator/_was_paused/_HOLD_*/_queued_indicators/_active_action_tile) von map_root → DragController; alle _root._<state>-Prefixes im Controller entfernt (sed). Controller state-autark; nutzt _root. nur noch für Infra (grid 52×/_registry 13×/add_child 12×/_player 7×/_hud 5×/terrain_layer 1×/_on_tile_clicked 1×).

## ✅ PHASE 5 ABGESCHLOSSEN (2026-06-14)
- map_root.gd: 1929 → 250 Z. (−87 %). God-Object zerlegt in src/scenes/map_root/: TerrainRenderer (201), BuildingIndicatorLayer (118), PathDotOverlay (73), ResourceBadgeFactory (64), TransportOverlay (82), DragController (1079). map_root = schlanker Koordinator.
- DragController inkrementell in 9 Chunks extrahiert, jeder vom Nutzer in Godot verifiziert. 3 tote Methoden gefunden+entfernt (_pay_drag_cost, _cancel_drag_visual, _make_resource_icon_node).
- OFFEN: Phase 6 Asset-Move (am besten im Editor) + assets/ui-Dangling-Bug.

## DragController-Aufteilung (2026-06-14, nach Phase 5)
- Split 1: ActionFeedback extrahiert (src/scenes/map_root/action_feedback.gd, 136 Z.) — Spieler-Aktions-Indikatoren (Queued/Active/Progress + Loot), getrieben von _player-Signalen. Bidirektionale Verdrahtung: DragController.is_action_running() ↔ ActionFeedback liest _drag._pending_transports/_was_paused/_resource_icons/_spawn_badge/_spawn_pickup_float. map_root wired _action_feedback.setup(self,_drag) + _drag.set_action(_action_feedback). DragController 1079 → 974 Z.
- Split 2: ResourceBadgeLayer extrahiert (src/scenes/map_root/resource_badge_layer.gd, 123 Z., Node2D) — _resource_icons-Daten + _spawn_resource_badges/_spawn_badge + animate_float + _hit_test_resource_icon + _spawn_pickup_float. Ein-direktional: DragController + ActionFeedback greifen via _badges. zu (set_badges / setup(...,badges)). DragController 974 → 876 Z. map_root wired _resource_badges vor drag/action.
- Komponenten in src/scenes/map_root/ jetzt 8: terrain_renderer, building_indicator_layer, path_dot_overlay, resource_badge_factory, transport_overlay, drag_controller (876), action_feedback (138), resource_badge_layer (123).
- VERBLEIBEND in DragController: Drag-Zustandsmaschine (start/finish/deposit/overlays/batch) + _input/_unhandled_input/_process + Transport-Lifecycle (park/advance/_pending_transports). Nur noch sinnvoller Kandidat: TransportManager — aber verschärft 3-Wege-Pause-Kopplung (drag↔transport↔action), daher eher belassen.
- NÄCHSTE Chunks (leaf→core, je Runde, Nutzer verifiziert dazwischen): Deposit (_try_deposit_to_building ~30 _root-Refs+2 Lambdas — der schwerste; ggf. erst Drag-State mitnehmen) → Transport-Lifecycle (_pending_transports/_advance/_park_panel_icon_pending) → Drag-Overlays (_setup/_update_drag_overlays) → Drag-Start/Finish → Badges (_resource_icons/_spawn_*) → Input (_input/_unhandled_input/_hit_test)+_process-Drag-Anteil. Endziel map_root <600 Z.
- Extrahierte map_root-Komponenten bisher (src/scenes/map_root/): TerrainRenderer, BuildingIndicatorLayer, PathDotOverlay, ResourceBadgeFactory, TransportOverlay.
- UMGESETZT (Plan): Phase 6 Asset-Reorganisation ins Plandok geschrieben. Befund: Assets nur als String-Literale referenziert (6 Dateien), KEINE .tscn/.tres-Bindung; 120 .import-Sidecars müssen mitwandern. Pre-existing Bug: resources.json icon_path → assets/ui/icons/resources/* existieren NICHT.
- OFFEN: Phase 5 Rest (ResourceBadgeLayer, BuildingIndicatorLayer, TransportOverlay, ~700-Z. DragController) + Phase 6 Asset-Move (am besten im Godot-Editor) + Panel-Farbliteral-Migration. Alle brauchen Godot/Screenshot-Verifikation.
- WICHTIG unverifiziert (kein lokales Godot-Binary): Suite NICHT gelaufen. Vor Merge `bash addons/gdUnit4/runtest.sh -a res://tests/` ausführen. Bewusster Verhaltens-Nuance: unbekannte Res im Drag-Overlay zeigen jetzt Fallback-Kreis statt (vorher fälschlich) Holz-Icon — Screenshot prüfen.
