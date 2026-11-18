class_name Boss
extends Node2D
## Jefe circular ("Giroscopio Orbital") con escudos omnidireccionales que alternan
## entre estado CERRADO (resistente) y ABIERTO (vulnerable).
##
## Forma parte del grupo `enemies` para que BulletManager colisione los disparos
## del jugador con su `HitboxComponent` sin duplicar lógica.

signal shield_state_changed(is_open: bool)
signal hp_changed(current_hp: int, max_hp: int)
signal defeated(boss: Boss)

const TRANSITION_WARN_TIME := 0.65

@export var data: BossData

var bullets: BulletManager
var player: Player
var field: Rect2

var _entering: bool = true
var _shields_open: bool = false
var _state_timer: float = 0.0
var _time: float = 0.0
var _origin_x: float = 0.0
var _armor_fractional_dmg: float = 0.0
var _hit_flash: float = 0.0
var _ring_pulse: float = 0.0
var _burst_counter: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var health: HealthComponent = $HealthComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var weapon: WeaponComponent = $WeaponComponent


func setup(boss_data: BossData) -> void:
	data = boss_data


func is_shields_open() -> bool:
	return _shields_open


func is_enraged() -> bool:
	return float(health.hp) <= float(health.max_hp) * data.enrage_hp_ratio


func _ready() -> void:
	add_to_group(&"bosses")
	_origin_x = position.x
	health.reset(data.max_hp)
	hitbox.radius = data.radius
	# El daño se filtra en `_on_hit_received` para aplicar la reducción del escudo cerrado.
	hitbox.health = null
	hitbox.hit_received.connect(_on_hit_received)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	weapon.fired.connect(_on_fired)
	_set_shields_open(false)


func _set_shields_open(open_state: bool) -> void:
	_shields_open = open_state
	var mult := 0.8 if is_enraged() else 1.0
	_state_timer = (data.open_duration if _shields_open else data.closed_duration) * mult
	if sprite:
		sprite.frame = 1 if _shields_open else 0
	var pat := data.pattern_open if _shields_open else data.pattern_closed
	if pat:
		weapon.interval = pat.interval * (0.78 if is_enraged() else 1.0)
		weapon.prime(0.35)
		weapon.active = not _entering
	# Pulso visual de apertura/cierre.
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "scale", Vector2(0.33, 0.33), 0.10)
		tw.tween_property(sprite, "scale", Vector2(0.30, 0.30), 0.14)
	shield_state_changed.emit(_shields_open)


## El láser de 3 estrellas fuerza la apertura del escudo y aplica daño directo.
func apply_laser_strike() -> void:
	if health.is_dead():
		return
	if not _shields_open:
		_set_shields_open(true)
	_hit_flash = 0.28
	health.take_damage(data.laser_damage)


func _physics_process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
	if _ring_pulse > 0.0:
		_ring_pulse = maxf(_ring_pulse - delta, 0.0)

	if _entering:
		position.y = move_toward(position.y, data.combat_y, data.entry_speed * delta)
		if is_equal_approx(position.y, data.combat_y):
			_entering = false
			weapon.active = true
		queue_redraw()
		return

	var speed_mult := data.enrage_speed_mult if is_enraged() else 1.0
	_time += delta * speed_mult
	position.x = _origin_x + sin(_time * data.sway_frequency * TAU) * data.sway_amplitude
	position.y = data.combat_y + sin(_time * data.sway_frequency * 2.0 * TAU) * 18.0

	# Rotación suave de los escudos en modo cerrado; fijo o oscilante al abrir.
	if sprite:
		if not _shields_open:
			sprite.rotation += delta * (0.55 if not is_enraged() else 0.9)
		else:
			sprite.rotation = lerp_angle(sprite.rotation, 0.0, delta * 6.0)

	_state_timer -= delta
	if _state_timer <= 0.0:
		_set_shields_open(not _shields_open)

	if player and player.is_targetable():
		var reach := data.radius + player.hitbox.radius
		if position.distance_squared_to(player.position) <= reach * reach:
			player.hitbox.hit(data.contact_damage)

	queue_redraw()


func _on_hit_received(amount: int) -> void:
	if health.is_dead():
		return
	if _shields_open:
		_hit_flash = 0.12
		health.take_damage(amount)
	else:
		# Escudos cerrados: absorbe gran parte del impacto y destella el anillo magnético.
		_ring_pulse = 0.16
		_armor_fractional_dmg += float(amount) * data.closed_damage_mult
		var whole := int(floor(_armor_fractional_dmg))
		if whole >= 1:
			_armor_fractional_dmg -= float(whole)
			health.take_damage(whole)


func _on_damaged(_amount: int, current: int) -> void:
	hp_changed.emit(current, health.max_hp)


func _on_fired(_origin: Vector2) -> void:
	if bullets == null or _entering:
		return
	_burst_counter += 1
	var target := player.position if player else position + Vector2.DOWN
	var pat := data.pattern_open if _shields_open else data.pattern_closed
	if pat:
		pat.emit(bullets, position, target)
		# En estado abierto y furioso añade un anillo defensivo cada 2 ráfagas.
		if _shields_open and is_enraged() and (_burst_counter % 2 == 0) and data.pattern_closed:
			data.pattern_closed.emit(bullets, position, target)

	# Disparo naranja brillante periódico para que el jugador pueda rebotarlo con Barrel Roll (F).
	if data.orange_shot_chance > 0.0 and randf() < data.orange_shot_chance \
			and bullets.try_consume_orange_cooldown(data.orange_shot_min_interval):
		var dir := (target - position).normalized()
		if dir.is_zero_approx():
			dir = Vector2.DOWN
		bullets.spawn(position, dir * data.orange_shot_speed, data.orange_shot_radius,
				data.orange_shot_color, BulletManager.Team.ENEMY, 1, true)


func _on_died() -> void:
	weapon.active = false
	remove_from_group(&"bosses")
	defeated.emit(self)
	queue_free()


func _draw() -> void:
	var warning := _state_timer <= TRANSITION_WARN_TIME
	if not _shields_open:
		# Barrera omnidireccional activa cuando los 4 escudos están cerrados.
		var pulse_a := 0.35 + (_ring_pulse / 0.16) * 0.45
		var ring_col := Color(1.0, 0.75, 0.25, pulse_a) if warning else Color(0.35, 0.85, 1.0, pulse_a)
		draw_arc(Vector2.ZERO, data.radius + 8.0, 0.0, TAU, 48, ring_col, 3.0)
		draw_circle(Vector2.ZERO, data.radius + 6.0, Color(ring_col.r, ring_col.g, ring_col.b, 0.08))
	else:
		# Halo cálido de vulnerabilidad cuando las bobinas internas están expuestas.
		var vuln_col := Color(0.35, 0.85, 1.0, 0.55) if warning else Color(1.0, 0.35, 0.2, 0.42)
		draw_arc(Vector2.ZERO, data.radius - 6.0, 0.0, TAU, 48, vuln_col, 2.0)

	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, data.radius * 0.65, Color(1.0, 0.9, 0.7, (_hit_flash / 0.28) * 0.35))
