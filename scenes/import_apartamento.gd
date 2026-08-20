@tool
extends EditorScenePostImport
## Pós-import do APARTAMENTO.blend: garante que toda malha visível receba GI de
## verdade — lightmap quando ela tem UV2, probes quando não tem.
##
## Sem isso o modelo se parte em três regimes de iluminação e o MESMO material
## aparece com cores diferentes de um objeto para o outro:
##   1. STATIC com UV2   -> entra no bake, luz completa;
##   2. STATIC sem UV2   -> o bake IGNORA (não há onde gravar os texels) e o
##                          objeto fica só com ambient_light_energy (0.08),
##                          ou seja, praticamente sem luz;
##   3. DYNAMIC          -> fora do bake, iluminado pelas probes.
## O caso 2 é o que mais destoa, e é silencioso: nada avisa que o objeto ficou
## de fora. Aqui ele é rebaixado para probes, que é muito mais próximo do
## lightmap do que o ambiente puro.
##
## ATENÇÃO: o Godot NÃO reimporta a cena quando só o conteúdo deste script muda
## (o .import e o md5 do .blend continuam iguais). Depois de editar aqui, force
## a reimportação apagando o cache:
##     rm .godot/imported/APARTAMENTO.blend-*
##     godot --headless --editor --quit
## e refaça o bake do LightmapGI, senão a alteração não tem efeito nenhum.


## Densidade extra de lightmap nas folhas de porta. O bake global roda a
## 0,05 m/texel (lightmap_texel_size 0.1 do .import x texel_scale 2.0 do
## LightmapGI), o que dá só ~13 x 40 texels na face de uma porta — grosseiro
## demais pra uma peça que em VR se olha de perto. Os nomes acompanham a lista
## FOLHAS de tools/portas_uv_lightmap.py; manter os dois em sincronia.
const PORTAS_PREFIXO := "C-Porta-70#1_"
const PORTAS_AVULSAS := ["portaQuarto", "portaGuarda"]
const PORTAS_TEXEL_SCALE := 2.0

## Meio-ângulo do cone dos spots embutidos do forro.
## O Blender exporta esses spots com spot_size de 180°, que chega aqui como
## spot_angle 90° — um hemisfério. Com a fonte a poucos milímetros abaixo do
## forro, metade do cone bate no próprio teto a distância zero e a luminária
## vira um borrão estourado. 45° devolve o facho de spot.
const SPOT_ANGULO := 45.0


func _post_import(cena: Node) -> Object:
	_marcar(cena)
	return cena


func _marcar(no: Node) -> void:
	for filho in no.get_children():
		_marcar(filho)
	var spot := no as SpotLight3D
	if spot:
		_consertar_spot(spot)
	var mi := no as MeshInstance3D
	if mi and mi.mesh:
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if _tem_uv2(mi.mesh) else GeometryInstance3D.GI_MODE_DYNAMIC
		if _e_folha_de_porta(mi.name):
			mi.gi_lightmap_texel_scale = PORTAS_TEXEL_SCALE
			print("porta com texel_scale %.1f: %s" % [PORTAS_TEXEL_SCALE, mi.name])


## Cada luminária do forro traz DUAS luzes, e metade delas aponta pro teto: o
## empty da luminária vem girado -180° em Y, então a luz de rotação local zero
## acaba com o -Z (a direção que o SpotLight3D ilumina) virado pra cima.
##
## É feito aqui, no pós-import, e não no _ready da cena: assim a orientação
## certa fica gravada na cena importada e aparece também nos gizmos do editor.
## Como o teste é geométrico, spots novos que cheguem invertidos entram junto.
func _consertar_spot(spot: SpotLight3D) -> void:
	if spot.spot_angle > SPOT_ANGULO:
		spot.spot_angle = SPOT_ANGULO
	# global_transform não vale aqui: no pós-import o nó ainda não está na
	# árvore. Acumula os pais até a raiz da cena importada. E o teste tem que
	# ser no espaço do mundo mesmo: a luz invertida tem rotação LOCAL zero,
	# quem a vira de cabeça pra baixo é o empty da luminária (-180° em Y).
	var t := spot.transform
	var pai := spot.get_parent()
	while pai is Node3D:
		t = (pai as Node3D).transform * t
		pai = pai.get_parent()
	if -t.basis.z.y > 0.0:
		spot.rotate_object_local(Vector3.RIGHT, PI)
		print("spot invertido corrigido: %s" % spot.name)


func _e_folha_de_porta(nome: String) -> bool:
	return nome.begins_with(PORTAS_PREFIXO) or nome in PORTAS_AVULSAS


## O unwrap de UV2 do importador falha em parte da geometria vinda do 3ds Max
## (faces degeneradas, non-manifold). Sem UV2 não há lightmap possível.
func _tem_uv2(malha: Mesh) -> bool:
	for i in malha.get_surface_count():
		if (int(malha.surface_get_format(i)) & int(Mesh.ARRAY_FORMAT_TEX_UV2)) == 0:
			return false
	return true
