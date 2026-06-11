class_name BuildingStatusIndicator extends Node2D
## Small circular status indicator for production buildings.
## Yellow = idle (no active production cycle).
## Green pie sector filling clockwise = production cycle in progress.

const _RADIUS: int = 5
const _BG_COLOR: Color = Color(0.06, 0.06, 0.06, 0.88)
const _IDLE_COLOR: Color = Color(0.95, 0.78, 0.12)
const _WORKING_COLOR: Color = Color(0.18, 0.82, 0.28)
const _CONSTRUCTION_COLOR: Color = Color(0.55, 0.78, 1.0)
const _BORDER_COLOR: Color = Color(0.0, 0.0, 0.0, 0.65)
const _FAN_STEPS: int = 24

enum _Mode { IDLE, WORKING, CONSTRUCTING }

var _progress: float = 0.0
var _mode: _Mode = _Mode.IDLE


func set_idle() -> void:
	_mode = _Mode.IDLE
	_progress = 0.0
	queue_redraw()


func set_progress(progress: float) -> void:
	_mode = _Mode.WORKING
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func set_construction_progress(progress: float) -> void:
	_mode = _Mode.CONSTRUCTING
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, float(_RADIUS), _BG_COLOR)

	var fill_color: Color
	match _mode:
		_Mode.IDLE:
			draw_circle(Vector2.ZERO, float(_RADIUS - 1), _IDLE_COLOR)
			draw_arc(Vector2.ZERO, float(_RADIUS), 0.0, TAU, 16, _BORDER_COLOR, 1.0)
			return
		_Mode.WORKING:
			fill_color = _WORKING_COLOR
		_Mode.CONSTRUCTING:
			fill_color = _CONSTRUCTION_COLOR

	if _progress >= 1.0:
		draw_circle(Vector2.ZERO, float(_RADIUS - 1), fill_color)
	else:
		var inner_r: float = float(_RADIUS - 1)
		var start_angle: float = -PI * 0.5
		var end_angle: float = start_angle + TAU * _progress
		var points := PackedVector2Array()
		points.append(Vector2.ZERO)
		for i in range(_FAN_STEPS + 1):
			var angle: float = lerpf(start_angle, end_angle, float(i) / float(_FAN_STEPS))
			points.append(Vector2(cos(angle) * inner_r, sin(angle) * inner_r))
		draw_polygon(points, PackedColorArray([fill_color]))

	draw_arc(Vector2.ZERO, float(_RADIUS), 0.0, TAU, 16, _BORDER_COLOR, 1.0)
