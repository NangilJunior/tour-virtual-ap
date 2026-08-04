extends Control
## Splash da Manch Studios: logo branca sobre fundo preto, logo depois da
## abertura da Godot (que é o boot splash do motor, antes de qualquer cena).
##
## Enquanto a logo está na tela, o apartamento carrega em segundo plano
## (ResourceLoader em thread). Sem isso a troca de cena travaria a janela por
## alguns segundos sem nada para ver — a cena tem centenas de megabytes de
## malha e textura.
##
## A splash dura [member duracao_total] e ponto: se o carregamento ainda não
## acabou quando o fade de saída termina, a espera que sobrar acontece já na
## tela preta, em vez de segurar a logo por tempo indeterminado.

## Cena que entra no lugar da splash.
const CENA_PRINCIPAL := "res://scenes/apartamento.tscn"

## Tempo total da splash, em segundos, fades incluídos.
@export var duracao_total: float = 4.0
## Tempo do fade de entrada da logo, em segundos.
@export var fade_entrada: float = 0.6
## Tempo do fade de saída, em segundos.
@export var fade_saida: float = 0.5

@onready var logo: TextureRect = $Centro/Logo


func _ready() -> void:
	var inicio := Time.get_ticks_msec()
	logo.modulate.a = 0.0
	# No navegador o motor roda em thread única e o carregamento em segundo
	# plano não dá conta: um script que herda de outro não consegue resolver a
	# classe base durante o load_threaded_request, e a cena do apartamento
	# chegava sem script nenhum — sem colisão, sem portas e com o menu de VR
	# preso na tela. Lá a splash só marca o tempo e a cena é carregada de uma
	# vez, pelo caminho normal.
	var em_thread := not _e_web()
	if em_thread:
		# Sem sub-threads: a cena é uma árvore só, e o ganho não compensa o
		# risco de importadores que não são thread-safe.
		ResourceLoader.load_threaded_request(CENA_PRINCIPAL, "PackedScene", false)

	await _fade(1.0, fade_entrada)
	var espera := duracao_total - fade_saida - (Time.get_ticks_msec() - inicio) / 1000.0
	if espera > 0.0:
		await get_tree().create_timer(espera).timeout
	await _fade(0.0, fade_saida)

	if not em_thread:
		get_tree().change_scene_to_file(CENA_PRINCIPAL)
		return

	# Bloqueia aqui só pelo que faltar do carregamento, com a tela já preta.
	var cena := ResourceLoader.load_threaded_get(CENA_PRINCIPAL) as PackedScene
	if cena == null:
		# Carregamento em thread falhou (ou foi descartado): cai no caminho
		# síncrono, que trava um instante mas sempre funciona.
		push_warning("Splash: carregamento em thread falhou, indo pelo caminho síncrono.")
		get_tree().change_scene_to_file(CENA_PRINCIPAL)
		return
	get_tree().change_scene_to_packed(cena)


## true quando o tour está rodando dentro de um navegador (ver main.gd, que
## faz a mesma checagem dupla pelo mesmo motivo).
func _e_web() -> bool:
	return OS.has_feature("web") or OS.get_name() == "Web"


func _fade(alvo: float, duracao: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(logo, "modulate:a", alvo, duracao)
	await tween.finished
