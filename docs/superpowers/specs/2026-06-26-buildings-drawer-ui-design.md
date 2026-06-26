# Buildings Drawer UI — Design Spec

**Date:** 2026-06-26
**Status:** Approved (design); implementation pending
**Replaces:** `BuildingDetailPanel` (centered modal) + Buildings-tab in `InventoryScreen`
**Touches:** `TaskDialog`, `TransportDrawer` (centralization of edge-drawer behavior)

## 1. Goal

Replace the existing centered-modal `BuildingDetailPanel` with a right-edge drawer
("Buildings tab") sitting between the existing Tasks and Transport drawers. At the
same time, factor the duplicated drawer machinery (~1170 lines across `TaskDialog`
and `TransportDrawer`) into a single centralized `EdgeDrawerController` and adopt
a new, simpler open/close model for all three drawers.

## 2. Drawer Behavior (applies to all three drawers)

Replaces the previous hover-peek + click-pin model:

- **Idle:** Tab sits at the right screen edge; panel offscreen.
- **Hover on tab:** Tab nudges out a short distance (~12 px) as visual feedback.
  The panel does NOT open on hover.
- **Click on tab:** Panel slides in pinned.
- **Click outside panel + tab:** Panel slides out. The click event is not
  consumed (clicks pass through to the map).
- **ESC:** Always closes the drawer. Exception: if the active content reports
  `wants_escape_handled() = true` (e.g. an inline rename edit is active),
  content handles ESC first and may swallow it.
- **Click on map building:** Opens Buildings drawer pinned and jumps directly
  to that building's detail view.

Tab order on the right edge, top → bottom:

1. Tasks (`top_margin = 104`, existing)
2. **Buildings** (`top_margin = 212`, new)
3. Transport (`top_margin = 320`, moved down from current 212)

Drawer width: 520 px (same as today). Sections in the Buildings drawer stack
vertically, never side-by-side.

> **Behavior change:** Tasks and Transport drawers lose their hover-opens-panel
> behavior. This is intentional but spectator-visible — call out in changelog.

## 3. Architecture

### 3.1 Centralized drawer machinery (composition, not inheritance)

New module: `src/ui/edge_drawer/`

- `edge_drawer_controller.gd` (Node, ~180 lines) — owns all tab/slide/pin/hover/
  click-outside/ESC behavior. Holds a reference to a content `Control` rather
  than subclassing it. Configured via `setup(content, config)`.
- `edge_drawer_config.gd` (Resource) — fields:
  - `tab_label: String`
  - `tab_top_margin: float`
  - `panel_width: float`
  - `layer_index: int`
  - `hover_peek_distance: float`
- `edge_drawer_tab.gd` (Control) — standalone tab visual: background, label,
  optional badge; emits `hover_entered/exited`, `pressed`.

**Content API** (every drawer content node must implement):

```gdscript
extends Control
signal request_close()
func on_drawer_opened() -> void
func on_drawer_closed() -> void
func wants_escape_handled() -> bool
func handle_escape() -> bool   # true = ESC consumed; false = drawer should close
```

Tabs stack vertically by `tab_top_margin`. When multiple drawers are open, the
last opened gets the highest `layer_index` (controller maintains a small
registry, queried at open time).

### 3.2 Drawer-content node ownership

| Existing class       | Becomes                              |
|----------------------|--------------------------------------|
| `TaskDialog`         | `tasks_drawer_content.gd`            |
| `TransportDrawer`    | `transport_drawer_content.gd`        |
| (new)                | `buildings_drawer_content.gd`        |

Each is a `Control` containing only content; the wrapping `CanvasLayer` +
controller wiring lives in `hud.gd` (one-shot setup).

### 3.3 BuildingsDrawerContent as a view-stack

Files under `src/ui/edge_drawer/buildings/`:

- `buildings_drawer_content.gd` (Control, ~150 lines) — view-stack root; routes
  signals out.
- `views/building_list_view.gd` — tile-grid of active buildings; first tile is
  the `+`-tile.
