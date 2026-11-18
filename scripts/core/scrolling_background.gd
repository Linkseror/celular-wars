class_name ScrollingBackground
extends Node2D
## Fondo del Nivel 1 (Vena Braquial — Brazo del paciente).
##
## Combina el shader del vaso sanguíneo con glóbulos rojos, micro-gotas de suero de
## inyección al inicio del nivel y chispas bio-eléctricas al acercarse al jefe.

const BG_SHADER := preload("res://shaders/bloodstream_bg.gdshader")

@export var field_size: Vector2 = Vector2(720.0, 1280.0)
@export var far_speed: float = 135.0
@export var near_speed: float = 235.0

var stage_progress: float = 0.0

var _shader_rect: ColorRect
var _shader_mat: ShaderMaterial
var _far_cells: Array[Dictionary] = []
var _near_cells: Array[Dictionary] = []


func _ready() -> void:
	z_index = -10
	_shader_rect = ColorRect.new()
	_shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_rect.size = field_size
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = BG_SHADER
	_shader_rect.material = _shader_mat
	add_child(_shader_rect)
	_populate_cells()


func setup(size: Vector2) -> void:
	field_size = size
	if _shader_rect:
		_shader_rect.size = size
	_populate_cells()


func set_stage_progress(progress: float) -> void:
	stage_progress = clampf(progress, 0.0, 1.0)
	if _shader_mat:
		_shader_mat.set_shader_parameter(&"stage_progress", stage_progress)


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
	for i in 26:
		# 0 = glóbulo rojo, 1 = mota bioluminiscente, 2 = micro-burbuja del suero de inyección
		var kind := 0
		if i % 3 == 1:
			kind = 1
		elif i % 3 == 2:
			kind = 2
		_near_cells.append({
			"pos": Vector2(rng.randf_range(18.0, field_size.x - 18.0), rng.randf_range(0.0, field_size.y)),
			"radius": rng.randf_range(2.5, 5.5) if kind != 0 else rng.randf_range(16.0, 32.0),
			"alpha": rng.randf_range(0.18, 0.34) if kind != 0 else rng.randf_range(0.10, 0.20),
			"kind": kind,
		})


func _physics_process(delta: float) -> void:
	var speed_mult := 1.0 + stage_progress * 0.45
	_advance_layer(_far_cells, far_speed * speed_mult * delta)
	_advance_layer(_near_cells, near_speed * speed_mult * delta)
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
		var kind: int = c["kind"]
		if kind == 2:
			# Burbujas cian del suero de inyección al principio; viran a violeta cerca del jefe.
			var col := Color(0.25, 0.85, 1.0).lerp(Color(0.75, 0.35, 1.0), stage_progress)
			_draw_cell(c, col)
		elif kind == 1:
			_draw_cell(c, Color(0.95, 0.45, 0.65))
		else:
			_draw_cell(c, Color(0.7, 0.12, 0.24))


func _draw_cell(c: Dictionary, base_color: Color) -> void:
	var p: Vector2 = c["pos"]
	var r: float = c["radius"]
	var a: float = c["alpha"]
	if c["kind"] != 0:
		draw_circle(p, r * 2.1, Color(base_color, a * 0.28))
		draw_circle(p, r, Color(base_color, a))
	else:
		# Glóbulo rojo estilizado: borde más brillante y centro cóncavo.
		draw_circle(p, r, Color(base_color, a))
		draw_circle(p, r * 0.5, Color(0.08, 0.01, 0.04, a * 0.9))
