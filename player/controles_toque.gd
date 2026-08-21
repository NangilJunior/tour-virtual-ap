extends CanvasLayer
## Controles de toque para quem abre o tour no navegador do celular.
##
## Um analógico virtual em cada metade da tela: o esquerdo anda, o direito gira
## a câmera. Cada um nasce onde o dedo encosta e some ao soltar, então não
## importa o tamanho da tela nem onde a mão está. Os dois são desenhados só em
## contorno — um anel grande marcando onde o dedo pousou e um anel menor
## acompanhando o quanto ele já deslocou.
##
## O analógico direito gira por TAXA, e não por arrasto: enquanto o anel menor
## estiver fora do centro a câmera segue girando, na velocidade proporcional ao
## deslocamento. Antes o lado direito era arrasto relativo, que no celular
## obriga a arrastar-soltar-arrastar para dar meia-volta.
##
## Botão redondo no canto inferior direito para abrir portas, que só aparece
## quando há mesmo algo interativo por perto.
##
## Só é criado quando faz sentido (ver apartamento.gd): navegador com tela de
## toque, ou o argumento --toque na linha de comando para testar no PC.

## Emitido quando o botão de interação é tocado.
signal interagir

## Raio do anel externo, em pixels da tela base (1152x648).
@export var raio: float = 105.0
## Raio do anel interno, o que acompanha o dedo.
@export var raio_manete: float = 42.0
## Fração do raio abaixo da qual o analógico é considerado centrado. Evita a
## câmera girando sozinha por causa de um dedo parado que treme.
@export var zona_morta: float = 0.14
## Salto máximo aceitável entre dois eventos do MESMO dedo, como fração da
## largura da tela. Acima disso o evento não veio do dedo que estava ali: o
## navegador remapeou o índice do toque. Ver _tratar_arraste.
@export var salto_maximo: float = 0.35
## Velocidade de giro com o analógico no talo, em radianos por segundo.
## O vertical é mais lento de propósito: giro de pitch rápido embrulha.
@export var velocidade_giro: Vector2 = Vector2(2.4, 1.5)
## Cor das bordas dos controles.
@export var cor_borda: Color = Color(1.0, 1.0, 1.0, 0.8)
## Espessura das bordas, em pixels.
@export var largura_borda: int = 3


## Um analógico: os dois anéis, o dedo que o controla e o valor lido (-1..1).
class Analogico:
	var dedo: int = -1
	var centro: Vector2 = Vector2.ZERO
	## Última posição vista para este dedo, usada para detectar remapeamento.
	var ultima: Vector2 = Vector2.ZERO
	var valor: Vector2 = Vector2.ZERO
	var base: Control
	var manete: Control

	func mostrar(em: Vector2) -> void:
		centro = em
		ultima = em
		base.position = em - base.size * 0.5
		manete.position = em - manete.size * 0.5
		base.visible = true
		manete.visible = true

	func esconder() -> void:
		dedo = -1
		valor = Vector2.ZERO
		base.visible = false
		manete.visible = false

	## Move o anel interno. O eixo Y sai invertido (arrastar para cima = frente
	## / olhar para cima). Devolve true se precisou reancorar.
	##
	## Um dedo não teleporta: se a posição pulou mais que salto_max desde o
	## último evento, quem mudou foi o índice do toque, não a mão. Nesse caso o
	## centro é remarcado onde o evento caiu, o que faz o analógico parar. Sem
	## isso o delta trocava de sinal e a câmera girava para o lado contrário.
	func arrastar(ate: Vector2, raio_max: float, morta: float, salto_max: float) -> bool:
		var pulou := (ate - ultima).length() > salto_max
		if pulou:
			centro = ate
			base.position = ate - base.size * 0.5
		ultima = ate
		var delta := ate - centro
		if delta.length() > raio_max:
			delta = delta.normalized() * raio_max
		manete.position = centro + delta - manete.size * 0.5
		var v := delta / raio_max
		valor = Vector2.ZERO if v.length() < morta else Vector2(v.x, -v.y)
		return pulou


