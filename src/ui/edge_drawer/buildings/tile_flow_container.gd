class_name TileFlowContainer extends MarginContainer
## Wrapper that combines consistent margin padding with an HFlowContainer for building tiles.
## Tiles are added to the inner HFlowContainer via add_tile() / clear_tiles().

const H_SEPARATION := 8
const V_SEPARATION := 8
const MARGIN := 12

var _flow: HFlowContainer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("margin_left",   MARGIN)
	add_theme_constant_override("margin_right",  MARGIN)
	add_theme_constant_override("margin_top",    MARGIN)
	add_theme_constant_override("margin_bottom", MARGIN)

	_flow = HFlowContainer.new()
	_flow.name = "Flow"
	_flow.add_theme_constant_override("h_separation", H_SEPARATION)
	_flow.add_theme_constant_override("v_separation", V_SEPARATION)
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_flow)


## Appends a tile to the inner flow container.
func add_tile(tile: Control) -> void:
	if _flow == null:
		push_warning("[TileFlowContainer] Flow not ready — call after _ready()")
		return
	_flow.add_child(tile)


## Removes all tiles from the flow container.
func clear_tiles() -> void:
	if _flow == null:
		return
	for child: Node in _flow.get_children():
		child.queue_free()
