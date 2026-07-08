extends CharacterBody3D
## Rig de jogador VR: locomoção suave no analógico esquerdo (relativa à cabeça)
## e snap-turn no analógico direito.

## Velocidade de caminhada em metros por segundo.
@export var move_speed: float = 2.2
## Ângulo de cada giro do snap-turn, em graus.
@export var snap_turn_degrees: float = 30.0
## Zona morta dos analógicos para evitar drift.
@export var dead_zone: float = 0.2

@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand

## Garante um único giro por inclinada do analógico.
var _snap_ready: bool = true


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_snap_turn()


func _handle_movement(delta: float) -> void:
	var input := left_hand.get_vector2("primary")
	if input.length() < dead_zone:
		input = Vector2.ZERO

	# Direção relativa à orientação do headset, achatada no plano do chão.
	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction := (right * input.x + forward * input.y)

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta

	move_and_slide()


func _handle_snap_turn() -> void:
	var turn := right_hand.get_vector2("primary").x
	if absf(turn) < 0.6:
		_snap_ready = true
		return
	if not _snap_ready:
		return
	_snap_ready = false

	var angle := deg_to_rad(snap_turn_degrees) * (-1.0 if turn > 0.0 else 1.0)
	_rotate_around_point(camera.global_position, angle)


## Gira o rig ao redor da posição da câmera (jogador sente que gira no lugar).
func _rotate_around_point(point: Vector3, angle: float) -> void:
	var t := global_transform
	var offset := t.origin - point
	offset = offset.rotated(Vector3.UP, angle)
	t.basis = Basis(Vector3.UP, angle) * t.basis
	t.origin = point + offset
	global_transform = t.orthonormalized()
