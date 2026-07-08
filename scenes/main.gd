extends Node3D
## Inicializa o OpenXR e direciona a renderização para o headset.
## Sem headset/runtime disponível, roda em modo desktop (preview).

var xr_interface: XRInterface


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR inicializado — renderizando no headset.")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
	else:
		push_warning("OpenXR não inicializado. Rodando em modo desktop (preview).")
