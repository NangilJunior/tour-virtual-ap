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

@onready var modelo: Node3D = $Modelo


func _ready() -> void:
	super()
	var inicio := Time.get_ticks_msec()
	var total := _gerar_colisoes(modelo)
	print("Colisão do apartamento: %d meshes em %d ms" % [total, Time.get_ticks_msec() - inicio])


func _gerar_colisoes(no: Node) -> int:
	var total := 0
	for filho in no.get_children():
		total += _gerar_colisoes(filho)

	if no is MeshInstance3D and no.mesh:
		# Tamanho no mundo: AABB local escalado pela escala global do nó.
		var tamanho: Vector3 = no.get_aabb().size * no.global_transform.basis.get_scale()
		var maior := maxf(tamanho.x, maxf(tamanho.y, tamanho.z))
		var menor := minf(tamanho.x, minf(tamanho.y, tamanho.z))
		if maior >= 2.5 and menor <= 0.25:
			no.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		var nome := no.name.to_lower()
		for termo in ignorar_nomes:
			if termo in nome:
				return total
		if tamanho.x >= dimensao_minima or tamanho.y >= dimensao_minima or tamanho.z >= dimensao_minima:
			no.create_trimesh_collision()
			total += 1
	return total
