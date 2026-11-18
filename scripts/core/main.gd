extends Node
## Nivel 1: Inyección en el brazo del paciente (6 minutos de avance por la vena braquial
## seguidos del combate contra el jefe nanobot "Giroscopio Orbital").

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/bosses/boss.tscn")
const SHIELD_PICKUP := preload("res://scenes/pickups/shield_pickup.tscn")
const STAR_PICKUP := preload("res://scenes/pickups/star_pickup.tscn")
const TEST_ENEMY: EnemyData = preload("res://resources/enemies/bacteriofago_menor.tres")
const TEST_TIER: TierData = preload("res://resources/tiers/regular.tres")
const LEVEL_BOSS_DATA: BossData = preload("res://resources/bosses/giroscopio_orbital.tres")

const LEVEL_DURATION := 360.0
const RESTART_DELAY := 1.5
const WAVE_PAUSE := 1.1

## True mientras el láser elimina enemigos: esas bajas no sueltan drops.
var _laser_sweep: bool = false
var _elapsed_time: float = 0.0
var _wave_index: int = 0
var _spawning_wave: bool = false
var _wave_pending: bool = false
var _boss_spawned: bool = false
var _boss_defeated: bool = false
var _boss: Boss = null

@onready var playfield: Playfield = $Playfield
@onready var background: ScrollingBackground = $Playfield/ScrollingBackground
@onready var bullets: BulletManager = $Playfield/BulletManager
@onready var player: Player = $Playfield/Player
@onready var status: Label = $HUD/Status


func _ready() -> void:
	var field := playfield.rect()
	background.setup(field.size)
	bullets.field = field
	bullets.player = player
	player.bullets = bullets
	player.field = field
	player.position = Vector2(field.size.x * 0.5, field.size.y - 180.0)
	player.shields_changed.connect(func(_s: int, _m: int) -> void: _update_status())
	player.stars_changed.connect(func(_s: int, _n: int) -> void: _update_status())
	player.barrel_roll_started.connect(_update_status)
	player.barrel_roll_finished.connect(_update_status)
	player.laser_fired.connect(_on_laser_fired)
	player.defeated.connect(_on_player_defeated)
	_update_status()
	_launch_next_wave()


func _process(delta: float) -> void:
	if not player.health.is_dead() and not _boss_defeated:
		_elapsed_time = minf(_elapsed_time + delta, LEVEL_DURATION)
		background.set_stage_progress(_elapsed_time / LEVEL_DURATION)
		if Input.is_action_just_pressed(&"skip_to_boss") and not _boss_spawned:
			_skip_to_boss_fight()
		elif _elapsed_time >= LEVEL_DURATION and not _boss_spawned:
			_check_wave_cleared()
	_update_status()


func _skip_to_boss_fight() -> void:
	_elapsed_time = LEVEL_DURATION
	background.set_stage_progress(1.0)
	_laser_sweep = true
	for enemy: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_laser_sweep = false
	bullets.clear(BulletManager.Team.ENEMY)
	_spawn_boss()


func _launch_next_wave() -> void:
	if _spawning_wave or _wave_pending or _boss_spawned:
		return
	if _elapsed_time >= LEVEL_DURATION:
		_spawn_boss()
		return
	_spawning_wave = true
	_wave_index += 1
	_update_status()
	var field := playfield.rect()
	var pattern_kind := (_wave_index - 1) % 4
	match pattern_kind:
		0:
			# Tanda 1: fila descendente en abanico suave.
			for i in 5:
				var x := field.size.x * (i + 1) / 6.0
				_spawn_enemy(Vector2(x, -30.0 - absf(i - 2) * 18.0), i * 0.35, 0.5 + i * 0.25)
		1:
			# Tanda 2: formación en V bajando hacia el jugador.
			for i in 5:
				var offset := i - 2
				var x := field.size.x * 0.5 + offset * 105.0
				var y := -30.0 - (2 - absi(offset)) * 42.0
				_spawn_enemy(Vector2(x, y), offset * 0.25, 0.6 + absf(offset) * 0.3)
		2:
			# Tanda 3: cascada diagonal escalonada.
			var left_to_right := (_wave_index % 2) == 1
			for i in 5:
				var idx := i if left_to_right else (4 - i)
				var x := field.size.x * (idx + 1) / 6.0
				_spawn_enemy(Vector2(x, -30.0), i * 0.4, 0.7)
				if i < 4:
					await get_tree().create_timer(0.32).timeout
					if not is_inside_tree() or player.health.is_dead() or _boss_spawned:
						_spawning_wave = false
						return
		3:
			# Tanda 4: tenaza por los flancos con ligero acercamiento al jugador.
			for row in 3:
				for side: float in [-1.0, 1.0]:
					var x := field.size.x * (0.5 + side * 0.32)
					_spawn_enemy(Vector2(x, -35.0), (row + (0 if side < 0 else 2)) * 0.3, 0.6 + row * 0.35, 22.0)
				if row < 2:
					await get_tree().create_timer(0.55).timeout
					if not is_inside_tree() or player.health.is_dead() or _boss_spawned:
						_spawning_wave = false
						return
	_spawning_wave = false
	_check_wave_cleared()


