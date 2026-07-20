extends Node3D
## Controla o menu inicial (Modo VR / Modo Desktop) e ativa o runtime OpenXR
## ou o modo desktop conforme a escolha do usuário.
##
## Se a cena não tiver o nó "ModoMenu" (cenas de teste como main.tscn e
## test_room.tscn), cai automaticamente no comportamento antigo: detecta o
## headset e entra direto em VR, ou em desktop se não achar nada.

var xr_interface: XRInterface

@onready var menu: CanvasLayer = get_node_or_null("ModoMenu")
@onready var menu_pausa: CanvasLayer = get_node_or_null("MenuPausa")


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if menu:
		_mostrar_menu()
	elif xr_interface and xr_interface.is_initialized():
		_ativar_vr()
	else:
		_ativar_desktop()

	if menu_pausa:
		var vbox_pausa := menu_pausa.get_node("Centro/Painel/VBox")
		(vbox_pausa.get_node("BotaoContinuar") as Button).pressed.connect(_on_continuar)
		(vbox_pausa.get_node("BotaoSair") as Button).pressed.connect(_on_sair)


func _mostrar_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var vbox := menu.get_node("Centro/Painel/VBox")
	(vbox.get_node("BotaoVR") as Button).pressed.connect(_on_escolher_vr)
	(vbox.get_node("BotaoDesktop") as Button).pressed.connect(_on_escolher_desktop)


## Botão "Menu" (☰) do controle (Xbox/ROG Ally/Steam Deck): abre/fecha o
## menu de pausa com a opção Sair — importante em dispositivos sem teclado,
## onde não dá pra usar Esc/Alt+F4 pra fechar o aplicativo.
func _unhandled_input(event: InputEvent) -> void:
	if not menu_pausa:
		return
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_START:
		if menu and menu.visible:
			return
		_alternar_pausa()


func _alternar_pausa() -> void:
	if menu_pausa.visible:
		_on_continuar()
	else:
		menu_pausa.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var jogador := get_node_or_null("XRPlayer")
		if jogador:
			jogador.set_physics_process(false)
		(menu_pausa.get_node("Centro/Painel/VBox/BotaoContinuar") as Button).grab_focus()


func _on_continuar() -> void:
	menu_pausa.visible = false
	var jogador := get_node_or_null("XRPlayer")
	if jogador:
		jogador.set_physics_process(true)
		if jogador.get("_desktop_mode"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_sair() -> void:
	get_tree().quit()


func _on_escolher_vr() -> void:
	if not (xr_interface and xr_interface.is_initialized()):
		if not xr_interface or not xr_interface.initialize():
			_avisar(
				"Headset não detectado. Conecte o headset e deixe o runtime "
				+ "(SteamVR/Monado) aberto antes de escolher Modo VR."
			)
			return
	_ativar_vr()
	_esconder_menu()


func _on_escolher_desktop() -> void:
	if xr_interface and xr_interface.is_initialized():
		xr_interface.uninitialize()
	_ativar_desktop()
	_esconder_menu()


func _ativar_vr() -> void:
	print("Modo VR ativado — renderizando no headset.")
	# O VR roda na taxa de atualização nativa do headset; desliga o vsync da janela.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Supersampling leve: nitidez extra no headset sem estourar o custo por
	# pixel (1.2x ≈ 44% mais pixels; 1.5x seriam 125% a mais).
	if xr_interface is OpenXRInterface:
		(xr_interface as OpenXRInterface).render_target_size_multiplier = 1.2
	get_viewport().use_xr = true
	_configurar_jogador(false)


func _ativar_desktop() -> void:
	print("Modo desktop ativado — WASD/setas + mouse, Shift corre, Esc solta o mouse.")
	get_viewport().use_xr = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_configurar_jogador(true)


func _configurar_jogador(desktop: bool) -> void:
	var jogador := get_node_or_null("XRPlayer")
	if jogador:
		jogador.configurar_modo(desktop)


func _avisar(texto: String) -> void:
	var aviso := menu.get_node("Centro/Painel/VBox/Aviso") as Label
	aviso.text = texto
	aviso.visible = true


func _esconder_menu() -> void:
	menu.visible = false
