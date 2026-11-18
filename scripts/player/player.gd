class_name Player
extends Node2D
## Nave del jugador: movimiento, Focus, barrel roll, escudos, estrellas y disparo.
##
## Los escudos son la vida: HealthComponent guarda escudos + 1, porque con
## 0 escudos la nave aún aguanta hasta el siguiente impacto.

signal shields_changed(shields: int, max_shields: int)
signal stars_changed(stars: int, needed: int)
## Se emite al recoger la última estrella; quien escucha limpia el escenario.
signal laser_fired
signal barrel_roll_started
signal barrel_roll_finished
signal defeated

## Margen para que la nave no salga a medias del campo.
const EDGE_MARGIN := 16.0
const ROLL_FRAMES := 8

@export var data: PlayerData

var bullets: BulletManager
var field: Rect2
var stars: int = 0
var focusing: bool = false

var _invuln_left: float = 0.0
var _roll_time: float = 0.0
var _roll_cooldown_left: float = 0.0
var _roll_dir: int = 1
var _touching: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var health: HealthComponent = $HealthComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var weapon: WeaponComponent = $WeaponComponent


func _ready() -> void:
	health.reset(data.max_shields + 1, data.start_shields + 1)
	hitbox.radius = data.hitbox_radius
	weapon.interval = data.fire_interval
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	weapon.fired.connect(_on_fired)


func is_rolling() -> bool:
	return _roll_time > 0.0


func is_targetable() -> bool:
	return not health.is_dead() and not health.invulnerable and not (data.roll_invulnerable and is_rolling())


func shields() -> int:
	return max(health.hp - 1, 0)


## Devuelve false si ya estaba al máximo (el drop se recoge igual).
func add_shield() -> bool:
	if health.is_dead() or health.hp >= health.max_hp:
		return false
	health.heal(1)
	shields_changed.emit(shields(), data.max_shields)
	return true


func add_star() -> void:
	if health.is_dead():
		return
	stars += 1
	var fire := stars >= data.stars_for_laser
	if fire:
		stars = 0
	stars_changed.emit(stars, data.stars_for_laser)
	if fire:
		laser_fired.emit()


func try_barrel_roll(dir_x: float = 0.0) -> bool:
	if health.is_dead() or is_rolling() or _roll_cooldown_left > 0.0:
		return false
	_roll_dir = -1 if dir_x < -0.1 else 1
	_roll_time = data.roll_duration
	barrel_roll_started.emit()
	return true


func _physics_process(delta: float) -> void:
	focusing = Input.is_action_pressed(&"focus")
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if Input.is_action_just_pressed(&"barrel_roll"):
		try_barrel_roll(dir.x)

	var move_speed := data.focus_speed if focusing else data.speed
	if is_rolling():
		move_speed *= data.roll_speed_mult
	_move(dir * move_speed * delta)
	_update_roll(delta)
	weapon.active = Input.is_action_pressed(&"shoot") or _touching

	if _invuln_left > 0.0:
		_invuln_left -= delta
		if _invuln_left <= 0.0:
			health.invulnerable = false
		# Parpadeo mientras dura la invulnerabilidad tras impacto.
		modulate.a = 1.0 if _invuln_left <= 0.0 or fmod(_invuln_left, 0.2) < 0.1 else 0.3
	queue_redraw()


func _update_roll(delta: float) -> void:
	if _roll_cooldown_left > 0.0:
		_roll_cooldown_left = maxf(_roll_cooldown_left - delta, 0.0)
	if _roll_time <= 0.0:
		sprite.frame = 0
		return
	_roll_time = maxf(_roll_time - delta, 0.0)
	var progress := 1.0 - (_roll_time / maxf(data.roll_duration, 0.001))
	var step := clampi(int(floor(progress * ROLL_FRAMES)), 0, ROLL_FRAMES - 1)
	sprite.frame = posmod(step * _roll_dir, ROLL_FRAMES)
	if _roll_time <= 0.0:
		sprite.frame = 0
		_roll_cooldown_left = data.roll_cooldown
		barrel_roll_finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	# Táctil: arrastre relativo con el primer dedo; dispara mientras se toca.
	if event is InputEventScreenTouch and event.index == 0:
		_touching = event.pressed
	elif event is InputEventScreenDrag and event.index == 0 and not health.is_dead():
		_move(event.relative * data.touch_sensitivity)


func _move(offset: Vector2) -> void:
	var area := field.grow(-EDGE_MARGIN)
	position = (position + offset).clamp(area.position, area.end)


func _on_damaged(_amount: int, current: int) -> void:
	shields_changed.emit(shields(), data.max_shields)
	if current > 0:
		health.invulnerable = true
		_invuln_left = data.invuln_time


func _on_died() -> void:
	weapon.active = false
	_roll_time = 0.0
	sprite.frame = 0
	set_physics_process(false)
	hide()
	defeated.emit()


func _on_fired(_origin: Vector2) -> void:
	if bullets == null:
		return
	for side: float in [-1.0, 1.0]:
		bullets.spawn(position + Vector2(side * data.shot_offset, -18.0),
				Vector2(0.0, -data.shot_speed), data.shot_radius, data.shot_color,
				BulletManager.Team.PLAYER, data.shot_damage)


func _draw() -> void:
	# Anillo de escudos: más opaco cuantos más escudos quedan.
	if shields() > 0:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 40,
				Color(0.4, 0.8, 1.0, 0.25 + 0.15 * shields()), 2.0)
	# Estela cian giratoria durante el barrel roll.
	if is_rolling():
		var progress := 1.0 - (_roll_time / maxf(data.roll_duration, 0.001))
		var start_angle := progress * TAU * _roll_dir
		draw_arc(Vector2.ZERO, 32.0, start_angle, start_angle + PI * 0.85, 24,
				Color(0.45, 0.95, 1.0, 0.75), 3.0)
		draw_arc(Vector2.ZERO, 32.0, start_angle + PI, start_angle + PI * 1.85, 24,
				Color(0.45, 0.95, 1.0, 0.75), 3.0)
	if focusing:
		draw_circle(Vector2.ZERO, data.hitbox_radius + 1.5, Color(1.0, 0.2, 0.3))
		draw_circle(Vector2.ZERO, data.hitbox_radius, Color.WHITE)
