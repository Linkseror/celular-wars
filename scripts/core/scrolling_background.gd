class_name ScrollingBackground
extends Node2D
## Fondo biológico en movimiento para transmitir avance continuo por el torrente sanguíneo.
##
## Combina el shader de tejido/plasma con dos capas paralelas de glóbulos y motas
## bioluminiscentes que descienden a distinta velocidad.

const BG_SHADER := preload("res://shaders/bloodstream_bg.gdshader")

@export var field_size: Vector2 = Vector2(720.0, 1280.0)
@export var far_speed: float = 135.0
@export var near_speed: float = 235.0

var _shader_rect: ColorRect
var _far_cells: Array[Dictionary] = []
var _near_cells: Array[Dictionary] = []


func _ready() -> void:
	z_index = -10
	_shader_rect = ColorRect.new()
	_shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_rect.size = field_size
	var mat := ShaderMaterial.new()
	mat.shader = BG_SHADER
	_shader_rect.material = mat
	add_child(_shader_rect)
	_populate_cells()


func setup(size: Vector2) -> void:
	field_size = size
	if _shader_rect:
		_shader_rect.size = size
	_populate_cells()


func _populate_cells() -> void:
	_far_cells.clear()
	_near_cells.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42017
	for _i in 18:
		_far_cells.append({
			"pos": Vector2(rng.randf_range(24.0, field_size.x - 24.0), rng.randf_range(0.0, field_size.y)),
			"radius": rng.randf_range(12.0, 26.0),
			"alpha": rng.randf_range(0.08, 0.16),
			"kind": 0,
		})
	for _i in 22:
		var is_mote := rng.randf() < 0.55
		_near_cells.append({
			"pos": Vector2(rng.randf_range(18.0, field_size.x - 18.0), rng.randf_range(0.0, field_size.y)),
			"radius": rng.randf_range(2.5, 5.0) if is_mote else rng.randf_range(16.0, 32.0),
			"alpha": rng.randf_range(0.18, 0.34) if is_mote else rng.randf_range(0.10, 0.20),
			"kind": 1 if is_mote else 0,
		})


func _physics_process(delta: float) -> void:
	_advance_layer(_far_cells, far_speed * delta)
	_advance_layer(_near_cells, near_speed * delta)
	queue_redraw()


func _advance_layer(cells: Array[Dictionary], dy: float) -> void:
	var h := field_size.y + 80.0
	for c: Dictionary in cells:
		var p: Vector2 = c["pos"]
		p.y += dy
		if p.y > field_size.y + 40.0:
			p.y -= h
		c["pos"] = p


func _draw() -> void:
	for c: Dictionary in _far_cells:
		_draw_cell(c, Color(0.55, 0.08, 0.18))
	for c: Dictionary in _near_cells:
		var base := Color(0.95, 0.45, 0.65) if c["kind"] == 1 else Color(0.7, 0.12, 0.24)
		_draw_cell(c, base)


func _draw_cell(c: Dictionary, base_color: Color) -> void:
	var p: Vector2 = c["pos"]
	var r: float = c["radius"]
	var a: float = c["alpha"]
	if c["kind"] == 1:
		draw_circle(p, r * 2.0, Color(base_color, a * 0.28))
		draw_circle(p, r, Color(base_color, a))
	else:
		# Glóbulo rojo estilizado: borde más brillante y centro hundido.
		draw_circle(p, r, Color(base_color, a))
		draw_circle(p, r * 0.5, Color(0.08, 0.01, 0.04, a * 0.9))
