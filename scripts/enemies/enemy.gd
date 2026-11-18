class_name Enemy
extends Node2D
## Enemigo genérico. Todo lo que lo distingue llega por `setup()` desde recursos.
##
## Los enemigos de rango ELITE no bajan hasta el fondo: descienden hasta la franja
## superior, orbitan de izquierda a derecha, disparan en cono desde sus dos cañones
## inferiores visibles y lanzan un láser periódico desde el ojo central.

signal defeated(enemy: Enemy)
signal left_field(enemy: Enemy)

var data: EnemyData
var tier: TierData
var bullets: BulletManager
var player: Player
var field: Rect2
var sway_phase: float = 0.0
var initial_fire_delay: float = -1.0
## Qué tanto se desplaza lateralmente hacia el jugador al descender (0 = solo baja).
var track_player_speed: float = 0.0
## Altura de órbita personalizada para enemigos Élite (< 0 usa data.elite_orbit_y).
var orbit_y_override: float = -1.0

var _pattern: BulletPattern
var _origin_x: float
var _time: float = 0.0
var _fire_anim_left: float = 0.0
var _entering_orbit: bool = true
var _laser_cooldown_left: float = 0.0
var _laser_charge_left: float = 0.0
var _laser_active_left: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var health: HealthComponent = $HealthComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var weapon: WeaponComponent = $WeaponComponent


## Llamar antes de añadir el enemigo al árbol.
func setup(enemy_data: EnemyData, tier_data: TierData) -> void:
	data = enemy_data
	tier = tier_data


func is_elite() -> bool:
	return tier != null and tier.rank == TierData.Rank.ELITE


func is_firing_eye_laser() -> bool:
	return _laser_active_left > 0.0


func _ready() -> void:
	add_to_group(&"enemies")
	_origin_x = position.x
	_time = sway_phase
	health.reset(roundi(data.max_hp * tier.hp_mult))
	hitbox.radius = data.radius
	health.died.connect(_on_died)
	weapon.fired.connect(_on_fired)
	if sprite:
		var tex := data.sprite_for(tier.rank)
		sprite.texture = tex
		sprite.hframes = max(data.sprite_frames, 1)
		sprite.frame = 0
		sprite.modulate = tier.tint
		if is_elite():
			# Mostramos las toberas y el rayo delante del cuerpo cuando dibuja el ojo.
			sprite.show_behind_parent = true
	_pattern = data.pattern_for(tier.rank)
	if _pattern:
		weapon.interval = _pattern.interval
		var delay := initial_fire_delay if initial_fire_delay >= 0.0 else randf_range(0.5, _pattern.interval)
		weapon.prime(delay)
		weapon.active = true
	if is_elite():
		_laser_cooldown_left = data.elite_laser_interval * 0.65


func _physics_process(delta: float) -> void:
	_time += delta
	if _fire_anim_left > 0.0:
		_fire_anim_left = maxf(_fire_anim_left - delta, 0.0)
		if _fire_anim_left <= 0.0 and sprite and _laser_active_left <= 0.0:
			sprite.frame = 0

	if is_elite():
		_process_elite(delta)
	else:
		_process_regular(delta)

	if player and player.is_targetable():
		# Chocar con el cuerpo del enemigo quita un escudo; el enemigo sigue vivo.
		var reach := data.radius + player.hitbox.radius
		if position.distance_squared_to(player.position) <= reach * reach:
			player.hitbox.hit(data.contact_damage)


func _process_regular(delta: float) -> void:
	if track_player_speed > 0.0 and player and not player.health.is_dead():
		_origin_x = move_toward(_origin_x, player.position.x, track_player_speed * delta)
	var sway_x := _origin_x + sin(_time * data.sway_frequency * TAU) * data.sway_amplitude
	if field.size.x > 0.0:
		position.x = clampf(sway_x, field.position.x + data.radius, field.end.x - data.radius)
	else:
		position.x = sway_x
	position.y += data.speed * tier.speed_mult * delta
	if position.y > field.end.y + data.radius * 2.0:
		remove_from_group(&"enemies")
		left_field.emit(self)
		queue_free()


func _process_elite(delta: float) -> void:
	var target_y := orbit_y_override if orbit_y_override > 0.0 else data.elite_orbit_y
	if _entering_orbit:
		position.y = move_toward(position.y, target_y, 170.0 * delta)
		if is_equal_approx(position.y, target_y):
			_entering_orbit = false
	else:
		position.y = target_y + sin(_time * 1.8) * 9.0

	var center_x := field.size.x * 0.5 if field.size.x > 0.0 else _origin_x
	var orbit_x := center_x + sin(_time * data.elite_orbit_frequency * TAU) * data.elite_orbit_amplitude
	if field.size.x > 0.0:
		position.x = clampf(orbit_x, field.position.x + data.radius + 12.0, field.end.x - data.radius - 12.0)
	else:
		position.x = orbit_x

	_update_elite_eye_laser(delta)
	queue_redraw()


