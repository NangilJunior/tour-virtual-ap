extends Node
## Portas internas interativas: cada folha de porta ganha um pivô na linha
## das dobradiças (objetos "G-dobradiça da porta" do modelo), colisão própria
## que gira junto, e abre/fecha com tecla E (desktop) ou gatilho do controle
## direito (VR). A porta sempre abre para o lado oposto ao jogador.

## Distância máxima do jogador até a porta para poder interagir (metros).
@export var alcance: float = 2.5
## Ângulo de abertura, em graus.
@export var angulo_abertura: float = 80.0
## Duração da animação de abrir/fechar, em segundos.
@export var duracao: float = 0.7
## Offset manual (metros) aplicado à posição do pivô de cada porta.
## Útil para ajustar sem mexer no Blender. Eixo local da porta:
## X = largura, Z = espessura.
@export var pivot_offset: Vector3 = Vector3.ZERO
## Mapeia padrão de nome da porta → sentido de rotação para abrir PARA
## DENTRO (+1.0 ou -1.0). Usa substring: a entrada mais longa que bater
## vence. Portas fora do dicionário usam detecção por física.
@export var portas_sentido: Dictionary = {
	"C-Porta-70#1_001": -1.0,
	"C-Porta-70#1_004": -1.0,
	"portaQuarto": 1.0,
}
## Mapeia padrão de nome da porta → nome de um Node3D na cena que
## serve como eixo de rotação. O nó deve existir na árvore da cena
## antes de portas.configurar(). Se encontrado, sobrepõe a detecção
## automática de dobradiça.
@export var eixos_manuais: Dictionary = {
	"C-Porta-70#1_002": "eixoPortaEsc",
	"C-Porta-70#1_001": "eixoPortaSui",
	"C-Porta-70#1_003": "eixoBanSoc",
	"C-Porta-70#1_004": "eixoBanSui",
	"portaQuarto": "eixoPortaCri",
}

## Pivôs criados, um por folha de porta.
var _pivos: Array[Node3D] = []

var _camera: Camera3D


func configurar(modelo: Node3D, player: CharacterBody3D) -> void:
	_camera = player.get_node("XROrigin3D/XRCamera3D")
	var mao_direita: XRController3D = player.get_node("XROrigin3D/RightHand")
	mao_direita.button_pressed.connect(_on_botao_vr)

	var folhas: Array[MeshInstance3D] = []
	var dobradicas: Array[Vector3] = []
	_coletar(modelo, folhas, dobradicas)
	# Também busca portas que já são filhas de eixos manuais (fora de Modelo)
	for padrao in eixos_manuais:
		if eixos_manuais[padrao].is_empty():
			continue
		var eixo_node := _encontrar_no(get_tree().root, eixos_manuais[padrao])
		if eixo_node == null:
			continue
		for filho in eixo_node.get_children():
			if filho is MeshInstance3D and filho.mesh != null and filho not in folhas:
				var nome := filho.name.to_lower()
				if "porta" in nome and "dobradi" not in nome and "batente" not in nome:
					folhas.append(filho)
					print("  porta em eixo manual: '%s' (em %s)" % [filho.name, eixo_node.name])

	for folha in folhas:
		var caixa := folha.global_transform * folha.get_aabb()
		var centro := caixa.get_center()
		var pivo: Node3D
		var eixo_node := _buscar_eixo_manual(folha.name)
		if eixo_node != null:
			pivo = eixo_node
			print("  eixo manual para '%s': %s → %.2f, %.2f, %.2f" % [
				folha.name, eixo_node.name,
				eixo_node.global_position.x, eixo_node.global_position.y,
				eixo_node.global_position.z])
		else:
			# dobradiças desta porta: as que estão a menos de 1 m do centro da folha
			var proximas: Array[Vector3] = []
			for d in dobradicas:
				if Vector2(d.x - centro.x, d.z - centro.z).length() < 1.0:
					proximas.append(d)
			var eixo: Vector3
			if proximas.size() >= 2:
				eixo = Vector3.ZERO
				for d in proximas:
					eixo += d
				eixo /= proximas.size()
			else:
				eixo = folha.global_position
			pivo = Node3D.new()
			pivo.name = folha.name + "_pivo"
			folha.get_parent().add_child(pivo)
			pivo.global_position = Vector3(eixo.x, caixa.position.y, eixo.z) + pivot_offset
		if folha.get_parent() != pivo:
			folha.reparent(pivo)
		folha.create_trimesh_collision()
		pivo.set_meta("aberta", false)
		pivo.set_meta("folha", folha)
		# RID do corpo estático da folha, para excluí-lo do teste de espaço
		for filho in folha.get_children():
			if filho is StaticBody3D:
				pivo.set_meta("corpo", (filho as StaticBody3D).get_rid())
		_pivos.append(pivo)
	print("Portas interativas: %d folhas preparadas" % _pivos.size())
	for p in _pivos:
		var f: MeshInstance3D = p.get_meta("folha")
		var pos := (f.global_transform * f.get_aabb()).get_center()
		print("  • %s  pos=(%.1f, %.1f, %.1f)" % [f.name, pos.x, pos.y, pos.z])