func _spawn_enemy(pos: Vector2, sway_phase: float = 0.0, fire_delay: float = -1.0,
		track_speed: float = 0.0) -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.setup(TEST_ENEMY, TEST_TIER)
	enemy.bullets = bullets
	enemy.player = player
	enemy.field = playfield.rect()
	enemy.position = pos
	enemy.sway_phase = sway_phase
	enemy.initial_fire_delay = fire_delay
	enemy.track_player_speed = track_speed
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.left_field.connect(_on_enemy_left_field)
	playfield.add_child(enemy)


func _spawn_boss() -> void:
	if _boss_spawned or player.health.is_dead():
		return
	_boss_spawned = true
	var field := playfield.rect()
	_boss = BOSS_SCENE.instantiate()
	_boss.setup(LEVEL_BOSS_DATA)
	_boss.bullets = bullets
	_boss.player = player
	_boss.field = field
	_boss.position = Vector2(field.size.x * 0.5, -110.0)
	_boss.defeated.connect(_on_boss_defeated)
	playfield.add_child(_boss)
	_update_status()


func _on_boss_defeated(_defeated_boss: Boss) -> void:
	_boss = null
	_boss_defeated = true
	bullets.clear(BulletManager.Team.ENEMY)
	_update_status()


func _on_enemy_defeated(enemy: Enemy) -> void:
	if not _laser_sweep:
		_roll_drop(enemy)
	_check_wave_cleared()


func _on_enemy_left_field(_enemy: Enemy) -> void:
	_check_wave_cleared()


func _check_wave_cleared() -> void:
	if _spawning_wave or _wave_pending or _boss_spawned or player.health.is_dead():
		return
	if get_tree().get_nodes_in_group(&"enemies").is_empty():
		if _elapsed_time >= LEVEL_DURATION:
			_spawn_boss()
			return
		_wave_pending = true
		await get_tree().create_timer(WAVE_PAUSE).timeout
		_wave_pending = false
		if is_inside_tree() and not player.health.is_dead() and not _boss_spawned:
			_launch_next_wave()


## Como mucho un drop por enemigo: primero se sortea el escudo y después la estrella.
func _roll_drop(enemy: Enemy) -> void:
	var roll := randf()
	var scene: PackedScene = null
	if roll < enemy.data.shield_drop_chance:
		scene = SHIELD_PICKUP
	elif roll < enemy.data.shield_drop_chance + enemy.data.star_drop_chance:
		scene = STAR_PICKUP
	if scene == null:
		return
	var pickup: Pickup = scene.instantiate()
	pickup.player = player
	pickup.field = playfield.rect()
	pickup.position = enemy.position
	playfield.add_child.call_deferred(pickup)


## El láser limpia todas las balas enemigas y los enemigos normales; contra el jefe
## fuerza la apertura de sus escudos y le inflige daño pesado.
func _on_laser_fired() -> void:
	bullets.clear(BulletManager.Team.ENEMY)
	_laser_sweep = true
	for enemy: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.health.take_damage(enemy.health.hp)
	_laser_sweep = false
	for boss: Boss in get_tree().get_nodes_in_group(&"bosses"):
		boss.apply_laser_strike()
	var beam := LaserBeam.new()
	beam.field = playfield.rect()
	beam.duration = player.data.laser_duration
	beam.position = player.position
	beam.z_index = 2
	playfield.add_child(beam)


func _on_player_defeated() -> void:
	await get_tree().create_timer(RESTART_DELAY).timeout
	get_tree().reload_current_scene()


func _format_time(sec: float) -> String:
	var total := int(floor(sec))
	return "%02d:%02d" % [total / 60, total % 60]


func _update_status() -> void:
	var roll_text := "LISTO"
	if player.is_rolling():
		roll_text = "ACTIVO"
	elif player.roll_cooldown_left() > 0.0:
		roll_text = "%.1fs" % player.roll_cooldown_left()

	var base_hud := "Escudos: %d/%d   Estrellas: %d/%d   [Espacio] Roll: %s" % [
		player.shields(), player.data.max_shields, player.stars,
		player.data.stars_for_laser, roll_text]

	if _boss_defeated:
		status.text = base_hud + "\n¡GIROSCOPIO ORBITAL DESTRUIDO! — Brazo despejado"
	elif _boss != null and is_instance_valid(_boss):
		var shield_txt := "ABIERTOS (VULNERABLE)" if _boss.is_shields_open() else "CERRADOS (RESISTENTE)"
		status.text = "%s\nJEFE: %s  HP: %d/%d  |  Escudos: %s" % [
			base_hud, _boss.data.display_name, _boss.health.hp, _boss.health.max_hp, shield_txt]
	else:
		status.text = "%s\nVena Braquial: %s / %s   Tanda: %d   ([F2] Saltar al Jefe)" % [
			base_hud, _format_time(_elapsed_time), _format_time(LEVEL_DURATION), _wave_index]
