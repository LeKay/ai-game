# Camera System

> **Status**: Approved
> **Author**: User + Claude
> **Last Updated**: 2026-05-11
> **Implements Pillar**: Pillar 2 (Information Transparency)

## Overview

The Camera System is a viewport controller that maps world-space coordinates to screen-space rendering and back. It exposes pan and zoom operations driven by the Input System, maintains a view rectangle that constrains panning to the Grid/Map System boundaries, and provides mouse-to-tile conversion via a well-defined formula using Grid/Map System's tile size and the current zoom level. The Camera System is pure infrastructure — it has no simulation logic, no states beyond its position and zoom, and no direct player fantasy. It exists to ensure the player can see and interact with the 30×30 tile grid. When functioning correctly, the camera is invisible; the player thinks "look there" and moves the viewport. It fails when there is input lag, snapping, or out-of-bounds jumps.

## Player Fantasy

The Camera System has no player fantasy — it exists to be invisible. Good camera work feels like having eyes directly above the map, precisely where you need them. You don't notice the camera until it fails: when zoom is too tight to plan, when panning lags behind input, or when the view snaps unexpectedly at map edges.

The fantasy belongs to what the camera enables: the satisfying moment of zooming out to see your entire village layout and instantly spotting a bottleneck (**Pillar 3** — Optimization Over Expansion), or hovering over a tile to read exactly what's blocking a production chain (**Pillar 2** — Information Transparency). The Camera System's job is to stay out of the way so those moments happen without friction.

## Detailed Design

### Core Rules

**1. Camera Coordinate Model**

The camera operates in two coordinate spaces:

- **World space**: Measured in pixels, origin (0, 0) at the top-left of the Grid/Map System. Tile N has center at `(N.x * TILE_SIZE + TILE_SIZE/2, N.y * TILE_SIZE + TILE_SIZE/2)`. Total map size: `GRID_SIZE × TILE_SIZE = 30 × 48 = 1440 × 1440` pixels.

- **Screen space**: Measured in screen pixels, origin (0, 0) at the top-left of the game window. Window size is a project-level constant (e.g., 1920 × 1080).

The camera defines a **view rectangle** in world space:

```
ViewRect = {
	x: float,           // World-space left edge of viewport (pixels)
	y: float,           // World-space top edge of viewport (pixels)
	zoom: float,        // Zoom multiplier (1.0 = 1 screen pixel = 1 world pixel)
}
```

The view rectangle dimensions are derived from screen size and zoom:

```
view_width = screen_width / zoom
view_height = screen_height / zoom
```

**2. Pan Inputs**

The camera accepts three pan input sources from the Input System. All pan inputs are processed each frame and add to the camera position:

| Input Source | Action | Effect |
|-------------|--------|--------|
| **WASD** | `on_action_held` for `move_up`/`move_down`/`move_left`/`move_right` | Pan camera in direction of held key. Speed = `pan_speed × TILE_SIZE` pixels/second (per-frame movement = `pan_speed × TILE_SIZE × delta`). |
| **Arrow keys** | `on_action_held` for `camera_pan` | Same effect as WASD. Arrow keys map to camera pan in the Input System. |
| **Middle mouse drag** | `on_mouse_moved` with middle button held | Delta move = delta between current and last mouse screen position, converted to world space by dividing by `zoom`. |

**Pan speed tuning knob:** default 8 tiles/second (384 pixels/second at TILE_SIZE = 48). Camera movement is frame-rate independent: movement per frame = `pan_speed × TILE_SIZE × delta`. All pan inputs are processed each frame and add to the camera position.

**3. Edge Scrolling**

When the mouse cursor is within the edge zone, the camera auto-pans in the direction away from the edge:

```
edge_zone_width = settings.mouse_edge_pan_threshold  // default 20px (from Input System)
if mouse.x < edge_zone_width:        pan_left(edge_zone_speed)
if mouse.x > screen_width - edge_zone_width:  pan_right(edge_zone_speed)
if mouse.y < edge_zone_width:        pan_up(edge_zone_speed)
if mouse.y > screen_height - edge_zone_width:   pan_down(edge_zone_speed)
```

