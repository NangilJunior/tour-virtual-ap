extends SceneTree
## Render de diagnóstico das folhas de porta com o lightmap assado.
##
## Abre a apartamento.tscn fora do editor, planta uma câmera de frente para cada
## porta e salva um PNG por porta. Serve pra conferir o resultado do bake sem
## precisar entrar em VR.
##
## Uso:
##     godot --path . --script tools/shot_portas.gd -- <pasta_de_saida>
##
## O script do main é removido antes de instanciar a cena: senão o _ready dele
## entra em modo desktop, joga a janela em fullscreen e captura o mouse.

const PORTAS := [
	"C-Porta-70#1_001", "C-Porta-70#1_002", "C-Porta-70#1_003",
	"C-Porta-70#1_004", "C-Porta-70#1_005", "portaQuarto", "portaGuarda",
]


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var saida: String = argv[0] if argv.size() > 0 else "/tmp"

	DisplayServer.window_set_size(Vector2i(1280, 960))

	var cena: PackedScene = load("res://scenes/apartamento.tscn")
	var raiz: Node3D = cena.instantiate()
	raiz.set_script(null)
	# A XRCamera3D do XRPlayer vira a câmera corrente no _ready dele e rouba o
	# render — sem tirar o player do caminho, todos os PNGs saem iguais.
	var player := raiz.get_node_or_null("XRPlayer")
	if player:
		raiz.remove_child(player)
		player.queue_free()
	# O ModoMenu tem um ColorRect de fundo em tela cheia; sem o script do main
	# pra escondê-lo ele tapa a cena 3D inteira no PNG.
	for menu_nome in ["ModoMenu", "MenuPausa"]:
		var menu := raiz.get_node_or_null(menu_nome) as CanvasLayer
		if menu:
			menu.visible = false
	root.add_child(raiz)

	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()

	# Alguns frames pra o LightmapGI se registrar antes do primeiro disparo.
	for i in 30:
		await process_frame

	for nome in PORTAS:
		var mi := _achar(raiz, nome) as MeshInstance3D
		if mi == null:
			print("AUSENTE: ", nome)
			continue

		var aabb := mi.global_transform * mi.get_aabb()
		var centro := aabb.get_center()
		# Olha a porta pela face mais larga: recua na direção do menor lado.
		var t := aabb.size
		var eixo := Vector3.RIGHT if t.x < t.z else Vector3.BACK
		# Qual lado da porta dá pra sala e qual dá pro cômodo vizinho depende de
		# cada porta; captura os dois e deixa a escolha para quem olha.
		for lado in [1.0, -1.0]:
			cam.global_position = centro + eixo * lado * 1.6 + Vector3.UP * 0.1
			cam.look_at(centro, Vector3.UP)

			# process_frame sozinho devolve frame velho (o projeto roda com
			# thread_model=2, render em thread separada): a imagem do viewport
			# só está pronta depois de frame_post_draw.
			for i in 4:
				await process_frame
				await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var arq := "%s/porta_%s_lado%s.png" % [
				saida, nome.replace("#", "").replace("-", "_"),
				"A" if lado > 0.0 else "B"]
			img.save_png(arq)
			print("salvo %s  (centro %.2f, %.2f, %.2f  gi=%d texel_scale=%.1f)"
				% [arq, centro.x, centro.y, centro.z, mi.gi_mode, mi.gi_lightmap_texel_scale])

	quit(0)


func _achar(no: Node, nome: String) -> Node:
	if no.name == nome:
		return no
	for filho in no.get_children():
		var achado := _achar(filho, nome)
		if achado:
			return achado
	return null
