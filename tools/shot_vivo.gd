extends SceneTree
## Render com o script da cena ATIVO (o shot_cena.gd zera o script, e aí os
## ajustes feitos no _ready — colisão, cone dos spots — não aparecem).

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var saida: String = a[0]
	var pos := Vector3(float(a[1]), float(a[2]), float(a[3]))
	var yaw := float(a[4])
	var pitch := float(a[5]) if a.size() > 5 else 0.0

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	get_root().add_child(vp)

	var raiz: Node3D = (load("res://scenes/apartamento.tscn") as PackedScene).instantiate()
	vp.add_child(raiz)
	for i in 60:
		await process_frame

	for m in ["ModoMenu", "MenuPausa"]:
		var n := raiz.get_node_or_null(m) as CanvasLayer
		if n: n.visible = false
	var cam := Camera3D.new()
	cam.fov = 75.0
	vp.add_child(cam)
	cam.make_current()
	cam.global_position = pos
	cam.global_rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	for i in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(saida)
	print("SHOT|%s" % saida)
	quit(0)
