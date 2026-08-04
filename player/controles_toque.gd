extends CanvasLayer
## Controles de toque para quem abre o tour no navegador do celular.
##
## Metade esquerda da tela: analógico virtual que nasce onde o dedo encosta e
## some ao soltar — assim não importa o tamanho da tela nem onde a mão está.
## Metade direita: arrasta para olhar em volta. Botão redondo no canto
## inferior direito para abrir portas, que só aparece quando há mesmo algo
## interativo por perto (mesma checagem que acende a dica da tecla).
##
## Só é criado quando faz sentido (ver apartamento.gd): navegador com tela de
## toque, ou o argumento --toque na linha de comando para testar no PC.

## Emitido quando o botão de interação é tocado.
signal interagir

## Raio do analógico virtual, em pixels da tela base (1152x648).
@export var raio: float = 90.0
## Sensibilidade do arraste de olhar, em radianos por pixel arrastado.
@export var sensibilidade_olhar: float = 0.005
## Cor das bordas dos controles.
@export var cor_borda: Color = Color(1.0, 1.0, 1.0, 0.55)

## Direção de caminhada no formato do analógico esquerdo (-1..1 nos dois eixos).
var _direcao: Vector2 = Vector2.ZERO
## Giro pedido pelo arraste desde a última leitura, em radianos.
var _olhar: Vector2 = Vector2.ZERO
## Índice do dedo que está no analógico e do que está arrastando a visão
## (-1 = nenhum). Guardar o índice é o que permite os dois ao mesmo tempo.
var _dedo_mov: int = -1
var _dedo_olhar: int = -1
## Onde o dedo do analógico encostou: é o centro do controle.
var _centro: Vector2 = Vector2.ZERO

var _base: Panel
var _manete: Panel
var _botao: Button


func _ready() -> void:
	# Acima do mundo 3D, abaixo do menu de pausa (layer 10).
	layer = 5
	_base = _criar_circulo(raio * 2.0, Color(0.0, 0.0, 0.0, 0.25))
	_manete = _criar_circulo(raio * 0.85, Color(1.0, 1.0, 1.0, 0.25))
	_montar_botao()


func _criar_circulo(diametro: float, fundo: Color) -> Panel:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = fundo
	estilo.border_color = cor_borda
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(int(diametro * 0.5))

	var circulo := Panel.new()
	circulo.add_theme_stylebox_override("panel", estilo)
	circulo.size = Vector2(diametro, diametro)
	circulo.visible = false
	# Não intercepta toque: quem lê os dedos é o _input daqui.
	circulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(circulo)
	return circulo


func _montar_botao() -> void:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	estilo.border_color = Color(1.0, 1.0, 1.0, 0.85)
	estilo.set_border_width_all(3)
	estilo.set_corner_radius_all(70)

	var estilo_apertado := estilo.duplicate() as StyleBoxFlat
	estilo_apertado.bg_color = Color(1.0, 1.0, 1.0, 0.3)

	_botao = Button.new()
	_botao.text = "Abrir"
	_botao.add_theme_stylebox_override("normal", estilo)
	_botao.add_theme_stylebox_override("hover", estilo)
	_botao.add_theme_stylebox_override("focus", estilo)
	_botao.add_theme_stylebox_override("pressed", estilo_apertado)
	_botao.add_theme_font_size_override("font_size", 28)
	_botao.add_theme_color_override("font_color", Color.WHITE)
	# Ancorado no canto inferior direito: 140x140, a 60 px da borda direita e
	# 90 px do fundo, para não brigar com a barra do navegador no celular.
	_botao.anchor_left = 1.0
	_botao.anchor_top = 1.0
	_botao.anchor_right = 1.0
	_botao.anchor_bottom = 1.0
	_botao.offset_left = -200.0
	_botao.offset_top = -230.0
	_botao.offset_right = -60.0
	_botao.offset_bottom = -90.0
	_botao.visible = false
	_botao.pressed.connect(func() -> void: interagir.emit())
	add_child(_botao)


## Caminhada pedida pelo analógico virtual, no mesmo formato do analógico
## esquerdo do controle (x = lados, y = frente).
func direcao() -> Vector2:
	return _direcao


## Giro acumulado desde a última chamada, em radianos, e zera o acumulador —
## o jogador soma isso no alvo do olhar dele.
func consumir_olhar() -> Vector2:
	var giro := _olhar
	_olhar = Vector2.ZERO
	return giro


## Mostra o botão de abrir só quando há algo interativo ao alcance.
func definir_interacao_disponivel(disponivel: bool) -> void:
	_botao.visible = disponivel


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_tratar_toque(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_tratar_arraste(event as InputEventScreenDrag)


func _tratar_toque(toque: InputEventScreenTouch) -> void:
	if not toque.pressed:
		if toque.index == _dedo_mov:
			_soltar_analogico()
		elif toque.index == _dedo_olhar:
			_dedo_olhar = -1
		return
	# O botão de abrir trata o próprio toque: _input roda antes da interface,
	# então sem esta saída o mesmo dedo também giraria a câmera.
	if _botao.visible and _botao.get_global_rect().has_point(toque.position):
		return
	var meio := get_viewport().get_visible_rect().size.x * 0.5
	if toque.position.x < meio and _dedo_mov == -1:
		_dedo_mov = toque.index
		_centro = toque.position
		_base.position = _centro - _base.size * 0.5
		_base.visible = true
		_manete.position = _centro - _manete.size * 0.5
		_manete.visible = true
	elif _dedo_olhar == -1:
		_dedo_olhar = toque.index


func _tratar_arraste(arraste: InputEventScreenDrag) -> void:
	if arraste.index == _dedo_mov:
		var delta := arraste.position - _centro
		if delta.length() > raio:
			delta = delta.normalized() * raio
		_manete.position = _centro + delta - _manete.size * 0.5
		# y invertido: arrastar para cima na tela é andar para frente.
		_direcao = Vector2(delta.x, -delta.y) / raio
	elif arraste.index == _dedo_olhar:
		_olhar += arraste.relative * sensibilidade_olhar


func _soltar_analogico() -> void:
	_dedo_mov = -1
	_direcao = Vector2.ZERO
	_base.visible = false
	_manete.visible = false