- `views/build_picker_view.gd` — tile-list of buildable types (content extracted
  from today's `InventoryScreen` Buildings tab).
- `views/building_detail_view.gd` — header + production/inventory + transport +
  upgrades.
- `views/recipe_picker_view.gd` — recipe tiles; embedded **inside** the
  Production section as a sub-state, not as a root view.
- `views/route_editor_view.gd` — thin wrapper around the existing `RouteEditor`;
  embedded **inside** the Transport section as a sub-state.

**View-stack rules:**

- Stack is flat (max depth 2: List → Detail, or List → BuildPicker).
- `+`-tile in list → replaces list with `BuildPickerView` (with `← Back` row).
- Buildable tile clicked → drawer closes + build-mode signal emitted.
- Building tile clicked → switch to Detail.
- Map building clicked → drawer opens pinned + pushes Detail directly.
- Different building clicked while in Detail → Detail swaps content (no new push).
- Recipe-picker and route-editor live inside their section body only — header
  and other sections remain visible so the player never loses context.

**Lifecycle:**

- Default initial view: `BuildingListView`.
- On drawer close: active rename/recipe-picker/route-editor are silently
  cancelled; detail position is NOT remembered (next open returns to list),
  unless the open is triggered by a map click.

## 4. Tile System

Shared tile module under `src/ui/edge_drawer/buildings/tiles/`:

- `drawer_tile.gd` (Control, ~80 lines) — base tile.
  - Size: 72×84 px (icon 56×56, label below, optional badge top-right).
  - States: `normal`, `hover`, `pressed`, `disabled`, `active`.
  - Optional `progress_circle: float` overlay (0..1) for radial ring.
  - Optional `plus_glyph: bool` overlay for `+`-tiles.
  - Emits `pressed`, `hovered`.
- `building_tile.gd` — asset = `BUILDING_TEXTURES`, label = custom or default
  name, badge = state-dot color from `STATE_COLORS`. Im-Bau variant: progress
  ring + dimmed modulate.
- `item_tile.gd` — asset = resource icon (`resources.json`), label =
  resource name, badge = current quantity. Drag-source emitting the existing
  `storage/input/output_drag_started` payload schema.
- `worker_tile.gd` — NPC portrait/glyph + name. `+`-variant when no worker
  assigned.
- `upgrade_tile.gd` — emoji asset (until art is generated), label = name,
  badge = checkmark (active) or cost tooltip (available). Disabled when
  unaffordable.
- `route_tile.gd` — carrier glyph + item icon, label `from → to`, badge =
  items-per-day throughput (same data the old Transport section showed).

`tile_flow_container.gd` (Control, ~40 lines) — `HFlowContainer` wrapper with
consistent spacing/padding, used everywhere tiles are listed.

## 5. Detail View Layout

```
┌─────────────────────────────────────────────────────┐
│ ← Back                                              │  Back-bar (24 px)
├─────────────────────────────────────────────────────┤
│ Lumber Camp 3                                       │  Name above asset
│ ┌──────┐ Efficiency: 80%   ┌──────┐ ┌────┐         │
│ │Asset │ Utilization: 75%  │Worker│ │ ✏️ │         │  Header
│ └──────┘                   └──────┘ └────┘         │
├─────────────────────────────────────────────────────┤
│ Production                              ⚙️          │  (hidden if 1 recipe)
│                                                     │
│  [🪵 12] [🪵 8]   →   [🪵 4]                       │  Input → Output tiles
│                                                     │
│  Consumption: ~6 🌳/day · Output: ~12 🪵/day       │  Estimated daily rates
├─────────────────────────────────────────────────────┤
│ Transport                                           │  No icon button
│                                                     │
│   Incoming (1)                                      │
│   [→ Route Tile] [+]                                │
│                                                     │
│   Outgoing (2)                                      │
│   [→ Route Tile] [→ Route Tile] [+]                 │
├─────────────────────────────────────────────────────┤
│ Upgrades                                            │  Hidden if active+available empty
│                                                     │
│   [✓ Saw] [Steel Tools] [Faster Cart]               │  Active first, then available
└─────────────────────────────────────────────────────┘
```

### 5.1 Header

- **Name** label above the asset, left side.
- Click ✏️ → name label becomes `LineEdit`; ✓ submit / ✕ cancel appear next
  to it. Enter submits, ESC cancels (content fields ESC via
  `wants_escape_handled = true`).
- **Worker tile** to the right of Eff/Util (before space-between flex region).
  Click with worker → emits `npc_detail_requested` (opens existing
  `NpcDetailPanel`). Click on `+`-variant → opens inline free-NPC picker popup
  above the tile. Worker slot stays visible when no free NPCs exist — disabled
  with tooltip "No free workers".
- Only one worker per building (current game design).

### 5.2 Production section (`production_section.gd`)

- Header: label "Production" left, ⚙️ right (space-between). ⚙️ hidden when
  `available_recipes.size() <= 1`.
- Normal body: `TileFlowContainer` with input `ItemTile`s, then `→` glyph,
  then output `ItemTile`s. Inputs show buffer quantity as badge; outputs ditto.
- Picker body (after ⚙️ click): tile-list of available recipes; each tile
  shows mini I/O glyphs (e.g. `🌾→🍞`); `← Back` row at top. Click on a
  recipe → calls `BuildingRegistry.set_active_recipe()` and returns to normal
  body.
- Below tiles: rate label using **current efficiency** (not theoretical max),
  formatted per day (e.g. "~12 🪵/day"). Recomputed on
  `building_state_changed` and `ticks_advanced`.
- **Storage buildings replace this whole section with `InventorySection`** at
  the same position: a `TileFlowContainer` listing all stored resources as
  `ItemTile`s. Position between header and transport.

### 5.3 Transport section (`transport_section.gd`)

- Header: label "Transport", no icon button.
- Body: two sub-containers:
  - `Incoming (n)` sub-header + `TileFlowContainer` of `RouteTile`s + `+`-tile
    at end.
  - `Outgoing (n)` sub-header + `TileFlowContainer` of `RouteTile`s + `+`-tile
    at end.
- Empty sub-sections still render their sub-header (with `(0)`) and the
  `+`-tile, so the player knows where to drop a new route.
- Click `+` → swaps section body to `route_editor_view.gd` with this building
  pre-filled as From or To respectively. Save/Cancel return to list body.
- Click existing `RouteTile` → opens it in editor (edit mode) — same UX as
  today's `TransportDrawer`.

### 5.4 Upgrades section (`upgrades_section.gd`)

- Header: label "Upgrades".
- Body: single `TileFlowContainer`. Active upgrades first (with check
  overlay), then available upgrades. Locked upgrades (progression-gated) are
  not listed (matches today's `get_available_upgrades` filtering).
- Click on available tile → direct install when affordable. When unaffordable,
  tile is disabled with cost tooltip ("Requires: 10× Stone, 5× Wood").
- Section hidden entirely when both `active_upgrades` and
  `get_available_upgrades` are empty.

### 5.5 Building list view

- Single `TileFlowContainer` of `BuildingTile`s; first tile is the `+`-tile.
- Each tile: asset + custom/default name + state-dot badge.
- **Im-Bau tile:** dimmed modulate (~0.5), `progress_circle` overlay; click
  triggers the player character's construction action (same as clicking the
  building on the map). Tooltip: "Under construction (X%) — click to build".

## 6. Data Flow & Signals

UI never owns state. All writes go through Autoload registries.

### 6.1 BuildingsDrawerContent → HUD signals

```gdscript
# Build flow
signal build_mode_requested(building_type: int)
signal demolish_mode_requested()

# Detail actions
signal rename_building(building_id: String, new_name: String)
signal recipe_changed(building_id: String, recipe_id: StringName)
signal upgrade_install_requested(building_id: String, upgrade_id: StringName)
signal npc_assigned(building_id: String, npc_id: StringName)
signal npc_released(building_id: String, npc_id: StringName)
signal npc_detail_requested(npc_id: StringName)
signal construction_work_requested(building_id: String)

# Drag-out (forwarded to DragController in map_root)
signal storage_drag_started(resource_id, container_id, building_tile)
signal input_drag_started(resource_id, building_id, building_tile)
signal output_drag_started(resource_id, building_id, building_tile)

# Routes (reuses existing TransportDrawer signal contracts)
signal route_create_requested(from_id, to_id, npc_id, item_id)
signal route_update_requested(route_id, changes)
signal route_delete_requested(route_id)
signal map_select_requested(step: String)
```

### 6.2 Data reads

- Active building list: `BuildingRegistry.get_all_buildings()` filtered to
  Production + Storage types (exclude Shelter, Path).
- Per-building state: existing API — `get_efficiency`, `get_utilization`,
  `get_state`, `active_recipe`, `input_buffer`, `output_buffer`.
- Refresh triggers: `BuildingRegistry.building_state_changed`, `building_added`,
  `building_removed`, `upgrade_installed`, `upgrade_removed`,
  `InventorySystem.container_changed`, `LogisticsSystem.routes_changed`,
  `TickSystem.ticks_advanced` (rate recompute).

### 6.3 Map click → drawer open

HUD listens to existing `building_selected` from `map_root` and calls
`_buildings_drawer.open_for_building(building_id)`, which pins the drawer and
pushes the Detail view for that ID.

### 6.4 New API methods (added if missing)

- `BuildingRegistry.set_active_recipe(building_id, recipe_id)`
- `BuildingRegistry.set_custom_name(building_id, name)` (if rename isn't
  persistent today)
- `BuildingRegistry.get_available_recipes(building_id) -> Array`
- `BuildingRegistry.compute_estimated_daily_rate(building_id, item_id) -> float`

Each is checked first in the implementation plan; only added if missing.

## 7. Migration Plan

### Phase A — EdgeDrawer base (no UX change)

1. Build `EdgeDrawerController`, `EdgeDrawerConfig`, `EdgeDrawerTab`.
2. Migrate `TaskDialog` to controller; extract content as
   `tasks_drawer_content.gd`. **Manual verify in Godot.**
3. Migrate `TransportDrawer` analogously. **Manual verify in Godot** including
   route create/edit/delete.

### Phase B — BuildingsDrawer (new feature)

4. `BuildingsDrawerContent` + `BuildingListView` + `BuildingTile` +
   `TileFlowContainer` + `DrawerTile` base. List renders; `+`-tile visible.
   **Verify list, im-Bau progress ring.**
5. `BuildPickerView` (content extracted from `InventoryScreen`'s Buildings
   tab). Click `+` → picker. Click buildable → drawer closes + build mode.
   **Verify build flow end-to-end.**
6. `BuildingDetailView` skeleton: back-bar + header (asset, name, eff/util,
   worker tile, rename). Rename in-place. Worker click opens NPC detail or
   free-NPC picker. **Verify detail entry, back, rename persistence.**
7. `ProductionSection` + `InventorySection` for storage. Item tiles with
   buffer quantities + drag-out + daily-rate label. **Verify drag-out works
   from drawer's CanvasLayer, same as old modal.**
8. Recipe picker sub-state (⚙️). **Verify recipe switch where multi-recipe
   buildings exist; else just verify ⚙️ hidden.**
9. `TransportSection` + `RouteEditorView` embed + `+`-tiles for in/out.
   **Verify create/edit/delete + map-select round-trip.**
10. `UpgradesSection`. **Verify install + state refresh.**

### Phase C — Tear down old modal

11. Delete `building_detail_panel.gd` and its instantiation in `hud.gd`.
12. Map click on building (`map_root` / `DragController`) routes to
    `_buildings_drawer.open_for_building()`.
13. Replace HUD signal handlers that listened to the old panel with
    Buildings-drawer handlers.
14. Remove Buildings tab from `InventoryScreen`. **Verify inventory shows
    Resources + Crafting only; no regressions in any gameplay flow.**

### Phase D — Cleanup

15. Remove dead helpers from `BuildingGrid` if unused. Keep `BuildingGrid` if
    `BuildPickerView` reuses it.
16. Manual smoke-test of all gameplay flows.

### Unchanged

`NpcDetailPanel`, `RouteEditor` class, `DraggableWindow`, `BuildingRegistry`
data model, `LogisticsSystem`, all gameplay systems.

## 8. Testing & Verification

> **Note:** Per the project owner's instruction, automated tests are
> documented here as the *intended* test surface, but are NOT to be implemented
> as part of this work. Verification during implementation will be manual via
> Godot screenshots and walkthrough.

### 8.1 Automated tests (documented, not implemented)

Would live in `tests/unit/ui/edge_drawer/`:

- `edge_drawer_controller_test.gd`:
  - Tab geometry for given `tab_top_margin` and `panel_width`.
  - State transitions: `idle → hover → idle`, `idle → pinned → idle`,
    `pinned → click-outside → idle`.
  - ESC routing: content `wants_escape_handled() = true` → content gets ESC
    first; otherwise controller closes.
  - Tab stacking: three controllers with distinct `tab_top_margin` → no
    overlap rectangles.

- `buildings_drawer_content_test.gd`:
  - Initial view is `BuildingListView`.
  - `open_for_building(id)` → current view is `BuildingDetailView` with that
    ID.
  - List → Detail(A) → click building B in list API → Detail swaps to B, no
    duplicate stack push.
  - Demolish active building → returns to refreshed list.

- `building_detail_view_test.gd`:
  - Storage building renders `InventorySection`, NOT `ProductionSection`.
  - Production building with 1 recipe → ⚙️ hidden.
  - Multi-recipe building → ⚙️ visible; click swaps body to
    `RecipePickerView`.
  - Empty upgrades + no available → section completely hidden.

- `daily_rate_formula_test.gd`:
  - Known cycle ticks + efficiency → expected output/day.
  - Efficiency 0 → rate 0.
  - Boundary: cycle longer than one day.

### 8.2 Manual verification (required for completion)

Logged in `production/qa/evidence/buildings-drawer-walkthrough.md` and ticked
off in Godot by the project owner:

1. Tasks tab: hover shows tab peek, click pins/unpins, click outside closes,
   ESC closes, content unchanged.
2. Transport tab: ditto, plus route create/edit/delete still works.
3. Buildings tab: list renders, `+` opens build picker, build flow works,
   im-Bau shows progress ring.
4. Detail view: header correct, rename in-place + persistence, worker click
   opens NPC detail, worker `+` assigns.
5. Production: I/O tiles show buffers, drag-out works, daily rate plausible,
   ⚙️ swaps and recipe change takes effect.
6. Storage: Inventory section instead of Production, drag-out from inventory
   works.
7. Transport in detail: routes sorted (in/out), `+` opens editor inline,
   map-select round-trip works.
8. Upgrades: active first with checkmark, available click-installs, cost
   tooltip on unaffordable.
9. Demolish while detail open → returns to refreshed list.
10. On game start: only one drawer behavior model (no old modal anywhere).

### 8.3 Known technical risks (resolve during implementation)

- `BuildingRegistry.set_active_recipe` may not yet exist — first task of
  Phase B step 8 is to check and add if missing.
- `compute_estimated_daily_rate` needs access to cycle definitions (today in
  `CraftingRegistry` or hardcoded in `BuildingRegistry`?) — small recon at
  start of Phase B step 7.
- `BUILDING_TEXTURES` in `BuildingRegistry` must cover every type that appears
  in the active-buildings list — fallback to storage.png would look bad in the
  drawer.
- Drag-out from the drawer to the map space crosses CanvasLayers — verify the
  existing drag system handles this (the old modal also crossed layers, so
  this should work).

## 9. Out of Scope

- New art for upgrades (emojis until generated).
- Touch / gamepad input (PC-only, per project preferences). Keyboard ESC + click
  are sufficient.
- Localization of new strings (project hasn't shipped localization yet).
- Persistence of drawer pin state across save/load.
- Animations beyond the existing slide/peek (no fancy tile entrance animations).
