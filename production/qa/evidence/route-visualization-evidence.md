# QA Evidence — Route Visualization (Story 006)

> **Story**: `production/epics/logistics-system/story-006-route-visualization.md`
> **Story Type**: Visual/Feel
> **Required Evidence**: Manual walkthrough + visual lead sign-off
> **Date**: TBD (fill in at review)
> **Reviewer**: TBD

---

## AC-1: Active route line visible at correct opacity and color

**Setup**: Create a route with source at (3, 7), destination at (8, 2), carrier in TRAVEL_TO_SOURCE state.

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Line2D node exists between two building positions | Line visible on map | | |
| Line color = green (#4CAF50) | `default_color` matches green | | |
| Line modulate alpha = 0.3 (30% opacity) | Translucent overlay | | |

---

## AC-2: Color and pattern match carrier state

**Setup**: Create three routes in different states.

| Route | State | Expected Color | Expected Opacity | Actual | Pass/Fail |
|-------|-------|---------------|-----------------|--------|-----------|
| Route A | TRAVEL_TO_SOURCE | yellow (#FFC107) | 0.3 | | |
| Route B | WAITING_DESTINATION | red (#F44336) | 0.3 | | |
| Route C | DEACTIVATED (active=false) | gray (#888888) | 0.1 | | |

---

## AC-3: Hover highlights line and shows tooltip

**Setup**: Create a route, move mouse over the route line.

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Line modulate alpha changes from 0.3 → 0.6 | Brighter highlight visible | | |
| Tooltip appears | Panel with NPC name visible | | |
| Tooltip shows NPC name | NPC ID displayed | | |
| Tooltip shows distance | "Distance: N tiles" | | |
| Tooltip shows round-trip time | "Round-trip: N ticks" | | |
| Tooltip shows efficiency | "Efficiency: N%" | | |
| Tooltip hides on mouse-out | Panel hidden when mouse leaves line | | |

---

## AC-4: Route lines pan and zoom with camera

**Setup**: Create route, pan camera (WASD), zoom in/out (scroll).

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Lines stay connected to buildings during pan | No fixed-screen artifacts | | |
| Lines scale with zoom | Lines zoom in/out with world | | |
| Line endpoints align with building centers | Connected to building tile centers | | |

---

## AC-5: Inactive routes at 10% opacity

**Setup**: Pause or deactivate a route.

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Gray color (#888888) | Dim gray line | | |
| 10% opacity | Barely visible | | |

---

## AC-6 (DEFERRED): Colorblind line patterns

> **Status**: DEFERRED — excluded from this sprint per user instruction.
> Line patterns (solid/dashed/dotted) to be added in a future pass.

---

## AC-7: Route lines use dirty-flag updates

**Setup**: Monitor frame profiler while game is running with active routes.

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Lines do not redraw every frame | No per-frame clear_points()/add_point() calls in profiler | | |
| Lines redraw on carrier state change | Line updates color/opacity on next tick after state transition | | |

---

## AC-8: Route lines in world tree (not CanvasLayer)

**Setup**: Open Godot Remote Scene tree while game is running.

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| RouteLines node is child of MapRoot | Node2D child, not CanvasLayer | | |
| Tooltip CanvasLayer is child of RouteLines | RouteTooltipLayer node visible | | |

---

## Sign-off

- [ ] All non-deferred ACs pass
- [ ] Visual lead sign-off: _________________
- [ ] Date: _________________
