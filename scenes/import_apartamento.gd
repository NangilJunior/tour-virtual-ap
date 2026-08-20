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

## Meio-ângulo do cone dos spots embutidos.
## O Blender exporta esses spots com spot_size de 180°, que chega aqui como
## spot_angle 90° — um hemisfério, que não é facho de spot nenhum.
const SPOT_ANGULO := 45.0

## Corpo negro a 3500 K em sRGB. Toda luz do modelo entra nesta temperatura,
## igual às da apartamento.tscn, pra não misturar tons de fonte.
const COR_3500K := Color(1.0, 0.7803, 0.5459)

## Alcance dos spots convertidos a partir das luzes pontuais do modelo.
const SPOT_ALCANCE := 6.0

## Corpo negro a 3000 K em sRGB, para os planes emissivos ("Luz") das sancas
## e do forro. Mais quente que os 3500 K das luzes porque o tonemap é AgX, que
## lava a saturação das altas luzes: o material vinha em ~3700 K e chegava na
## tela praticamente branco (saturação 0,073). A 3000 K sobe para 0,137 sem
## mexer na energia, ou seja, sem tirar luz do ambiente.
const COR_3000K := Color(1.0, 0.7211, 0.4293)


## Raiz da cena importada. Todo nó criado aqui precisa dela como owner, senão
## não é gravado no .scn.
var _raiz: Node = null


func _post_import(cena: Node) -> Object:
	_raiz = cena
	_marcar(cena)
	return cena


func _marcar(no: Node) -> void:
	for filho in no.get_children():
		_marcar(filho)
	var spot := no as SpotLight3D
	if spot:
		_consertar_spot(spot)
	var omni := no as OmniLight3D
	if omni:
		_virar_spot(omni)
	var mi := no as MeshInstance3D
	if mi and mi.mesh:
		_ajustar_emissivos(mi.mesh)
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if _tem_uv2(mi.mesh) else GeometryInstance3D.GI_MODE_DYNAMIC
		if _e_folha_de_porta(mi.name):
			mi.gi_lightmap_texel_scale = PORTAS_TEXEL_SCALE
			print("porta com texel_scale %.1f: %s" % [PORTAS_TEXEL_SCALE, mi.name])


## Cada luminária traz DUAS luzes: uma joga no alvo (1 a 2,5 m abaixo) e a
## outra aponta pro lado oposto, contra a superfície que está a 2-3 cm — o
## forro nos embutidos, a prateleira de cima nos spots de marcenaria. Essa
## segunda luz não ilumina nada: só estoura o que encosta nela.
##
## Antes eu virava essa luz pra baixo, o que era pior — ficavam duas luzes
## iguais no mesmo cone, dobrando a energia justo nos spots de móvel. O certo
## é desligá-la. Fica invisível em vez de removida: apagar nó de cena importada
## já quebrou as referências do LightmapGI antes.
##
## É feito no pós-import, e não no _ready: assim vale também no bake e nos
## gizmos do editor. O teste é geométrico, então spot novo entra junto.
func _consertar_spot(spot: SpotLight3D) -> void:
	if spot.spot_angle > SPOT_ANGULO:
		spot.spot_angle = SPOT_ANGULO
	spot.light_color = COR_3500K
	# global_transform não vale aqui: no pós-import o nó ainda não está na
	# árvore. Acumula os pais até a raiz da cena importada. E o teste tem que
	# ser no espaço do mundo: a luz invertida tem rotação LOCAL zero, quem a
	# vira de cabeça pra baixo é o empty da luminária (-180° em Y).
	if -_mundo(spot).basis.z.y > 0.0:
		spot.visible = false
		spot.light_bake_mode = Light3D.BAKE_DISABLED
		print("spot contra a superfície desligado: %s" % spot.name)


## As luzes do trilho da sala e o spot avulso vêm como POINT, que no Godot é
## OmniLight3D e ilumina os 360°. Viram spots apontando pra baixo.
func _virar_spot(omni: OmniLight3D) -> void:
	var spot := SpotLight3D.new()
	spot.name = omni.name
	spot.light_color = COR_3500K
	spot.light_energy = omni.light_energy
	spot.light_bake_mode = omni.light_bake_mode
	spot.shadow_enabled = omni.shadow_enabled
	spot.spot_range = maxf(omni.omni_range, SPOT_ALCANCE)
	spot.spot_angle = SPOT_ANGULO
	# mesma posição, mirando pra baixo. A base do pai pode estar girada, então
	# a rotação é desfeita no espaço do pai antes de apontar o -Z para -Y.
	var base_pai := _mundo(omni).basis * omni.transform.basis.inverse()
	spot.transform = Transform3D(base_pai.inverse() * Basis(Vector3.RIGHT, -PI / 2.0), omni.transform.origin)
	var pai := omni.get_parent()
	pai.add_child(spot)
	spot.owner = _raiz
	pai.remove_child(omni)
	omni.queue_free()
	print("omni virou spot: %s" % spot.name)


## Leva os planes emissivos de iluminação para 3000 K. Só os materiais "Luz*",
## que são os painéis/sancas; o vidro dos spots e as lâmpadas das luminárias
## ficam como estão. Os materiais são compartilhados, então o set repete sem
## custo — o _vistos evita só o trabalho redundante.
var _vistos: Dictionary = {}


func _ajustar_emissivos(malha: Mesh) -> void:
	for i in malha.get_surface_count():
		var m := malha.surface_get_material(i) as StandardMaterial3D
		if m == null or not m.emission_enabled:
			continue
		if not m.resource_name.begins_with("Luz"):
			continue
		if _vistos.has(m.get_instance_id()):
			continue
		_vistos[m.get_instance_id()] = true
		m.emission = COR_3000K
		print("plane emissivo a 3000K: %s (energia %.1f)" % [m.resource_name, m.emission_energy_multiplier])


## Transform acumulada até a raiz (global_transform não existe fora da árvore).
func _mundo(no: Node3D) -> Transform3D:
	var t := no.transform
	var pai := no.get_parent()
	while pai is Node3D:
		t = (pai as Node3D).transform * t
		pai = pai.get_parent()
	return t


func _e_folha_de_porta(nome: String) -> bool:
	return nome.begins_with(PORTAS_PREFIXO) or nome in PORTAS_AVULSAS


## O unwrap de UV2 do importador falha em parte da geometria vinda do 3ds Max
## (faces degeneradas, non-manifold). Sem UV2 não há lightmap possível.
func _tem_uv2(malha: Mesh) -> bool:
	for i in malha.get_surface_count():
		if (int(malha.surface_get_format(i)) & int(Mesh.ARRAY_FORMAT_TEX_UV2)) == 0:
			return false
	return true