Edge scroll speed = 0.25 × WASD pan speed (quarter as fast — provides a distinct "precise scanning" feel that is clearly distinguishable from WASD movement). Default = 2 tiles/second when pan_speed = 8 tiles/second.

**Edge zone UI guard:** Edge scrolling is suppressed when the mouse cursor is over any UI node. This prevents accidental camera panning when the player is trying to interact with HUD elements (minimap buttons, resource bars) near the screen edge. Edge scrolling only activates when the cursor is in the world-space portion of the screen.

**4. Zoom**

Zoom is controlled by the Input System `on_scroll(delta)` event:

```
zoom_delta = delta * settings.scroll_sensitivity * zoom_sensitivity
new_zoom = clamp(current_zoom + zoom_delta, MIN_ZOOM, MAX_ZOOM)
```

**Zoom point: the camera zooms toward the mouse cursor position in world space.** When zoom changes, the camera adjusts its position so that the world tile under the mouse remains under the mouse:

```
mouse_world_before = (mouse_screen / current_zoom) + camera_offset
camera_offset_new  = mouse_world_before - (mouse_screen / new_zoom)
```

Zoom range: `[0.85, 2.0]`. At 0.85, the 30×30 map nearly fills a 1920×1080 screen (view ≈ 2259×1271 world pixels vs map = 1440×1440), so a small amount of empty space remains on the edges. At 2.0, the view is 960×540 world pixels (~20×11 tiles) — tight but acceptable for detail work.

**10. Fit-to-View (Reset Camera)**

A key bind (default `R`) resets the camera to show the entire map centered and filling the screen. This is used when the player has panned/zoomed away and needs to reorient:

```
func reset_camera():
	# If map doesn't fully fit on screen at current zoom, zoom out to min_zoom.
    if view_width < MAX_X or view_height < MAX_Y:
        zoom = clamp(min(screen_width / MAX_X, screen_height / MAX_Y), MIN_ZOOM, MAX_ZOOM)
        # Recalculate view dimensions at new zoom
        view_width = screen_width / zoom
        view_height = screen_height / zoom
    # Center the camera on the map
    camera_offset.x = (MAX_X - view_width) / 2
    camera_offset.y = (MAX_Y - view_height) / 2
    # Clamp to boundary — if view > map at min_zoom, clamp forces offset to 0
    camera_offset.x = clamp(camera_offset.x, 0, MAX_X - view_width)
    camera_offset.y = clamp(camera_offset.y, 0, MAX_Y - view_height)
```

At 1920×1080 with a 1440×1440 map: At any zoom where the map doesn't fully fill the screen, Fit-to-View computes `min(1920/1440, 1080/1440) = min(1.33, 0.75) = 0.75`. Since 0.75 < MIN_ZOOM (0.85), zoom is set to 0.85. At zoom 0.85, `view_width = 2259 > MAX_X` so x-offset clamps to 0 (map fills screen width). `view_height = 1271 < MAX_Y` so y-offset = (1440 - 1271)/2 = 85 — the map is centered vertically with 169 pixels of extra map visible at the bottom (player can pan down).

This action does NOT animate — camera position and zoom change instantaneously, consistent with the "no transitions" design decision.

**5. Boundary Clamping**

The camera view rectangle is clamped to the map bounds:

```
MAX_X = GRID_SIZE * TILE_SIZE
MAX_Y = GRID_SIZE * TILE_SIZE

# If view exceeds map in a dimension, clamp to 0 (show full map, no panning).
# Otherwise clamp normally to prevent showing empty space.
clamp_x = if view_width > MAX_X: 0 else clamp(camera.x, 0, MAX_X - view_width)
clamp_y = if view_height > MAX_Y: 0 else clamp(camera.y, 0, MAX_Y - view_height)
```

