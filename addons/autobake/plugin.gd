@tool
extends EditorPlugin
## Automatiza o Bake Lightmaps da apartamento.tscn quando o editor abre com
## AUTOBAKE=1 no ambiente. Sai do editor ao terminar (código 0) ou após
## timeout. Ferramenta de pipeline — inofensiva sem a variável de ambiente.


func _enter_tree() -> void:
	if OS.get_environment("AUTOBAKE") == "1":
		_executar.call_deferred()


func _executar() -> void:
	var ei := get_editor_interface()
	print("AUTOBAKE|abrindo cena")
	ei.open_scene_from_path("res://scenes/apartamento.tscn")
	await get_tree().create_timer(8.0).timeout

	var raiz := ei.get_edited_scene_root()
	if raiz == null:
		printerr("AUTOBAKE|cena nao abriu")
		get_tree().quit(2)
		return
	var lm: LightmapGI = raiz.get_node_or_null("LightmapGI")
	if lm == null:
		printerr("AUTOBAKE|LightmapGI nao encontrado")
		get_tree().quit(2)
		return

	ei.get_selection().clear()
	ei.get_selection().add_node(lm)
	await get_tree().create_timer(2.0).timeout

	var botao := _acha_botao_bake(ei.get_base_control())
	if botao == null:
		printerr("AUTOBAKE|botao de bake nao encontrado")
		get_tree().quit(2)
		return

	# NÃO zerar lm.light_data: com ele preenchido o bake sobrescreve o
	# .lmbake em silêncio; zerado, o editor abre um diálogo de confirmação
	# que fica preso atrás do modal de progresso (deadlock).
	var caminho := "res://scenes/apartamento.lmbake"
	var antes := FileAccess.get_modified_time(caminho)
	print("AUTOBAKE|clicando: ", botao.text)
	botao.pressed.emit()

	# fim do bake = o arquivo .lmbake foi reescrito.
	for i in 1200:
		await get_tree().create_timer(1.0).timeout
		if FileAccess.get_modified_time(caminho) > antes:
			print("AUTOBAKE|bake concluido")
			await get_tree().create_timer(3.0).timeout
			ei.save_scene()
			await get_tree().create_timer(2.0).timeout
			print("AUTOBAKE|cena salva, saindo")
			get_tree().quit(0)
			return
	printerr("AUTOBAKE|timeout esperando o bake")
	get_tree().quit(3)


func _acha_botao_bake(no: Node) -> Button:
	var b := no as Button
	if b and "Lightmap" in b.text:
		return b
	for filho in no.get_children():
		var achado := _acha_botao_bake(filho)
		if achado:
			return achado
	return null
