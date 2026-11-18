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
signal barrel_roll_deflected
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
var _deflect_flash: float = 0.0
var _charge_time: float = 0.0
var _charge_cooldown_left: float = 0.0
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


func can_deflect() -> bool:
	return not health.is_dead() and is_rolling()


func roll_cooldown_left() -> float:
	return _roll_cooldown_left


func charge_ratio() -> float:
	return clampf(_charge_time / maxf(data.charge_duration, 0.001), 0.0, 1.0)


func is_targetable() -> bool:
	return not health.is_dead() and not health.invulnerable


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


func on_barrel_roll_deflect() -> void:
	_deflect_flash = 0.2
	add_star()
	barrel_roll_deflected.emit()


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
	_update_charged_shot(delta)
	weapon.active = (Input.is_action_pressed(&"shoot") or _touching) and _charge_time <= 0.0

	if _deflect_flash > 0.0:
		_deflect_flash = maxf(_deflect_flash - delta, 0.0)

	if _invuln_left > 0.0:
		_invuln_left -= delta
		if _invuln_left <= 0.0:
			health.invulnerable = false
		# Parpadeo mientras dura la invulnerabilidad tras impacto.
		modulate.a = 1.0 if _invuln_left <= 0.0 or fmod(_invuln_left, 0.2) < 0.1 else 0.3
	queue_redraw()


func _update_charged_shot(delta: float) -> void:
	if _charge_cooldown_left > 0.0:
		_charge_cooldown_left = maxf(_charge_cooldown_left - delta, 0.0)
	if Input.is_action_pressed(&"charged_shoot") and _charge_cooldown_left <= 0.0:
		_charge_time += delta
		if _charge_time >= data.charge_duration:
			_fire_charged_shot()
			_charge_time = 0.0
			_charge_cooldown_left = data.charge_cooldown
	else:
		_charge_time = 0.0


func _fire_charged_shot() -> void:
	if bullets == null:
		return
	# Equivale a 5 disparos completos del arma (2 cañones × shot_damage × 5 = 10).
	var dmg := data.shot_damage * 2 * data.charged_shot_multiplier
	bullets.spawn(position + Vector2(0.0, -24.0),
			Vector2(0.0, -data.charged_shot_speed), data.charged_shot_radius,
			data.charged_shot_color, BulletManager.Team.PLAYER, dmg)


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
	_charge_time = 0.0
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
	# Esfera de energía en la proa mientras se carga el tiro con Click Derecho.
	if _charge_time > 0.0:
		var ratio := charge_ratio()
		var nose := Vector2(0.0, -24.0)
		draw_circle(nose, 4.0 + ratio * 10.0, Color(0.25, 0.95, 1.0, 0.35 + ratio * 0.45))
		draw_circle(nose, 2.0 + ratio * 5.0, Color(1.0, 1.0, 1.0, 0.85))
		draw_arc(nose, 18.0 - ratio * 8.0, 0.0, TAU * ratio, 24,
				Color(0.4, 0.98, 1.0, 0.9), 2.0)
	# Estela cian giratoria durante el barrel roll.
	if is_rolling():
		var progress := 1.0 - (_roll_time / maxf(data.roll_duration, 0.001))
		var start_angle := progress * TAU * _roll_dir
		draw_arc(Vector2.ZERO, 32.0, start_angle, start_angle + PI * 0.85, 24,
				Color(0.45, 0.95, 1.0, 0.75), 3.0)
		draw_arc(Vector2.ZERO, 32.0, start_angle + PI, start_angle + PI * 1.85, 24,
				Color(0.45, 0.95, 1.0, 0.75), 3.0)
	# Destello dorado al rebotar un tiro naranja.
	if _deflect_flash > 0.0:
		var a := _deflect_flash / 0.2
		draw_arc(Vector2.ZERO, 36.0 + (1.0 - a) * 14.0, 0.0, TAU, 32,
				Color(1.0, 0.65, 0.15, a * 0.9), 3.5)
	if focusing:
		draw_circle(Vector2.ZERO, data.hitbox_radius + 1.5, Color(1.0, 0.2, 0.3))
		draw_circle(Vector2.ZERO, data.hitbox_radius, Color.WHITE)