If the view rectangle is larger than the map (zoom < min_zoom), the view rectangle is clamped so the map fills the screen. No black bars — the camera never shows outside the map.

**6. Mouse-to-Tile Conversion**

The Camera System exposes a public query that converts screen-space mouse position to world-space tile coordinates. This is the bridge between Input System mouse events and Grid/Map System tile queries:

```
func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	world_pos = camera_offset + (screen_pos / zoom)
	var tile = Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))
	// Clamp to grid bounds — if the screen position is in empty space (view larger than map),
	// return the nearest valid tile edge instead of an out-of-bounds coordinate.
	return tile.clamp(Vector2i(0, 0), Vector2i(GRID_SIZE - 1, GRID_SIZE - 1))
```

This is the same formula defined in the Input System GDD (mouse world position conversion), but the Camera System owns the actual implementation. Input System calls `camera.screen_to_tile(mouse_screen_pos)` for world-to-tile conversion.

**7. Tile-to-Screen Conversion**

Reverse conversion, used for rendering game objects at correct screen positions:

```
func tile_to_screen(tile_pos: Vector2i) -> Vector2:
	world_pos = tile_pos * TILE_SIZE + TILE_SIZE / 2
	screen_pos = (world_pos - camera_offset) * zoom
	return screen_pos
```

**8. Render Layer Ordering (Depth Sorting)**

All game objects rendered on the map (buildings, resource indicators, NPC transport routes) must respect the Grid/Map System's Y-sort requirement. Game objects are children of a `YSort` node with `y_sort_enabled = true`. The Camera System does not own depth sorting but must not override it — camera transforms apply to all children uniformly.

### States and Transitions

The Camera System has no simulation states — only two parameters (position and zoom) that change continuously:

**Camera State:**

| State | Position | Zoom | Notes |
|-------|----------|------|-------|
| **Idle** | Stable | Stable | Camera not moving. Mouse can trigger edge scroll. |
| **Panning** | Changing | Stable | WASD/arrow keys held OR mouse dragging OR edge scroll active. |
| **Zooming** | Adjusted | Changing | Scroll wheel active. Position shifts to keep mouse cursor anchored. |
| **Clamped** | At boundary | Stable | Camera hit map edge and cannot pan further. Next pan in direction of boundary has no effect. |

**State transitions:**

| From | To | Trigger |
|------|-----|---------|
| Idle | Panning | WASD/arrow key pressed, or middle mouse down |
| Panning | Idle | All pan inputs released |
| Idle | Zooming | Scroll wheel delta received |
| Zooming | Idle | Scroll wheel released |
| Any | Clamped | Camera position reaches boundary clamp |
| Clamped | Panning | Pan input moves away from boundary |
| Clamped | Idle | No pan input |

**Note on "states" vs "parameters":** The camera's core simulation has no states — only two continuous parameters (position, zoom). The table above describes transient conditions that affect input processing, not simulation state. The "Clamped" condition is the only one with meaningful behavioral difference (prevents further movement in the clamped direction). All other conditions are passive input states that do not alter the camera's underlying behavior.

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Input System** (upstream dependency) | Receives pan and zoom inputs | Input System → Camera: `on_action_held("camera_pan")`, `on_scroll(delta)`, `on_mouse_moved(world_pos)` | Camera subscribes to camera actions, updates viewport each frame |
| **Grid/Map System** (upstream dependency) | Queries tile data under cursor; uses tile size for conversion | Camera → Grid: `get_tile_view(x, y)` (for hover), `get_terrain(x, y)` (for building preview), `validate_placement(x, y)` (for placement preview) | Camera provides screen-to-tile conversion; Grid provides tile data |
| **Building System** (downstream) | Receives screen-to-tile for ghost preview placement | Camera → Building: `screen_to_tile(mouse_pos)` | Building System queries camera for current mouse tile in placement mode |
| **HUD System** (downstream) | Receives screen-to-tile for hover tooltips; renders minimap | Camera → HUD: `screen_to_tile(mouse_pos)`, `get_viewport_rect()`, `get_zoom()` | HUD queries camera for current view rectangle (minimap), mouse tile (tooltip) |

