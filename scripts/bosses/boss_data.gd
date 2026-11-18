class_name BossData
extends Resource
## Datos de balance de un jefe con ciclo de escudos omnidireccionales.

@export var display_name: String = "Giroscopio Orbital"
@export var max_hp: int = 240
@export var radius: float = 68.0
@export var contact_damage: int = 1

@export_group("Movimiento")
@export var entry_speed: float = 140.0
@export var combat_y: float = 240.0
@export var sway_amplitude: float = 190.0
@export var sway_frequency: float = 0.14
@export var enrage_hp_ratio: float = 0.5
@export var enrage_speed_mult: float = 1.35

@export_group("Escudos Omnidireccionales")
## Segundos que permanece con los escudos cerrados (resistente).
@export var closed_duration: float = 5.0
## Segundos que permanece con los escudos abiertos (vulnerable).
@export var open_duration: float = 4.5
## Multiplicador de daño cuando los escudos están cerrados (0.25 = 1 de cada 4 impactos).
@export_range(0.05, 1.0) var closed_damage_mult: float = 0.25
## Daño directo que recibe del láser de 3 estrellas del jugador (además de abrirle el escudo).
@export var laser_damage: int = 45

@export_group("Patrones de Disparo")
@export var pattern_closed: BulletPattern
@export var pattern_open: BulletPattern

@export_group("Disparo Naranja (Barrel Roll)")
@export_range(0.0, 1.0) var orange_shot_chance: float = 0.42
@export var orange_shot_min_interval: float = 2.4
@export var orange_shot_speed: float = 215.0
@export var orange_shot_radius: float = 10.0
@export var orange_shot_color: Color = Color(1.0, 0.45, 0.05)
