extends "res://scenes/main.gd"
## Gera colisão estática para o modelo do apartamento na carga da cena.
##
## O .blend importado tem milhares de meshes sem colisão; aqui cada
## MeshInstance3D grande o suficiente ganha um StaticBody3D trimesh via
## create_trimesh_collision(). Objetos pequenos (louças, decoração) ficam
## sem colisor — o jogador não esbarra neles e o custo de física despenca.
##
## No mesmo passeio, superfícies GRANDES E FINAS (laje, paredes — face única
## no SketchUp) viram casters de sombra dupla-face, senão o sol atravessa o
## teto visto de cima (face de costas não projeta sombra). Móveis ficam com
## sombra normal: dupla-face em volume fechado causa manchas pretas de
## auto-sombra.

## Só gera colisão se alguma dimensão do objeto for pelo menos isso (em metros).
@export var dimensao_minima: float = 0.4
## Objetos cujo nome contém um destes termos ficam sem colisão.
## Portas entram por padrão: se alguma estiver modelada fechada, colisão
## nela trancaria o jogador no cômodo.
@export var ignorar_nomes: PackedStringArray = ["porta"]

## Camada de renderização (2ª, das 20 do motor) usada pelas molduras/paredes
## que não devem receber luz direta do sol — o Sun (DirectionalLight3D) tem
## essa camada desligada no light_cull_mask. Continuam recebendo luz normal
## das luminárias e do ambiente; só ficam fora do sol.
const CAMADA_SEM_SOL := 2
## Grupo (Node > Groups no editor) pra marcar manualmente paredes do
## corredor sem sol direto — molduras de porta ("batente" ou "moldura" no
## nome) entram automaticamente, sem precisar marcar.
const GRUPO_SEM_SOL := "sem_sol_corredor"

@onready var modelo: Node3D = $Modelo
@onready var lightmap: LightmapGI = $LightmapGI

## Guarda o lightmap pra alternar no diagnóstico de flick (tecla L /
## botão X do controle esquerdo): sem lightmap, objetos probe-lit perdem a
## fonte suspeita — se o flick sumir, a causa são as probes.
var _lm_data: LightmapGIData


func _ready() -> void:
	super()
	# Desliga a troca de LOD das meshes: em VR o pulo de nível de detalhe ao
	# mover a cabeça aparece como "flick" na cena inteira (e cada olho pode
	# escolher um LOD diferente). Detalhe máximo sempre.
	get_viewport().mesh_lod_threshold = 0.0
	var inicio := Time.get_ticks_msec()
	var total := _gerar_colisoes(modelo)
	print("Colisão do apartamento: %d meshes em %d ms" % [total, Time.get_ticks_msec() - inicio])
	var sem_sol := _tirar_sol(modelo)
	print("Sem luz direta do sol: %d objetos" % sem_sol)
	_lm_data = lightmap.light_data
	var mao_esq: XRController3D = $XRPlayer/XROrigin3D/LeftHand
	mao_esq.button_pressed.connect(_on_left_button)
	# portas internas interativas (tecla E / gatilho direito)
	var portas := preload("res://scenes/portas_interativas.gd").new()
	portas.name = "PortasInterativas"
	add_child(portas)
	portas.configurar(modelo, $XRPlayer)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_L:
		_alternar_lightmap()


## Botão X (esquerdo) alterna o lightmap — diagnóstico do flick.
func _on_left_button(button_name: String) -> void:
	if button_name == "ax_button":
		_alternar_lightmap()


func _alternar_lightmap() -> void:
	lightmap.light_data = null if lightmap.light_data else _lm_data
	print("Lightmap: ", "DESLIGADO" if lightmap.light_data == null else "ligado")


## Tira as molduras de porta ("batente" no nome) e qualquer objeto marcado
## no grupo GRUPO_SEM_SOL da camada 1 (movendo pra CAMADA_SEM_SOL), que o
## Sun não enxerga (light_cull_mask). Evita as manchas de luz vazando pelas
## portas pro corredor sem apagar a luz das luminárias nem esconder o objeto
## da câmera (ela continua vendo todas as camadas).
func _tirar_sol(no: Node) -> int:
	var total := 0
	for filho in no.get_children():
		total += _tirar_sol(filho)
	if no is VisualInstance3D:
		var nome := no.name.to_lower()
		if "batente" in nome or "moldura" in nome or no.is_in_group(GRUPO_SEM_SOL):
			no.layers = CAMADA_SEM_SOL
			total += 1
	return total


## true se o nó está na coleção 01_Arquitetura (nome próprio ou de ancestral).
func _pertence_a_arquitetura(no: Node) -> bool:
	var p: Node = no
	while p and p != modelo:
		if "Arquitetura" in p.name:
			return true
		p = p.get_parent()
	return false


func _gerar_colisoes(no: Node) -> int:
	var total := 0
	for filho in no.get_children():
		total += _gerar_colisoes(filho)

	if no is MeshInstance3D and no.mesh:
		# Tamanho no mundo: AABB local escalado pela escala global do nó.
		var tamanho: Vector3 = no.get_aabb().size * no.global_transform.basis.get_scale()
		var maior := maxf(tamanho.x, maxf(tamanho.y, tamanho.z))
		if _pertence_a_arquitetura(no):
			# Laje/paredes (face única do SketchUp): sombra dupla-face, senão
			# o sol atravessa. Móveis NÃO — dupla-face neles vira mancha preta.
			no.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		elif maior < dimensao_minima:
			# Objeto pequeno não projeta sombra: corta milhares de draw calls
			# do shadow map do sol (o SSAO segue dando o contato visual).
			no.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var nome := no.name.to_lower()
		for termo in ignorar_nomes:
			if termo in nome:
				return total
		if tamanho.x >= dimensao_minima or tamanho.y >= dimensao_minima or tamanho.z >= dimensao_minima:
			no.create_trimesh_collision()
			total += 1
	return total