func _coletar(no: Node, folhas: Array[MeshInstance3D], dobradicas: Array[Vector3]) -> void:
	for filho in no.get_children():
		_coletar(filho, folhas, dobradicas)
	var nome := no.name.to_lower()
	var mi := no as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	if "dobradi" in nome and "porta" in nome:
		dobradicas.append((mi.global_transform * mi.get_aabb()).get_center())
	elif "porta" in nome and "dobradi" not in nome and "batente" not in nome:
		# abs(): componentes espelhados do SketchUp têm escala global negativa
		var t := mi.get_aabb().size * mi.global_transform.basis.get_scale().abs()
		var dims := [t.x, t.y, t.z]
		dims.sort()
		# folha: alta (1.8-2.3 m), largura 0.4-1.2, fina (< 15 cm)
		if 1.8 <= dims[2] and dims[2] <= 2.3 and 0.4 <= dims[1] and dims[1] <= 1.2 and dims[0] <= 0.15:
			folhas.append(mi)


func _buscar_eixo_manual(nome_folha: String) -> Node3D:
	var nome_lower := nome_folha.to_lower()
	var melhor_nome := ""
	var melhor_tam := 0
	for padrao in eixos_manuais:
		if padrao.to_lower() in nome_lower and padrao.length() > melhor_tam:
			melhor_tam = padrao.length()
			melhor_nome = eixos_manuais[padrao]
	if melhor_nome.is_empty():
		return null
	var raiz := get_tree().root
	return _encontrar_no(raiz, melhor_nome)


func _encontrar_no(no: Node, alvo: String) -> Node3D:
	if no.name == alvo:
		return no as Node3D
	for filho in no.get_children():
		var resultado := _encontrar_no(filho, alvo)
		if resultado != null:
			return resultado
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_E:
		_alternar_mais_proxima()


func _on_botao_vr(botao: String) -> void:
	if botao == "trigger_click":
		_alternar_mais_proxima()


func _alternar_mais_proxima() -> void:
	if _camera == null:
		return
	var origem := _camera.global_position
	var melhor: Node3D = null
	var melhor_dist := alcance
	for pivo in _pivos:
		var folha: MeshInstance3D = pivo.get_meta("folha")
		var d := origem.distance_to((folha.global_transform * folha.get_aabb()).get_center())
		if d < melhor_dist:
			melhor_dist = d
			melhor = pivo
	if melhor:
		_alternar(melhor)


func _alternar(pivo: Node3D) -> void:
	var aberta: bool = pivo.get_meta("aberta")
	var alvo := 0.0
	if not aberta:
		alvo = _sentido_de_abertura(pivo) * deg_to_rad(angulo_abertura)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(pivo, "rotation:y", alvo, duracao)
	pivo.set_meta("aberta", not aberta)


## Decide para que lado a porta abre.
## 1) Se o nome bate com uma entrada em [portas_sentido], usa o sentido
##    da entrada mais longa (mais específica).
## 2) Caso contrário, prioriza a direção mais longe do jogador.
func _sentido_de_abertura(pivo: Node3D) -> float:
	var folha: MeshInstance3D = pivo.get_meta("folha")
	print("DEBUG porta: nome='%s'" % folha.name)
	var nome_lower := folha.name.to_lower()
	var melhor_sentido: Variant = null
	var melhor_tam := 0
	var melhor_padrao := ""
	for padrao in portas_sentido:
		if padrao.to_lower() in nome_lower and padrao.length() > melhor_tam:
			melhor_tam = padrao.length()
			melhor_sentido = portas_sentido[padrao]
			melhor_padrao = padrao
	if melhor_sentido != null:
		print("  → força PARA DENTRO (sentido=%.1f, padrão='%s')" % [melhor_sentido, melhor_padrao])
		return melhor_sentido as float
	var caixa := folha.get_aabb()
	var forma := BoxShape3D.new()
	forma.size = caixa.size * folha.global_transform.basis.get_scale().abs() * 0.85
	var espaco := folha.get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if pivo.has_meta("corpo"):
		excluir.append(pivo.get_meta("corpo"))

	var hits := {}
	var dist_jogador := {}
	for sinal in [1.0, -1.0]:
		var rot := Basis(Vector3.UP, sinal * deg_to_rad(angulo_abertura))
		var t := folha.global_transform
		var rel := t.origin - pivo.global_position
		var pose_final := Transform3D(rot * t.basis, pivo.global_position + rot * rel)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = forma
		q.transform = pose_final * Transform3D(Basis(), caixa.get_center())
		q.exclude = excluir
		hits[sinal] = espaco.intersect_shape(q, 8).size()
		dist_jogador[sinal] = _camera.global_position.distance_to(q.transform.origin)
		print("  sinal=%+.1f  hits=%d  dist=%.2f" % [sinal, hits[sinal], dist_jogador[sinal]])

	var diff_dist := absf(dist_jogador[1.0] - dist_jogador[-1.0])
	if diff_dist > 0.3:
		var vencedor := 1.0 if dist_jogador[1.0] > dist_jogador[-1.0] else -1.0
		print("  → escolhido LONGE do jogador: %+.1f" % vencedor)
		return vencedor
	if hits[1.0] != hits[-1.0]:
		var vencedor := 1.0 if hits[1.0] < hits[-1.0] else -1.0
		print("  → escolhido MENOS colisões: %+.1f" % vencedor)
		return vencedor
	var vencedor := 1.0 if dist_jogador[1.0] > dist_jogador[-1.0] else -1.0
	print("  → empate, longe do jogador: %+.1f" % vencedor)
	return vencedor
