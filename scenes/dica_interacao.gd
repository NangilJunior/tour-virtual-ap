extends Node3D
## Dica de interação: uma caixinha de contorno branco com a tecla/botão que
## abre o objeto em foco, discreta no centro-baixo da visão, aparecendo e
## sumindo com fade rápido.
##
## É desenhada em 3D (SubViewport → quad preso à câmera) em vez de um
## CanvasLayer porque a interface 2D não aparece dentro do headset — assim a
## mesma dica serve para VR e desktop.
##
## O rótulo muda sozinho conforme o que a pessoa está usando no momento:
## gatilho (VR/Quest), tecla E (teclado) ou botão X (controle). O
## rastreamento é por último evento recebido, então trocar de teclado para
## controle no meio do passeio atualiza a dica na hora.

## Distância da dica até os olhos, em metros.
@export var distancia: float = 1.0
## Quanto a dica fica abaixo do centro da visão, em metros (na [distancia]
## acima). 0.6 a 1 m ≈ 31° abaixo da linha do olhar — junto à base da tela no
## desktop (a borda inferior fica em ~37°, com o FOV vertical padrão de 75°) e
## bem dentro do campo de visão no headset, que é mais alto.
@export var altura: float = -0.6
## Largura do quad da dica, em metros (na [distancia] acima). A altura é
## metade disso, seguindo o formato do viewport.
@export var largura: float = 0.16
## Duração do fade de entrada/saída, em segundos.
@export var duracao_fade: float = 0.12

## Rótulos por dispositivo.
const ROTULO_VR := "Gatilho"
const ROTULO_TECLADO := "E"
const ROTULO_CONTROLE := "X"
const ROTULO_TOQUE := "Abrir"

## Resolução do viewport onde a caixinha é desenhada. Bem maior que o tamanho
## em tela para o contorno e o texto ficarem nítidos de perto no headset.
const RESOLUCAO := Vector2i(256, 128)

var _viewport: SubViewport
var _label: Label
var _quad: MeshInstance3D
var _material: StandardMaterial3D
var _tween: Tween
var _visivel: bool = false
var _rotulo_atual: String = ""


func _ready() -> void:
	position = Vector3(0.0, altura, -distancia)
	_montar_viewport()
	_montar_quad()
	_atualizar_rotulo()
	_material.albedo_color.a = 0.0
	_quad.visible = false


## Desenha a caixinha (contorno branco + tecla) num viewport transparente.
func _montar_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RESOLUCAO
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	# UPDATE_ONCE: o conteúdo só muda quando o rótulo muda (troca de
	# dispositivo), então não há motivo para redesenhar todo frame.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	estilo.border_color = Color(1.0, 1.0, 1.0, 0.9)
	estilo.set_border_width_all(3)
	estilo.set_corner_radius_all(10)
	estilo.set_content_margin_all(8)

	var painel := PanelContainer.new()
	painel.set_anchors_preset(Control.PRESET_FULL_RECT)
	painel.add_theme_stylebox_override("panel", estilo)
	_viewport.add_child(painel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Encolhe sozinho quando o rótulo é longo ("Gatilho") em vez de vazar
	# para fora da caixinha.
	_label.clip_text = true
	_label.add_theme_font_size_override("font_size", 56)
	_label.add_theme_color_override("font_color", Color.WHITE)
	painel.add_child(_label)


## Quad preso à câmera mostrando a textura do viewport, sem sombreamento e
## sem teste de profundidade (senão paredes e portas cortariam a dica).
func _montar_quad() -> void:
	var malha := QuadMesh.new()
	malha.size = Vector2(largura, largura * 0.5)

	_material = StandardMaterial3D.new()
	_material.albedo_texture = _viewport.get_texture()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	_material.render_priority = 10
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	_quad = MeshInstance3D.new()
	_quad.name = "Caixa"
	_quad.mesh = malha
	_quad.material_override = _material
	# Fica fora do lightmap/GI e não projeta sombra: é interface, não cenário.
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_quad)


## Último dispositivo usado, para escolher o rótulo. Fica em _input (e não em
## _unhandled_input) para enxergar o evento mesmo quando outro nó o consome,
## e nunca marca o evento como tratado.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# No celular a dica só lembra o nome do botão que está na tela.
		_definir_rotulo(ROTULO_TOQUE)
	elif event is InputEventKey or event is InputEventMouseButton:
		_definir_rotulo(ROTULO_TECLADO)
	elif event is InputEventJoypadButton:
		_definir_rotulo(ROTULO_CONTROLE)
	elif event is InputEventJoypadMotion:
		# Só deflexão clara: eixo parado com drift não conta como "usando o
		# controle" (senão um analógico ruim sequestraria o rótulo do teclado).
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_definir_rotulo(ROTULO_CONTROLE)


func _definir_rotulo(rotulo: String) -> void:
	if _rotulo_atual == rotulo:
		return
	_rotulo_atual = rotulo
	_label.text = rotulo
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Em VR o rótulo é sempre o gatilho, independente de eventos de teclado ou
## controle que possam chegar da máquina que roda o streaming.
func _atualizar_rotulo() -> void:
	if get_viewport().use_xr:
		_definir_rotulo(ROTULO_VR)
	elif _rotulo_atual.is_empty():
		_definir_rotulo(ROTULO_TECLADO)


## Mostra ou esconde a dica com fade rápido. Chamada a cada checagem de foco;
## repetir o mesmo estado não reinicia a animação.
func definir_visivel(mostrar: bool) -> void:
	if mostrar:
		_atualizar_rotulo()
	if mostrar == _visivel:
		return
	_visivel = mostrar
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if mostrar:
		_quad.visible = true
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_material, "albedo_color:a", 1.0 if mostrar else 0.0, duracao_fade)
	if not mostrar:
		# Some do desenho de vez ao terminar de sumir.
		_tween.tween_callback(func() -> void: _quad.visible = false)
