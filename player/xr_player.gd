extends CharacterBody3D
## Rig de jogador VR em primeira pessoa.
##
## Locomoção suave com o analógico esquerdo (relativa para onde a cabeça olha)
## e snap-turn (giro em incrementos) com o analógico direito, que é o esquema
## mais confortável para explorar ambientes fechados como um apartamento.
##
## Sem headset (OpenXR não inicializado), o rig vira um FPS comum:
## WASD/setas + mouse, Shift para andar mais rápido, Esc solta o mouse.
##
## Agachar/sentar: botão A do controle direito (VR) ou tecla C (desktop)
## alterna a visão entre em pé e abaixada, com transição suave.

## Velocidade de caminhada em metros por segundo.
@export var move_speed: float = 2.2
## Ângulo de cada giro do snap-turn, em graus.
@export var snap_turn_degrees: float = 30.0
## Zona morta dos analógicos para evitar drift.
@export var dead_zone: float = 0.2
## Sensibilidade do mouse no modo desktop (radianos por pixel).
@export var mouse_sensitivity: float = 0.003
## Multiplicador de velocidade segurando Shift no modo desktop.
@export var sprint_multiplier: float = 2.0
## Altura dos olhos no modo desktop (sem tracking a câmera ficaria no chão).
@export var desktop_eye_height: float = 1.7
## Quanto a visão abaixa ao agachar/sentar, em metros.
@export var crouch_offset: float = 0.6
## Velocidade da transição em pé <-> agachado, em metros por segundo.
@export var crouch_speed: float = 3.0

@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var collision: CollisionShape3D = $CollisionShape3D

## Garante um único giro por inclinada do analógico (precisa voltar ao centro).
var _snap_ready: bool = true
## true quando o OpenXR não inicializou e estamos rodando no monitor.
var _desktop_mode: bool = false
## true quando a visão está abaixada (agachado/sentado).
var _crouched: bool = false
## Altura original da cápsula, para restaurar ao levantar.
var _standing_capsule_height: float


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	_desktop_mode = not (xr and xr.is_initialized())
	_standing_capsule_height = (collision.shape as CapsuleShape3D).height
	right_hand.button_pressed.connect(_on_right_hand_button)
	if _desktop_mode:
		camera.position.y = desktop_eye_height
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Botão A do controle direito alterna agachado/sentado.
func _on_right_hand_button(button_name: String) -> void:
	if button_name == "ax_button":
		_crouched = not _crouched


func _unhandled_input(event: InputEvent) -> void:
	if not _desktop_mode:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(
			camera.rotation.x - event.relative.y * mouse_sensitivity,
			-PI / 2.0 + 0.01, PI / 2.0 - 0.01
		)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_C:
		_crouched = not _crouched
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_crouch(delta)
	if not _desktop_mode:
		_handle_snap_turn()


## Anima a descida/subida da visão deslocando o XROrigin3D (funciona em VR
## e desktop, já que a câmera é filha dele) e encolhe a cápsula junto.
func _handle_crouch(delta: float) -> void:
	var target := -crouch_offset if _crouched else 0.0
	if is_equal_approx(xr_origin.position.y, target):
		return
	var y := move_toward(xr_origin.position.y, target, crouch_speed * delta)
	xr_origin.position.y = y
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = _standing_capsule_height + y
	collision.position.y = capsule.height / 2.0


## Teclas físicas (WASD independe de layout) para não depender de input map.
func _desktop_input() -> Vector2:
	var x := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var y := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) \
			- float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	return Vector2(x, y).limit_length(1.0)


func _handle_movement(delta: float) -> void:
	var input: Vector2
	if _desktop_mode:
		input = _desktop_input()
	else:
		input = left_hand.get_vector2("primary")
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

	var speed := move_speed
	if _desktop_mode and Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
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

	# Inclinar para a direita gira para a direita (sentido horário = ângulo negativo).
	var angle := deg_to_rad(snap_turn_degrees) * (-1.0 if turn > 0.0 else 1.0)
	_rotate_around_point(camera.global_position, angle)


## Gira o rig inteiro ao redor da posição da câmera, para o jogador sentir
## que está parado no lugar enquanto a cena gira.
func _rotate_around_point(point: Vector3, angle: float) -> void:
	var t := global_transform
	var offset := t.origin - point
	offset = offset.rotated(Vector3.UP, angle)
	t.basis = Basis(Vector3.UP, angle) * t.basis
	t.origin = point + offset
	global_transform = t.orthonormalized()