func _update_elite_eye_laser(delta: float) -> void:
	if _entering_orbit:
		return
	if _laser_active_left > 0.0:
		_laser_active_left = maxf(_laser_active_left - delta, 0.0)
		if sprite:
			sprite.frame = 1
		if player and player.is_targetable() and player.position.y >= position.y:
			var half_w := data.elite_laser_width * 0.5 + player.hitbox.radius
			if absf(player.position.x - position.x) <= half_w:
				player.hitbox.hit(1)
		if _laser_active_left <= 0.0:
			_laser_cooldown_left = data.elite_laser_interval
			if sprite and _fire_anim_left <= 0.0:
				sprite.frame = 0
	elif _laser_charge_left > 0.0:
		_laser_charge_left = maxf(_laser_charge_left - delta, 0.0)
		if _laser_charge_left <= 0.0:
			_laser_active_left = data.elite_laser_duration
	else:
		_laser_cooldown_left = maxf(_laser_cooldown_left - delta, 0.0)
		if _laser_cooldown_left <= 0.0:
			_laser_charge_left = data.elite_laser_charge_time


func _on_fired(_origin: Vector2) -> void:
	if bullets == null or position.y < field.position.y:
		return
	if sprite and sprite.texture != null and sprite.hframes > 1:
		sprite.frame = 1
		_fire_anim_left = 0.22
	var target := player.position if player else position + Vector2.DOWN

	if is_elite():
		# Enemigo Élite: dispara en cono hacia abajo desde los dos cañones inferiores visibles.
		if _pattern:
			for side: float in [-1.0, 1.0]:
				var nozzle := position + Vector2(side * data.elite_cannon_offset.x, data.elite_cannon_offset.y)
				_pattern.emit(bullets, nozzle, nozzle + Vector2.DOWN)
		if data.orange_shot_chance > 0.0 and randf() < data.orange_shot_chance \
				and bullets.try_consume_orange_cooldown(data.orange_shot_min_interval):
			bullets.spawn(position + Vector2(0.0, data.elite_cannon_offset.y),
					Vector2.DOWN * data.orange_shot_speed, data.orange_shot_radius,
					data.orange_shot_color, BulletManager.Team.ENEMY, 1, true)
		return

	if data.orange_shot_chance > 0.0 and randf() < data.orange_shot_chance \
			and bullets.try_consume_orange_cooldown(data.orange_shot_min_interval):
		var dir := Vector2.DOWN
		if _pattern and _pattern.aimed and not target.is_equal_approx(position):
			dir = (target - position).normalized()
		bullets.spawn(position, dir * data.orange_shot_speed, data.orange_shot_radius,
				data.orange_shot_color, BulletManager.Team.ENEMY, 1, true)
		return
	if _pattern:
		_pattern.emit(bullets, position, target)


func _on_died() -> void:
	remove_from_group(&"enemies")
	defeated.emit(self)
	queue_free()


func _draw() -> void:
	var c := data.color * tier.tint
	if tier.glow_strength > 0.0 and (sprite == null or sprite.texture == null):
		draw_circle(Vector2.ZERO, data.radius * 1.5, Color(c, 0.25 * tier.glow_strength))
	if sprite == null or sprite.texture == null:
		# Forma provisional solo si el arquetipo aún no tiene sprite asignado.
		draw_circle(Vector2.ZERO, data.radius, c)
		draw_circle(Vector2.ZERO, data.radius * 0.4, c.darkened(0.5))

	if is_elite():
		var beam_len := (field.end.y - position.y) if field.size.y > 0.0 else 1100.0
		if _laser_charge_left > 0.0:
			var ratio := 1.0 - (_laser_charge_left / maxf(data.elite_laser_charge_time, 0.001))
			draw_circle(Vector2.ZERO, 4.0 + ratio * 6.0, Color(1.0, 0.3, 0.1, 0.45 + ratio * 0.45))
			draw_line(Vector2.ZERO, Vector2(0.0, beam_len),
					Color(1.0, 0.25, 0.15, 0.2 + ratio * 0.45), 1.5 + ratio * 1.5)
		elif _laser_active_left > 0.0:
			var fade := clampf(_laser_active_left / maxf(data.elite_laser_duration, 0.001), 0.2, 1.0)
			var w := data.elite_laser_width
			draw_rect(Rect2(-w * 0.85, 0.0, w * 1.7, beam_len), Color(1.0, 0.2, 0.1, 0.28 * fade))
			draw_rect(Rect2(-w * 0.5, 0.0, w, beam_len), Color(1.0, 0.45, 0.15, 0.82 * fade))
			draw_rect(Rect2(-w * 0.2, 0.0, w * 0.4, beam_len), Color(1.0, 0.95, 0.8, 0.95 * fade))
			draw_circle(Vector2.ZERO, w * 0.65, Color(1.0, 0.85, 0.5, 0.9))
