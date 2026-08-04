class_name CenaPrincipal
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
@onready var world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment")


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	print("Plataforma: %s | web=%s | menu=%s" % [
		OS.get_name(), OS.has_feature("web"), menu != null])
	if _e_web():
		# Navegador não tem OpenXR: nada de menu de escolha, entra direto no
		# passeio em primeira pessoa (teclado/mouse no PC, toque no celular).
		# O menu é removido, não só escondido — assim não há como ele voltar
		# na frente do passeio.
		if menu:
			menu.queue_free()
			menu = null
		_ativar_desktop()
	elif menu:
		_mostrar_menu()
	elif xr_interface and xr_interface.is_initialized():
		_ativar_vr()
	else:
		_ativar_desktop()

	if menu_pausa:
		var vbox_pausa := menu_pausa.get_node("Centro/Painel/VBox")
		(vbox_pausa.get_node("BotaoContinuar") as Button).pressed.connect(_on_continuar)
		(vbox_pausa.get_node("BotaoSair") as Button).pressed.connect(_on_sair)


## true quando o tour está rodando dentro de um navegador. Testa as duas
## formas porque uma marca de recurso mal resolvida não pode ser o motivo de
## um menu de VR ficar preso na frente de quem abriu a página.
func _e_web() -> bool:
	return OS.has_feature("web") or OS.get_name() == "Web"


func _mostrar_menu() -> void:
	if _e_web():
		return
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
	# Checagem pelo nome da classe, e não pelo tipo: o template web não tem o
	# módulo OpenXR, então escrever OpenXRInterface aqui vira identificador
	# desconhecido e derruba a compilação DESTE script inteiro no navegador —
	# junto com apartamento.gd, que herda dele.
	if xr_interface != null and xr_interface.get_class() == "OpenXRInterface":
		xr_interface.set("render_target_size_multiplier", 1.2)
	get_viewport().use_xr = true
	_configurar_jogador(false)
	# SSR e depth of field custam frame time e, em VR, DOF incomoda (o olho já
	# foca fisicamente na distância certa) — ligados só no modo desktop.
	_configurar_pos_processamento(false)


func _ativar_desktop() -> void:
	print("Modo desktop ativado — WASD/setas + mouse, Shift corre, Esc solta o mouse.")
	get_viewport().use_xr = false
	# Tela cheia só no aplicativo nativo: no navegador quem manda no tamanho
	# da janela é a página, e pedir fullscreen sem um clique do usuário é
	# recusado pelo próprio navegador.
	if not _e_web():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_configurar_jogador(true)
	_configurar_pos_processamento(true)


## Reflexo de tela (piso) e desfoque de profundidade: só no modo desktop
## (ver _ativar_vr para o motivo de ficarem fora da VR).
func _configurar_pos_processamento(desktop: bool) -> void:
	if not world_environment:
		return
	if world_environment.environment:
		world_environment.environment.ssr_enabled = desktop
	# Depth of field mora em CameraAttributes (não em Environment) desde o
	# Godot 4; aplicado globalmente via WorldEnvironment.camera_attributes.
	if world_environment.camera_attributes:
		world_environment.camera_attributes.dof_blur_far_enabled = desktop


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
