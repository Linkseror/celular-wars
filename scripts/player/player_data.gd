class_name PlayerData
extends Resource
## Valores de balance del jugador.

## Distancia a la que se recoge un drop.
@export var pickup_radius: float = 26.0

@export_group("Movimiento")
@export var speed: float = 336.0
@export var focus_speed: float = 144.0
## Multiplicador del arrastre táctil (1 = la nave se mueve lo mismo que el dedo).
@export var touch_sensitivity: float = 1.0

@export_group("Barrel Roll")
## Duración de la animación completa de 360° en segundos.
@export var roll_duration: float = 0.36
## Tiempo de espera tras terminar el giro antes de poder hacer otro.
@export var roll_cooldown: float = 0.8
## Multiplicador de velocidad mientras dura el barrel roll.
@export var roll_speed_mult: float = 1.45
## Radio alrededor de la nave capaz de rebotar el disparo naranja especial.
@export var roll_deflect_radius: float = 28.0
## Multiplicador de velocidad del disparo naranja al rebotar.
@export var roll_reflect_speed_mult: float = 1.6

@export_group("Escudos")
## Escudos al empezar el nivel. Con 0 escudos, el siguiente impacto destruye la nave.
@export var start_shields: int = 3
@export var max_shields: int = 5
## Segundos de invulnerabilidad tras perder un escudo.
@export var invuln_time: float = 2.0
@export var hitbox_radius: float = 4.0

@export_group("Láser")
## Estrellas que hay que recoger para lanzar el láser.
@export var stars_for_laser: int = 3
## Segundos que dura el rayo en pantalla (la limpieza es instantánea).
@export var laser_duration: float = 0.7

@export_group("Disparo")
@export var fire_interval: float = 0.1
@export var shot_speed: float = 900.0
@export var shot_radius: float = 5.0
@export var shot_damage: int = 1
## Separación horizontal de los dos cañones respecto al centro.
@export var shot_offset: float = 10.0
@export var shot_color: Color = Color(0.5, 0.85, 1.0)
