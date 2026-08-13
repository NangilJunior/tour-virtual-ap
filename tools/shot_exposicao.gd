extends SceneTree
## Matriz de diagnóstico de brilho: as mesmas poses renderizadas com um knob de
## cada vez alterado, pra separar o que vem do bake, do sol, do céu e do
## pós-processamento.
##
## Uso:
##     godot --path . --script tools/shot_exposicao.gd -- <pasta_saida>

const LARGURA := 1280
const ALTURA := 900

## Só poses conferidas como interior — as duas primeiras tentativas caíram
## apontando pro céu e dentro de uma parede, e os números saíram sem sentido.
const POSES := [
	["sala_jantar_teto", 7.8, 1.6, -1.0, 180.0, 35.0],
	["sala_jantar_olho", 7.8, 1.6, -1.0, 180.0, 0.0],
	["quarto_criancas_teto", 1.3, 1.6, -1.8, 180.0, 30.0],
	["quarto_criancas_olho", 1.3, 1.6, -1.8, 180.0, 0.0],
	["suite_olho", 1.9, 1.6, -5.0, 180.0, 0.0],
]

var _env: Environment
var _sol: DirectionalLight3D
var _lm: LightmapGI
var _lm_data: LightmapGIData


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

	_env = (raiz.get_node("WorldEnvironment") as WorldEnvironment).environment
	_sol = raiz.get_node("Sun") as DirectionalLight3D
	_lm = raiz.get_node("LightmapGI") as LightmapGI
	_lm_data = _lm.light_data

	var cam := Camera3D.new()
	cam.fov = 80.0
	vp.add_child(cam)
	cam.make_current()

	for i in 40:
		await process_frame

	# nome -> o que muda em relação ao estado atual da cena
	var variantes := {
		"1_atual": func() -> void: pass,
		"2_ceu_060": func() -> void: _env.background_energy_multiplier = 0.6,
		"3_ceu_040": func() -> void: _env.background_energy_multiplier = 0.4,
		"4_ambiente_ceu_050": func() -> void:
			_env.ambient_light_sky_contribution = 0.5
			_env.ambient_light_color = Color(0.35, 0.38, 0.45)
			_env.ambient_light_energy = 0.3,
		"5_glow_030": func() -> void: _env.glow_intensity = 0.3,
		"6_combo": func() -> void:
			_env.tonemap_exposure = 0.75
			_env.glow_intensity = 0.3,
		"7_combo_forte": func() -> void:
			_env.tonemap_exposure = 0.7
			_env.glow_intensity = 0.25
			_env.background_energy_multiplier = 0.6,
	}

	for nome in variantes:
		_restaurar()
		(variantes[nome] as Callable).call()
		for p in POSES:
			cam.global_position = Vector3(p[1], p[2], p[3])
			cam.global_rotation = Vector3(deg_to_rad(p[5]), deg_to_rad(p[4]), 0.0)
			for i in 8:
				await process_frame
				await RenderingServer.frame_post_draw
			var caminho := "%s/%s__%s.png" % [saida, p[0], nome]
			vp.get_texture().get_image().save_png(caminho)
			print("salvo ", caminho)
	quit(0)


## Volta a cena ao estado de disco antes de aplicar a próxima variante.
func _restaurar() -> void:
	_lm.light_data = _lm_data
	_env.tonemap_exposure = 1.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.adjustment_enabled = true
	_env.ambient_light_energy = 0.08
	_env.ambient_light_sky_contribution = 1.0
	_env.background_energy_multiplier = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_sol.light_energy = 1.0
