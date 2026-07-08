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
		# Supersampling: renderiza acima da resolução nativa e reduz, deixando a
		# imagem bem mais nítida no headset. Como é PCVR, a GPU do PC aguenta.
		if xr_interface is OpenXRInterface:
			(xr_interface as OpenXRInterface).render_target_size_multiplier = 1.5
		get_viewport().use_xr = true
	else:
		push_warning("OpenXR não inicializado. Rodando em modo desktop (preview).")
