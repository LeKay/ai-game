# Story 006: Route Visualization

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature (Presentation)
> **Type**: Visual/Feel
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-009`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture
**ADR Decision Summary**: Route lines rendered via `RouteLines` node (extends `Node2D`, in world tree under camera's parent, NOT CanvasLayer) so lines pan and zoom with the camera. `Line2D` API used directly. Always-visible at 30% opacity for active routes. Color encodes status: green = active, yellow = carrier in transit, red = destination full. Line thickness encodes carrier count. Hover highlights to 60% opacity with tooltip (NPC name, distance, round-trip time, efficiency). Inactive/deactivated routes show dim gray line at 10% opacity. Line patterns (solid/dashed/dotted) provide colorblind accessibility (WCAG 2.1 AA). Dirty-flag updates — lines only redraw on state change, not per-frame.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: `Line2D` (stable since Godot 1.0). No verification required.

**Control Manifest Rules (Presentation Layer)**:
- Required: Depth ordering via `Node2D.y_sort_enabled` — not legacy YSort node
- Required: TileMapLayer per visual layer — one node per layer
- Required: Data-visual separation — TileMapLayer cells derived from Grid data via batch set_cell() calls
- Forbidden: Never use YSort node — use `Node2D.y_sort_enabled` property

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] Active route lines are always-visible on the map at 30% opacity, colored by status (green = active, yellow = carrier in transit, red = destination full)
- [ ] Line thickness encodes carrier count on the route
- [ ] Hovering over a route line highlights it at 60% opacity and displays a tooltip showing: NPC name, distance, round-trip time, efficiency
- [ ] Inactive/deactivated routes show a dim gray line at 10% opacity
- [ ] Line patterns provide colorblind accessibility: active = solid line, transit = dashed line, full = dotted line (colors are supplementary)
- [ ] Route lines are a `Node2D` in the world tree (under camera's parent), NOT a CanvasLayer — they pan and zoom with the map camera
- [ ] Route lines use dirty-flag updates: redraw only when state changes, not per-frame
- [ ] Tooltips are rendered in a CanvasLayer-based HUD overlay (separate from the route lines)

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**RouteLines node hierarchy**:
```
MapRoot (Node2D)
└── RouteLines (Node2D, y_sort_enabled = true)
    ├── Line2D (route_1 — source to destination)
    ├── Line2D (route_2 — source to destination)
    └── ...
```

**Key design decisions**:
1. RouteLines is a Node2D in the world tree — NOT a CanvasLayer. This ensures lines pan and zoom with the camera. CanvasLayer overlays are fixed to screen space.
2. Each active route gets its own Line2D child. For performance, use dirty-flag pattern: each Line2D has a `dirty: bool` flag that is set on state change and cleared on render. Only dirty lines are redrawn.
3. Tooltips are NOT drawn on the Line2D. They are a separate CanvasLayer overlay that appears at mouse position when a Line2D is hovered.

**Status color mapping** (from GDD Visual/Audio Requirements):
```
green = "#4CAF50"   // active
yellow = "#FFC107"  // carrier in transit
red = "#F44336"     // destination full / waiting
gray = "#888888"    // inactive/deactivated
```

**Line patterns** (for colorblind accessibility, WCAG 2.1 AA):
```
active     = solid   (no dash offset)
transit    = dashed  (dash_length = 8, gap_length = 4)
full       = dotted  (dash_length = 2, gap_length = 4)
inactive   = solid (dimmed)
```

**Dirty-flag update pattern**:
```
func _update_route_line(route: LogisticsRoute):
    var line = _route_lines[route.id]
    line.set_points([source_pos, dest_pos])
    line.color = status_color(route)
    line.width = 1.0 + carrier_count  // thickness scales with carrier count
    line.dash_offset = pattern_offset(route.carrier_state)
    line.modulate = inactive ? Color(0.53, 0.53, 0.53, 0.1) : Color(1, 1, 1, 0.3)
    line.dirty = false
```

**Hover interaction**: Use `Line2D.mouse_filter = Control.MOUSE_FILTER_STOP` to capture hover events. On hover, set line's `modulate.a = 0.6` and show tooltip CanvasLayer. On exit, restore `modulate.a = 0.3`.

**Performance**: Per ADR-0011, 30 routes at 60fps = ~1.8ms draw calls. Test at higher counts. Batch `set_points()` calls in `_process()` only for dirty lines.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Route model (data that the visualization reads)
- [Story 004]: Building status integration (the status values the visualization displays)
- [Story 008]: Transportation Management UI (the UI panel for route creation/editing — distinct from map visualization)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**Visual verification:**

- **AC-1**: Active route line visible at correct opacity and color
  - Setup: Create a route with source at (3, 7), destination at (8, 2), carrier in transit (TRAVEL_TO_SOURCE)
  - Verify: Line2D exists between the two building positions, color = green (#4CAF50), modulate alpha = 0.3 (30% opacity)
  - Pass condition: Line is visible on map, color is green, opacity is 30%

- **AC-2**: Color and pattern match carrier state
  - Setup: Create three routes — (a) carrier in transit (TRAVEL_TO_SOURCE), (b) carrier at destination waiting (WAITING_DESTINATION), (c) inactive route (DEACTIVATED)
  - Verify: (a) green + dashed line, (b) red + dotted line, (c) gray (#888888) + solid at 10% opacity
  - Pass condition: Each route line has correct color, pattern, and opacity

- **AC-3**: Hover highlights line and shows tooltip
  - Setup: Create a route, position mouse over the route line
  - Verify: Line modulate alpha changes from 0.3 to 0.6 (60% opacity), tooltip CanvasLayer appears showing NPC name, distance, round-trip time
  - Pass condition: Line highlights AND tooltip shows all four data points

- **AC-4**: Route lines pan and zoom with camera
  - Setup: Create route, move camera via WASD or scroll to zoom
  - Verify: Line endpoints update to match new camera position and zoom level
  - Pass condition: Lines stay connected to buildings as camera moves/zooms (no fixed-screen artifacts)

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**:
- Visual/Feel: `production/qa/evidence/route-visualization-evidence.md` + sign-off from visual lead

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (route model), Story 004 (building status integration — status values drive line colors)
- Unlocks: None
