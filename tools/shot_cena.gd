extends SceneTree
## Render de diagnóstico a partir de um ponto/ângulo, em resolução fixa.
##
## Usa um SubViewport em vez da janela: o compositor do desktop redimensiona a
## janela e dois runs saem com tamanhos diferentes, o que impede comparar PNGs.
##
## Uso:
##     godot --path . --script tools/shot_cena.gd -- <saida> <x> <y> <z> <yaw> [ab]
##
## Com o argumento "ab" renderiza dois PNGs do mesmo enquadramento — um com os
## mapas de normal/AO do parede_greige ligados e outro sem — para isolar o que
## eles mudam.

const LARGURA := 1280
const ALTURA := 900


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var saida: String = a[0]
	var pos := Vector3(float(a[1]), float(a[2]), float(a[3]))
	var yaw := float(a[4])
	var ab := a.size() > 5 and a[5] == "ab"

	var vp := SubViewport.new()
	vp.size = Vector2i(LARGURA, ALTURA)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Sem World3D próprio o SubViewport tenta usar o mundo da janela e a cena
	# instanciada aqui dentro não entra no render — sai só o céu.
	vp.own_world_3d = true
	root.add_child(vp)

	var raiz: Node3D = (load("res://scenes/apartamento.tscn") as PackedScene).instantiate()
	raiz.set_script(null)
	var pl := raiz.get_node_or_null("XRPlayer")
	if pl:
		raiz.remove_child(pl)
		pl.queue_free()
	for m in ["ModoMenu", "MenuPausa"]:
		var n := raiz.get_node_or_null(m) as CanvasLayer
		if n:
			n.visible = false
	vp.add_child(raiz)

	var cam := Camera3D.new()
	cam.fov = 75.0
	vp.add_child(cam)
	cam.make_current()

	for i in 40:
		await process_frame

	cam.global_position = pos
	cam.global_rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)

	var mat: StandardMaterial3D = load("res://assets/materials/parede_greige.tres")
	await _salvar(vp, "%s/com_pbr.png" % saida)

	if ab:
		# Só desliga o que foi acrescentado; albedo e triplanar continuam iguais.
		mat.normal_enabled = false
		mat.ao_enabled = false
		mat.roughness_texture = null
		mat.roughness = 0.85
		await _salvar(vp, "%s/sem_pbr.png" % saida)
	quit(0)


func _salvar(vp: SubViewport, caminho: String) -> void:
	for i in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(caminho)
	print("salvo ", caminho)