## Formulas

### 1. Screen-to-Tile Conversion

Convert screen-space mouse coordinates to world-space tile coordinates:

`screen_to_tile` formula is defined as:

```
world_pos = camera_offset + (screen_pos / zoom)
tile_pos  = floor(world_pos / TILE_SIZE)
```

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| screen_pos | p_screen | Vector2 | (0, 0) to (screen_width, screen_height) | Mouse position in screen pixels |
| camera_offset | c_off | Vector2 | (0, 0) to (MAX_X, MAX_Y) | Camera's world-space left edge (pixels) |
| zoom | z | float | 0.85–2.0 | Camera zoom multiplier |
| TILE_SIZE | ts | int | 48 | Tile pixel size from Grid/Map System (fixed, not tunable in Camera) |
| world_pos | w | Vector2 | (0, 0) to (1440, 1440) | Position in world pixel space |
| tile_pos | t | Vector2i | (0, 0) to (29, 29) | Tile coordinates |
| floor | ⌊⌋ | function | — | Floor function — rounds down to nearest integer |

**Output Range:** (0, 0) to (29, 29) for 30×30 grid — clamped by the `clamp()` call in the formula definition.

**Example:**
```
screen_pos = (400, 300) pixels
camera_offset = (0, 0)
zoom = 1.0
TILE_SIZE = 48
world_pos = (0, 0) + (400, 300) / 1.0 = (400, 300)
tile_pos = floor(400/48, 300/48) = floor(8.33, 6.25) = Vector2i(8, 6)
```

**Dependency:** Uses `TILE_SIZE` from Grid/Map System GDD. Must match exactly (48px).

---

### 2. Zoom-to-Mouse Anchor

When zoom changes, adjust camera offset so the world tile under the mouse stays under the mouse:

`zoom_anchor` formula is defined as:

```
mouse_world_before = (mouse_screen / current_zoom) + camera_offset
camera_offset_new  = mouse_world_before - (mouse_screen / new_zoom)
```

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| mouse_screen | m | Vector2 | (0, 0) to (screen_width, screen_height) | Mouse position in screen pixels |
| current_zoom | z_old | float | 0.85–2.0 | Camera zoom before change |
| new_zoom | z_new | float | 0.85–2.0 | Camera zoom after change |
| camera_offset_old | c_old | Vector2 | — | Camera offset before zoom |
| camera_offset_new | c_new | Vector2 | — | Camera offset after zoom |
| mouse_world_before | mw | Vector2 | — | World-space position of mouse before zoom |

**Output Range:** `camera_offset_new` is within valid world space [0, 1440] range (clamped by boundary rule)

**Example:**
```
mouse_screen = (400, 300)
current_zoom = 1.0
camera_offset_old = (0, 0)
new_zoom = 1.5

mouse_world_before = (400, 300) / 1.0 + (0, 0) = (400, 300)
camera_offset_new = (400, 300) - (400, 300) / 1.5 = (400, 300) - (266.67, 200) = (133.33, 100)

After clamp: camera_offset_new = (133, 100) (within bounds, no clamp needed)
```

