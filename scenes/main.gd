extends Node3D
## Inicializa o runtime OpenXR e direciona a renderização para o headset.
## Se nenhum headset/runtime estiver disponível, cai para modo desktop (preview),
## o que é útil para testar a cena sem colocar o óculos.

var xr_interface: XRInterface


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR inicializado com sucesso — renderizando no headset.")
		# O VR roda na taxa de atualização nativa do headset; desliga o vsync da janela.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
	else:
		push_warning("OpenXR não inicializado. Rodando em modo desktop (preview).")
