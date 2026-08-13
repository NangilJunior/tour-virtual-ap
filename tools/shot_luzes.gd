extends SceneTree
## Renders de diagnóstico das luminárias: várias poses num único carregamento
## da cena (shot_cena.gd recarrega tudo a cada chamada e só aceita yaw).
##
## Uso:
##     godot --path . --script tools/shot_luzes.gd -- <pasta_saida>
##
## Cada pose é "nome x y z yaw pitch": pitch positivo olha pra cima, que é
## onde as manchas circulares aparecem (teto e alto das paredes).

const LARGURA := 1280
const ALTURA := 900

const POSES := [
	["sala_estar_teto", 7.5, 1.6, -6.2, 0.0, 35.0],
	["sala_estar_parede", 6.0, 1.6, -4.5, 90.0, 10.0],
	["sala_jantar_teto", 7.8, 1.6, -1.0, 180.0, 35.0],
	["cozinha_teto", 9.5, 1.6, -1.2, 180.0, 35.0],
	["suite_teto", 1.9, 1.6, -5.0, 180.0, 35.0],
	["quarto_criancas_teto", 2.3, 1.6, -2.6, 180.0, 35.0],
	["corredor_teto", 1.3, 1.6, -1.8, 180.0, 30.0],
	["escritorio_teto", 3.0, 1.6, -3.2, 180.0, 35.0],
]


func _initialize() -> void:
	var saida: String = OS.get_cmdline_user_args()[0]

	var vp := SubViewport.new()
	vp.size = Vector2i(LARGURA, ALTURA)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	cam.fov = 80.0
	vp.add_child(cam)
	cam.make_current()

	for i in 40:
		await process_frame

	for p in POSES:
		cam.global_position = Vector3(p[1], p[2], p[3])
		cam.global_rotation = Vector3(deg_to_rad(p[5]), deg_to_rad(p[4]), 0.0)
		for i in 6:
			await process_frame
			await RenderingServer.frame_post_draw
		var caminho := "%s/%s.png" % [saida, p[0]]
		vp.get_texture().get_image().save_png(caminho)
		print("salvo ", caminho)
	quit(0)