var _mov := Analogico.new()
var _olhar_stick := Analogico.new()
## Giro acumulado desde a última leitura do jogador, em radianos.
var _olhar: Vector2 = Vector2.ZERO
var _botao: Button


func _ready() -> void:
	# Acima do mundo 3D, abaixo do menu de pausa (layer 10).
	layer = 5
	for a: Analogico in [_mov, _olhar_stick]:
		a.base = _criar_anel(raio * 2.0)
		a.manete = _criar_anel(raio_manete * 2.0)
	_montar_botao()


## Anel vazado: sem preenchimento, só a borda.
##
## São dois Panels sobrepostos, e não um só com sombra: o shadow_size do
## StyleBoxFlat preenche o círculo inteiro em vez de contorná-lo, e o miolo
## deixa de ser vazado. Aqui o de baixo é um pouco maior e escuro, sobrando
## como um halo de 2 px por fora do branco — é o que mantém o anel legível
## tanto contra o piso claro quanto contra a marcenaria escura.
func _criar_anel(diametro: float) -> Control:
	var anel := Control.new()
	anel.size = Vector2(diametro, diametro)
	anel.visible = false
	# Não intercepta toque: quem lê os dedos é o _input daqui.
	anel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anel.add_child(_borda(diametro + 4.0, Vector2(-2.0, -2.0), Color(0.0, 0.0, 0.0, 0.5), largura_borda + 2))
	anel.add_child(_borda(diametro, Vector2.ZERO, cor_borda, largura_borda))
	add_child(anel)
	return anel


func _borda(diametro: float, em: Vector2, cor: Color, largura: int) -> Panel:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	estilo.border_color = cor
	estilo.set_border_width_all(largura)
	estilo.set_corner_radius_all(int(diametro * 0.5))

	var p := Panel.new()
	p.add_theme_stylebox_override("panel", estilo)
	p.size = Vector2(diametro, diametro)
	p.position = em
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


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
	# Canto inferior direito, acima de onde a mão direita costuma pousar.
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


## O giro é por taxa, então precisa do tempo: acumula aqui e o jogador consome.
func _process(delta: float) -> void:
	if _olhar_stick.valor != Vector2.ZERO:
		_olhar += _olhar_stick.valor * velocidade_giro * delta


## Caminhada pedida pelo analógico virtual, no mesmo formato do analógico
## esquerdo do controle (x = lados, y = frente).
func direcao() -> Vector2:
	return _mov.valor


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
		for a: Analogico in [_mov, _olhar_stick]:
			if a.dedo == toque.index:
				a.esconder()
		return
	# O botão de abrir trata o próprio toque: _input roda antes da interface,
	# então sem esta saída o mesmo dedo também giraria a câmera.
	if _botao.visible and _botao.get_global_rect().has_point(toque.position):
		return
	# Se este índice ainda estiver anotado em algum analógico, o "soltar" dele
	# se perdeu (ou o índice foi reciclado). Libera antes de reatribuir, senão
	# ficam dois analógicos achando que mandam no mesmo dedo.
	for a: Analogico in [_mov, _olhar_stick]:
		if a.dedo == toque.index:
			a.esconder()
	var meio := get_viewport().get_visible_rect().size.x * 0.5
	var alvo: Analogico = _mov if toque.position.x < meio else _olhar_stick
	if alvo.dedo != -1:
		return
	alvo.dedo = toque.index
	alvo.mostrar(toque.position)


func _tratar_arraste(arraste: InputEventScreenDrag) -> void:
	var salto := get_viewport().get_visible_rect().size.x * salto_maximo
	for a: Analogico in [_mov, _olhar_stick]:
		if a.dedo == arraste.index:
			a.arrastar(arraste.position, raio, zona_morta, salto)
			return
