class_name EdgeDrawerConfig extends Resource
## Configuration resource for an EdgeDrawerController instance.
## Each drawer that uses EdgeDrawerController creates one of these to describe
## its visual identity, geometry, and layer placement — no hardcoded values in
## the controller itself.
##
## Usage:
##   var cfg := EdgeDrawerConfig.new()
##   cfg.tab_glyph = "📋"
##   cfg.tab_label = "Tasks"
##   cfg.tab_top_margin = 104.0
##   controller.setup(content, cfg, canvas_layer)

## Glyph rendered at the top of the tab (emoji or single character).
## E.g. "📋", "🏛", "🚚".
@export var tab_glyph: String = ""

## Short label rendered below the glyph inside the tab (optional — used for
## tooltip fallback and accessibility text). E.g. "Tasks", "Routes".
@export var tab_label: String = ""

## Distance in pixels from the top of the screen to the top edge of the tab.
## Stack multiple drawers by assigning non-overlapping margins.
## Default matches the Tasks drawer position (below fertility indicators).
@export var tab_top_margin: float = 104.0

## Width of the slide-in content panel in pixels.
@export var panel_width: float = 520.0

## CanvasLayer.layer index assigned to the owning CanvasLayer.
## Higher values render on top; ensure no two drawers share the same index.
@export var layer_index: int = 21

## Pixels the tab nudges toward the screen centre on mouse hover (visual
## feedback; panel does NOT open on hover).
@export var hover_peek_distance: float = 12.0
