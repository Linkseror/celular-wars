class_name Enemy
extends Node2D
## Enemigo genérico. Todo lo que lo distingue llega por `setup()` desde recursos.

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

var _pattern: BulletPattern
var _origin_x: float
var _time: float = 0.0
var _fire_anim_left: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var health: HealthComponent = $HealthComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var weapon: WeaponComponent = $WeaponComponent


## Llamar antes de añadir el enemigo al árbol.
func setup(enemy_data: EnemyData, tier_data: TierData) -> void:
	data = enemy_data
	tier = tier_data


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
	_pattern = data.pattern_for(tier.rank)
	if _pattern:
		weapon.interval = _pattern.interval
		var delay := initial_fire_delay if initial_fire_delay >= 0.0 else randf_range(0.5, _pattern.interval)
		weapon.prime(delay)
		weapon.active = true


func _physics_process(delta: float) -> void:
	_time += delta
	if _fire_anim_left > 0.0:
		_fire_anim_left = maxf(_fire_anim_left - delta, 0.0)
		if _fire_anim_left <= 0.0 and sprite:
			sprite.frame = 0
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
	elif player and player.is_targetable():
		# Chocar con el cuerpo del enemigo quita un escudo; el enemigo sigue vivo.
		var reach := data.radius + player.hitbox.radius
		if position.distance_squared_to(player.position) <= reach * reach:
			player.hitbox.hit(data.contact_damage)


func _on_fired(_origin: Vector2) -> void:
	if bullets == null or position.y < field.position.y:
		return
	if sprite and sprite.texture != null and sprite.hframes > 1:
		sprite.frame = 1
		_fire_anim_left = 0.22
	var target := player.position if player else position + Vector2.DOWN
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
	if tier.glow_strength > 0.0:
		draw_circle(Vector2.ZERO, data.radius * 1.5, Color(c, 0.25 * tier.glow_strength))
	if sprite == null or sprite.texture == null:
		# Forma provisional solo si el arquetipo aún no tiene sprite asignado.
		draw_circle(Vector2.ZERO, data.radius, c)
		draw_circle(Vector2.ZERO, data.radius * 0.4, c.darkened(0.5))
