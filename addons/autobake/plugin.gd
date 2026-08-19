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

	# A cena passa de 100 MiB e o tempo de abertura varia demais pra uma espera
	# fixa (8 s já falhou em 2026-08-19). Sonda até o LightmapGI existir.
	var raiz: Node = null
	var lm: LightmapGI = null
	# O editor restaura a sessão depois do _enter_tree e sobrepõe a cena que
	# pedimos (em 2026-08-19 caiu na splash.tscn), então reemitimos a abertura
	# a cada 10 s até a apartamento.tscn virar a cena editada.
	for i in 300:
		await get_tree().create_timer(1.0).timeout
		raiz = ei.get_edited_scene_root()
		if raiz != null and raiz.name == "Apartamento":
			lm = raiz.get_node_or_null("LightmapGI")
			if lm != null:
				print("AUTOBAKE|cena pronta em %ds" % (i + 1))
				break
		elif i % 10 == 9:
			print("AUTOBAKE|reemitindo abertura (raiz=%s)" % (raiz.name if raiz else "<nula>"))
			ei.open_scene_from_path("res://scenes/apartamento.tscn")
	if lm == null:
		printerr("AUTOBAKE|LightmapGI nao encontrado (raiz=%s)" % (raiz.name if raiz else "<nula>"))
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
	# Teto de 2h: com quality=2 + bounces=4 + supersampling + texel_scale=2 o
	# bake passa fácil dos 20 min do teto antigo, e estourar aqui mata o editor
	# no meio do bake (quit(3)) — melhor esperar demais do que perder o bake.
	for i in 7200:
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