**When zoom is larger than map fits on screen**, the anchor point clamps to map boundary — the tile under the mouse may shift slightly on screen, but this is unavoidable (the tile simply doesn't fit on screen at this zoom).

---

### 3. Boundary Clamp

Enforce camera position within map bounds:

`boundary_clamp` formula is defined as:

```
view_width  = screen_width / zoom
view_height = screen_height / zoom

clamp_x = clamp(camera_offset.x, 0, max_world_x - view_width)
clamp_y = clamp(camera_offset.y, 0, max_world_y - view_height)
```

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| screen_width | sw | int | 1920 (project constant) | Game window width in pixels |
| screen_height | sh | int | 1080 (project constant) | Game window height in pixels |
| zoom | z | float | 0.85–2.0 | Camera zoom multiplier |
| view_width | vw | float | sw/2.0–sw/0.85 = 960–2259 | Viewport width in world pixels |
| view_height | vh | float | sh/2.0–sh/0.85 = 540–1271 | Viewport height in world pixels |
| max_world_x | mx | int | 1440 | Grid/Map System total width (30 × 48) |
| max_world_y | my | int | 1440 | Grid/Map System total height (30 × 48) |
| camera_offset.x | cx | float | 0–1440 | Camera's world-space X position |
| camera_offset.y | cy | float | 0–1440 | Camera's world-space Y position |

**Output Range:** `clamp_x` ∈ [0, 1440 - vw], `clamp_y` ∈ [0, 1440 - vh]

**Example:**
```
screen = 1920×1080, zoom = 1.0
view_width = 1920, view_height = 1080
max_world = 1440×1440

clamp_x = (view_width > MAX_X ? 0 : clamp(cx, 0, 1440 - 1920)) = 0
clamp_y = (view_height < MAX_Y) ? clamp(cy, 0, 1440 - 1080) = clamp(cy, 0, 360)

Result: At zoom 1.0, the horizontal view (1920) exceeds the map width (1440),
        so clamp_x forces to 0 — the map fills the screen width with no panning.
        Vertically, the view fits, so normal clamping applies (cy ∈ [0, 360]).

At zoom = 1.5:
view_width = 1920 / 1.5 = 1280, view_height = 1080 / 1.5 = 720
# Both dimensions fit on screen, so normal clamping applies
clamp_x = clamp(cx, 0, 1440 - 1280) = clamp(cx, 0, 160)
clamp_y = clamp(cy, 0, 1440 - 720) = clamp(cy, 0, 720)
```

---

### 4. Tile-to-Screen Conversion

Convert tile coordinates to screen-space pixels (for rendering game objects):

`tile_to_screen` formula is defined as:

```
world_pos = tile_pos * TILE_SIZE + TILE_SIZE / 2
screen_pos = (world_pos - camera_offset) * zoom
```

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| tile_pos | t | Vector2i | (0, 0) to (29, 29) | Tile coordinates |
| TILE_SIZE | ts | int | 48 | Tile pixel size |
| camera_offset | c_off | Vector2 | — | Camera's world-space left edge |
| zoom | z | float | 0.85–2.0 | Camera zoom multiplier |
| world_pos | w | Vector2 | — | World-space center of tile |
| screen_pos | s | Vector2 | — | Position in screen pixels (may be negative if off-screen) |

**Output Range:** Screen coordinates. Negative values = off-screen to the left/top. Values > screen size = off-screen to the right/bottom.

**Example:**
```
tile_pos = Vector2i(5, 12), TILE_SIZE = 48
world_pos = (5, 12) * 48 + (24, 24) = (264, 600)
camera_offset = (0, 0), zoom = 1.0
screen_pos = (264, 600) * 1.0 = (264, 600) on screen

camera_offset = (200, 100), zoom = 1.0
screen_pos = (264 - 200, 600 - 100) = (64, 500) on screen

camera_offset = (0, 0), zoom = 0.85
screen_pos = (264, 600) * 0.85 = (224.4, 510) on screen (tiles appear smaller at lower zoom)
```

## Edge Cases

- **If camera offset is negative** (should never happen due to boundary clamp): Clamp to (0, 0) and log warning. A negative offset means the clamp formula is broken — this is a bug.

- **If camera offset exceeds map bounds** (e.g., due to rapid input before clamp applies): Clamp to max bounds. Rapid panning may temporarily push position past clamp — next frame's clamp fixes it. No visual artifact.

- **If screen size changes** (window resize during play): Recalculate `view_width` and `view_height`. Camera offset is re-clamped to new bounds. If the new window is smaller than the current view rectangle, the camera is clamped to the nearest edge (no sudden jump — camera position is preserved if it fits).

- **If zoom is changed while camera is at map boundary**: The zoom anchor formula may try to push camera offset negative (or past max). The boundary clamp handles this — camera offset is clamped. The tile under the mouse shifts slightly on screen (unavoidable when zooming a large view into a small map).

- **If mouse moves outside game window**: Edge scrolling stops immediately (mouse position is no longer known). Last known position is held for 1 frame, then edge scroll is disabled until mouse re-enters. This prevents the camera from "spinning" if the mouse was near an edge when it left the window.

- **If middle mouse drag is too fast for frame rate** (mouse moves multiple tiles per frame): `on_mouse_moved` provides delta between last and current position, so the Camera System receives the correct delta regardless of frame rate. No frame drops — camera moves by the full delta in one frame.

- **If `screen_to_tile` is called with a mouse position outside the visible map area** (screen area with no map at low zoom): Returns the tile coordinate at the nearest map edge. Example: at zoom 1.0 on a 1920×1080 screen with a 1440×1440 map, the rightmost 480px have no map — `screen_to_tile` on those pixels returns column 29 (the rightmost tile). This is acceptable — clicking outside the map does nothing in game logic.

- **If scroll wheel delta is 0** (no scroll): No zoom change occurs. Neutral state.

- **If camera_offset.x > MAX_X - view_width** (view rectangle wider than remaining map width): Boundary clamp sets camera_offset.x to `MAX_X - view_width`. The visible portion of the map is the rightmost edge — left portion of viewport shows no map (clamped to 0 but view extends beyond). No visual artifact — the engine handles this by simply not rendering anything for empty screen pixels.

- **If zoom changes and the anchor point moves the camera past the opposite boundary**: e.g., zooming in near the right edge may try to push camera_offset past MAX_X. Clamp handles this — anchor is approximate at map boundaries.

## Dependencies

### Upstream (Camera System depends on)

| System | Dependency Type | Notes |
|--------|----------------|-------|
| **Input System** | Hard — provides all camera inputs | Camera subscribes to `camera_pan`, `camera_zoom` (scroll), and `on_mouse_moved` events. Without Input System, camera has no input source. |
| **Grid/Map System** | Hard — provides tile data and coordinate constants | Camera queries `get_tile_view()` for hover, `TILE_SIZE` for conversions, and clamps to grid boundaries. Camera cannot function without a grid to display. |

### Downstream (systems that depend on Camera System)

| System | Dependency Type | Notes |
|--------|----------------|-------|
| **Building System** | Hard — needs screen-to-tile for placement preview | Ghost building preview depends on `screen_to_tile()` from Camera System. Without camera, building placement has no mouse-to-tile mapping. |
| **HUD System** | Hard — needs viewport info for tooltips and minimap | Hover tooltips use `screen_to_tile()`. Minimap needs `get_viewport_rect()` to show the current camera view. |
| **Manual Labor System** | Soft — uses camera hover for tile targeting | Manual Labor can operate without camera (Input System provides mouse position), but camera-based hover feedback is standard UX. |
| **Production System** | Soft — hover tooltips on production buildings | Production System shows "blocked/waiting/producing" via HUD hover, which queries Camera for current tile. |
| **Hover/Tooltip UI** | Hard — entire hover system is built on camera tile mapping | Hover UI uses `screen_to_tile()` from Camera as its primary input for determining what tile the player is looking at. |

### Bidirectional Consistency

Camera → Grid/Map System: Camera uses `TILE_SIZE = 48` from Grid/Map System GDD. If Grid/Map changes tile size, Camera conversions must match. Camera clamps to `GRID_SIZE × TILE_SIZE` from Grid/Map.

Camera → Input System: Input System defines `camera_pan` and `camera_zoom` action IDs. Camera subscribes to these. Input System's mouse world position formula delegates to Camera's `screen_to_tile()` implementation.

Grid/Map System → Camera: Grid/Map System GDD lists Camera under "Downstream dependents" as consuming `get_tile_view()` and `get_terrain()`. This GDD confirms that relationship.

## Tuning Knobs

| Knob | Default | Safe Range | Effect | What breaks if misconfigured |
|------|---------|------------|--------|------------------------------|
| **pan_speed_tiles_per_second** | 8 | 2–20 tiles | How many tiles the camera moves per second with WASD/arrows (frame-rate independent). Per-frame movement = `pan_speed × TILE_SIZE × delta`. | Below 2: sluggish, map feels sticky. Above 20: uncontrollable, can't aim precisely |
| **edge_scroll_speed** | 2 | 1–10 tiles | Auto-pan speed when mouse is in edge zone (0.25 × pan_speed by default, tiles/second). | Below 1: edge scroll useless. Above 10: edge scroll faster than WASD, unintuitive |
| **edge_zone_width** | 20 | 5–50 px | Screen-edge pixels that trigger auto-pan. | Below 5: barely any edge scroll zone. Above 50: edge zone covers most of screen, camera drifts while playing |
| **zoom_sensitivity** | 1.0 | 0.3–3.0 | Scroll wheel zoom speed multiplier. | Below 0.3: scroll barely changes zoom. Above 3.0: zoom oscillates uncontrollably with tiny scroll |
| **min_zoom** | 0.85 | 0.75–0.9 | Minimum zoom (furthest out). | Below 0.75: map is tiny, can't see details. Above 0.9: can't see enough map at once |
| **max_zoom** | 2.0 | 1.5–3.0 | Maximum zoom (closest in). | Below 1.5: can't zoom in enough for detail work. Above 3.0: individual pixels become visible, breaks art style |

**Cross-knob interactions:**
- `pan_speed × zoom_sensitivity`: At higher zoom levels, the same scroll delta produces a smaller world-space shift (because the view is tighter). This is intentional — zooming in should feel more precise.
- `edge_scroll_speed` defaults to `0.25 × pan_speed`. Changing pan_speed without adjusting edge_scroll_speed breaks the 1:4 ratio. Either adjust both, or make edge_scroll_speed a separate explicit knob.
- `min_zoom × screen_size`: If the map doesn't fill the screen at `min_zoom`, there will be empty (black) edges. At zoom 0.85 on a 1920×1080 screen: view = 1694×1271 world pixels, map = 1440×1440 → small vertical gap, map nearly fills screen. This is acceptable — the map is always fully visible with room to pan.

## Visual/Audio Requirements

**Visual:**
- The Camera System has no direct visual output. It transforms what the Grid/Map System and other systems render.
- **No camera shake, no transitions, no effects** — camera movement is instantaneous (no smooth interpolation, per design decision).
- **Screen resize**: If the game window is resized, the camera view updates immediately with no animation. No black bars — empty screen pixels are simply empty.

**Audio:**
- **No audio output** — camera movement or zoom triggers no sounds. Audio feedback for player interactions (e.g., scroll wheel click) is owned by the Input System or Audio System, not the Camera System.

## UI Requirements

The Camera System provides coordinate data to UI systems but does not own UI elements:

**Viewport Info (HUD System):**
- HUD System queries `get_viewport_rect()` to determine which tiles are visible in the current view. This can be used for:
  - Culling: Only render/build/tick objects within the viewport (performance optimization)
  - Minimap: Show the viewport rectangle on a minimap overlay
  - Distance indicators: Show distance from player character to visible buildings/tiles

**📌 UX Flag — Camera System**: This system provides the coordinate foundation for hover tooltips, placement previews, and minimap rendering used by HUD System, Building System, and Hover/Tooltip UI. In Phase 4 (Pre-Production), run `/ux-design` to specify hover tooltip positioning, minimap interaction, and camera input key hints **before** writing epics.

## Acceptance Criteria

1. **GIVEN** the camera is at offset (0, 0) with zoom 1.0, **WHEN** `screen_to_tile(Vector2(264, 600))` is called, **THEN** result is `Vector2i(5, 12)`
2. **GIVEN** the camera is at offset (0, 0) with zoom 1.0, **WHEN** `tile_to_screen(Vector2i(5, 12))` is called, **THEN** result is `Vector2(264, 600)`
3. **GIVEN** the camera is at offset (0, 0) with zoom 1.0, **WHEN** scroll wheel delta is +3.0 with zoom_sensitivity = 1.0, **THEN** new_zoom = clamp(1.0 + 3.0 * 1.0, 0.85, 2.0) = 2.0 (max zoom reached)
4. **GIVEN** the camera is at offset (500, 300) with zoom 1.5, **WHEN** boundary clamp is applied on a 1920×1080 screen, **THEN** camera_offset = clamp(500, 0, 1440 - 1280) = clamp(500, 0, 160) = 160 (clamped to right boundary)
5. **GIVEN** pan_speed_tiles_per_second = 8, **WHEN** `_process(delta)` is called with injected delta = 0.01667, **THEN** camera displacement = 8 × 48 × 0.01667 = 6.399 pixels (≈ 6.4 px, verified by automated unit test)
6. **GIVEN** edge_zone_width = 20 and camera control mode, **WHEN** mouse y > screen_height - 20 (bottom edge zone) and `_process(delta)` is called with injected delta = 0.01667, **THEN** camera downward displacement = 2 × 48 × 0.01667 = 1.599 pixels (≈ 1.6 px, verified by automated unit test)
7. **GIVEN** the camera is at camera_offset (200, 150) with zoom 1.0, **WHEN** scroll wheel delta is +2.0 and mouse is at screen position (400, 300), **THEN** new_zoom = clamp(1.0 + 2.0, 0.85, 2.0) = 2.0 and camera_offset_new = (400/1.0 + 200, 300/1.0 + 150) - (400/2.0, 300/2.0) = (600, 450) - (200, 150) = (400, 300)
8. **GIVEN** the mouse cursor leaves the game window, **WHEN** edge scrolling was active, **THEN** edge scrolling stops immediately (camera no longer pans)
9. **GIVEN** the camera is at offset (0, 0) with zoom 1.0 on a 1920×1080 window, **WHEN** the window is resized to 1280×720, **THEN** view_width = 1280, view_height = 720, and camera_offset is re-clamped to fit new bounds
10. **GIVEN** the camera is at zoom 0.85 (min_zoom) with camera_offset.x = 0, **WHEN** boundary clamp is applied (view_width = 1920/0.85 = 2259 > MAX_X = 1440, so clamp_x = 0), **THEN** camera_offset.x remains 0 and pan_right input has no effect (view exceeds map, camera locked to show full map)
11. **GIVEN** camera_offset = (0, 0), zoom = 1.0 on a 1920×1080 screen, **WHEN** `screen_to_tile(Vector2(1800, 500))` is called, **THEN** result is `Vector2i(29, 10)` (rightmost column — 1800/48 = 37.5 → clamped to 29, 500/48 = 10.4 → 10)
12. **GIVEN** the game window is resized from 1920×1080 to 1280×720, **WHEN** the current camera_offset was previously valid and remains within the new view bounds, **THEN** camera_offset changes by ≤ 1 pixel (no visible jump), only view_width and view_height are updated

## Open Questions

**None at this time.** Camera System design is complete for Vertical Slice.

**Future considerations (post-Vertical Slice):**
- **Camera shake/jitter** (for events like earthquakes, production explosions): Add a separate "camera effects" layer that offsets the view rectangle temporarily. Out of scope for Vertical Slice.
- **Camera focus/follow target** (when NPC or event is highlighted): Add a `set_focus_target(Vector2i tile_pos)` that smoothly moves camera to center on the target tile. Useful for production building error indicators.
- **Camera presets** (quick zoom to specific areas): Save/restore viewport state for "focus on building X" or "show entire map" buttons. Deferred to HUD System interaction design.
- **Smooth camera transitions** (instead of instant panning): Add `lerp()`-based interpolation for camera movement. Adds polish but also input lag. Current decision: instant panning for Vertical Slice (no lag). Revisit for MVP if playtest shows panning feels too jarring.
